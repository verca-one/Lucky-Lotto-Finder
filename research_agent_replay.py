"""
research_agent_replay.py — 전국 지방장 에이전트 '실전형 순차 재현' + 실전 자동 운영 (ag-1.1, 2026-10-11)

기존 크롤링·ag-1.0 백테스트·1246회 ag-1.0 실전 스냅샷은 읽기만 한다. research_v6_replay.sql 의 계보 테이블과
(실전 회차에 한해) research_agent_* 테이블의 model_version='ag-1.1' 행만 쓴다. 외부 유료 AI API 0회.

회차 t (1000 ≤ t ≤ 마지막 실제 결과 회차) 마다:
  A. 상태 = t-1 회차까지의 결과만 반영된 엔진 (감쇠 통계·가설·검증 누적)
  B/C. 중앙 엔진 지역 점수 + 238 지방장 판매점 평가 → 지역별 상위 5곳 납품 → 중앙 통합 추천
  D. 예측 동결 (prediction_snapshot_id = 'ag-1.1-r1:t', 사전 브리핑) — 이미 동결된 회차는 저장본으로 평가
  E. 실제 결과 공개 (t 회차 1·2등 판매점, 판매점 ID 매칭 상태)
  F. 사후 검증 (지방장·순위별 적중, 이력·무작위 기준, 확률 점수 log-loss, 중앙 엔진 지역·판매점)
  G. 연구 갱신 (가설 순방향 검정·상태 변화, t 이하 데이터로 신규 가설 발굴·공유: 매 회차 유의 발견,
     50회마다 탐색 후보·추세·복합까지 전체 발굴) → 다음 회차부터 적용
  H. 사후 브리핑
마지막 실제 회차 후에는 다음 미추첨 회차를 'live' 로 동결한다 (다음 실행 때 저장본 그대로 검증).

엔진 상태는 Supabase Storage(비공개 버킷 research-state)에 저장해 다음 실행은 새 회차만 처리한다.
상태가 없거나 손상되면 999회 기준선부터 다시 재현한다 (계산만 다시 하고 이미 동결된 기록은 덮어쓰지 않음).

사용:
  python research_agent_replay.py                       # 서버 (service_role)
  python research_agent_replay.py --dry-run --out x.json --state-dir ./state   # 로컬 계산 검증 (DB 쓰기 없음)
  python research_agent_replay.py --dry-run --until 1100 --state-dir ./state   # 중간까지 → 이어서 실행으로 재개 검증
환경변수: SUPABASE_URL, SUPABASE_KEY
"""
import argparse, gzip, hashlib, io, json, math, os, pickle, sys, time
from collections import Counter, defaultdict
from datetime import datetime, timezone

import numpy as np
import requests

import research_agent_worker as W
from research_agent_worker import (Universe, Engine, discover, store_rates, region_rates, tune, TUNED, load, key_role,
                                   h_summary, summarize_h, dv_central, STATUS, S_DISC, S_RES, S_PASS, S_WEAK, S_REJ, S_COMB,
                                   BOOST_KINDS, K_DELIVER, LEARN_START, CP_FIRST, CP_STEP, FACTOR_CAP)
from research_region_worker import Db, clean, _json_default, log

MODEL = "ag-1.1"
RUN_ID = "ag-1.1-r1"
# 2026-10-12 무결성 점검: 정렬 없는 offset 페이지 조회 결함을 고친 뒤(키셋 조회) 1000~1246회를 다시 계산해
# 저장된 247개 스냅샷 해시와 비교 → 전부 일치 (이 계보는 오염되지 않음). 결과를 data_provenance 에 기록한다.
INTEGRITY_CHECK = {"date": "2026-10-12", "method": "키셋(id) 정렬 조회로 1000~1246회 순차 재계산 후 저장 스냅샷 해시 비교",
                   "result": "247/247 일치 — 학습 입력 오염 없음", "checked_by": "로컬 재계산(읽기 전용)"}
REPLAY_MODE = "sequential_replay+live"
STATE_VERSION = 1
BUCKET = "research-state"
STORE_SHARED_KINDS = {"store_lead", "store_cowin", "region_store_lead", "store_cycle", "store_spill", "composite",
                      "cycle_pooled", "neighbor_spill"}
WRITE_EVERY = 10          # 회차 묶음 저장
STATE_EVERY = 25          # 상태 저장 주기 (재개 지점)
REPLAY_TABLES = ["research_replay_runs", "research_replay_predictions", "research_replay_agent_predictions",
                 "research_replay_results", "research_replay_agent_evals", "research_replay_central_evals",
                 "research_replay_hypotheses", "research_replay_hypothesis_events", "research_replay_briefings",
                 "research_replay_checkpoints"]


def now():
    return datetime.now(timezone.utc).isoformat()


def snap_id(t):
    return f"{RUN_ID}:{t}"


def rnd(o):
    """저장 용량 절감: 실수는 유효숫자 6자리"""
    if isinstance(o, float):
        return float(f"{o:.6g}") if math.isfinite(o) else None
    if isinstance(o, dict):
        return {k: rnd(v) for k, v in o.items()}
    if isinstance(o, list):
        return [rnd(v) for v in o]
    return o


# ── 상태 저장소 ────────────────────────────────────────────────────
class StateStore:
    def __init__(self, db=None, key=None, local_dir=None):
        self.db, self.key, self.dir = db, key, local_dir

    def _h(self, extra=None):
        h = {"apikey": self.key}
        if not self.key.startswith("sb_"):
            h["Authorization"] = f"Bearer {self.key}"
        h.update(extra or {})
        return h

    def _base(self):
        return self.db.base.replace("/rest/v1/", "/storage/v1/")

    def ensure_bucket(self):
        if self.dir:
            os.makedirs(self.dir, exist_ok=True)
            return
        r = requests.post(self._base() + "bucket", headers=self._h({"Content-Type": "application/json"}),
                          data=json.dumps({"id": BUCKET, "name": BUCKET, "public": False}), timeout=60)
        if r.status_code not in (200, 201) and "already exists" not in r.text.lower() and r.status_code != 409:
            log(f"[state] bucket {r.status_code} {r.text[:200]}")

    def save(self, name, obj):
        blob = gzip.compress(pickle.dumps(obj, protocol=pickle.HIGHEST_PROTOCOL), compresslevel=6)
        if self.dir:
            open(os.path.join(self.dir, name), "wb").write(blob)
            return len(blob)
        for attempt in range(3):
            r = requests.post(self._base() + f"object/{BUCKET}/{RUN_ID}/{name}", data=blob,
                              headers=self._h({"Content-Type": "application/octet-stream", "x-upsert": "true"}), timeout=300)
            if r.status_code in (200, 201):
                return len(blob)
            log(f"[state] upload {r.status_code} {r.text[:200]} (attempt {attempt + 1})")
            time.sleep(5)
        raise RuntimeError("state upload failed")

    def load(self, name):
        try:
            if self.dir:
                p = os.path.join(self.dir, name)
                if not os.path.exists(p):
                    return None
                blob = open(p, "rb").read()
            else:
                r = requests.get(self._base() + f"object/authenticated/{BUCKET}/{RUN_ID}/{name}", headers=self._h(), timeout=300)
                if r.status_code != 200:
                    log(f"[state] {name} 없음 ({r.status_code})")
                    return None
                blob = r.content
            return pickle.loads(gzip.decompress(blob))
        except Exception as e:
            log(f"[state] 로드 실패 {e}")
            return None


# ── 엔진 상태 복원 ────────────────────────────────────────────────
def fingerprint(u, upto_row, ncodes):
    h = hashlib.sha1()
    h.update(np.ascontiguousarray(u.E[:upto_row + 1, :ncodes]).tobytes())
    h.update(np.ascontiguousarray(u.F[:upto_row + 1, :ncodes]).tobytes())
    return h.hexdigest()


def attach(eng, u):
    """새 Universe(판매점·지역 뒤에 추가만 됨)에 엔진 배열 크기를 맞춘다"""
    S0, U0 = len(eng.kw), len(eng.kR)
    if u.S > S0:
        eng.kw = np.concatenate([eng.kw, np.zeros(u.S - S0)])
        eng.last_ev = np.concatenate([eng.last_ev, np.full(u.S - S0, -10 ** 6)])
        eng.lam0 = np.zeros(u.S)
    if u.U > U0:
        for f in ("kR", "kF", "kF_cum"):
            setattr(eng, f, np.concatenate([getattr(eng, f), np.zeros(u.U - U0)]))
    eng.u = u
    eng.rebuild()


class Track:
    """가설 실전 적용 추적 + 지방장 회차별 성과 (상태에 함께 저장)"""

    def __init__(self):
        self.first_live = np.zeros(0, int)
        self.first_explore = np.zeros(0, int)
        self.cnt_live = np.zeros(0, int)
        self.cnt_explore = np.zeros(0, int)
        self.rounds = []           # 회차별 {"t", per-agent arrays}
        self.central = []          # 회차별 중앙 지표

    def grow(self, H):
        g = H - len(self.first_live)
        if g > 0:
            self.first_live = np.concatenate([self.first_live, np.full(g, -1)])
            self.first_explore = np.concatenate([self.first_explore, np.full(g, -1)])
            self.cnt_live = np.concatenate([self.cnt_live, np.zeros(g, int)])
            self.cnt_explore = np.concatenate([self.cnt_explore, np.zeros(g, int)])


# ── 회차 처리 ─────────────────────────────────────────────────────
def predict(u, eng, ti, target):
    """t-1 까지의 정보로 예측 (동시 당첨 등 t 회차 결과가 필요한 가설은 발화 계산에서 제외)"""
    fire, trials, expv, targets, reg_targets = eng.fire(ti, with_cowin=False)
    dv = eng.deliver(ti, fire & eng.pred, targets, reg_targets)
    live_mask = np.isin(eng.status, (S_PASS, S_COMB))
    explore_mask = np.isin(eng.status, (S_DISC, S_RES, S_WEAK, S_PASS, S_COMB))
    applied_live = fire & live_mask & eng.boost
    applied_explore = fire & explore_mask & eng.boost
    per_store_live = defaultdict(list)
    for i in np.where(applied_live)[0]:
        tg = targets.get(i)
        stores_ = tg if tg is not None else (u.members[u.aidx[u.reg_ids[reg_targets[i]]]] if i in reg_targets else [])
        for s in stores_:
            per_store_live[int(s)].append(eng.st.H[i]["hypothesis_id"])
    return dict(dv=dv, applied_live=applied_live, applied_explore=applied_explore, per_store_live=per_store_live,
                fire=fire, targets=targets, reg_targets=reg_targets, target=target, ti=ti)


def prediction_rows(u, eng, pr, avail, mode, created):
    dv, t = pr["dv"], pr["target"]
    sid = snap_id(t)
    c = dv_central(u, dv, all_regions=True)
    agent_rows = []
    lists = {}
    for a, ag in enumerate(u.agent_ids):
        lst = [int(s) for s in dv["live"][a]]
        lists[ag] = [u.codes[s] for s in lst]
        app = [pr["per_store_live"].get(s, []) for s in lst]
        agent_rows.append({"prediction_snapshot_id": sid, "agent_id": ag, "replay_run_id": RUN_ID, "model_version": MODEL,
                           "target_round": t, "available_data_through_round": avail, "region_id": ag,
                           "store_ids": lists[ag], "scores": [float(dv["s_live"][s]) for s in lst],
                           "p_first": [],          # = scores × 1등 비중 (용량 절감으로 생략, 화면에서 계산)
                           "live_factors": ([float(dv["f_live"][s]) for s in lst]
                                            if any(dv["f_live"][s] != 1 for s in lst) else []),
                           "applied_hypothesis_ids": app if any(app) else None, "n_stores": int(len(u.members[a])),
                           "prediction_created_at": created, "replay_mode": mode})
    h = hashlib.sha1(json.dumps({"lists": lists, "focus": [x["region_id"] for x in c["focus_regions"][:10]]},
                                sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    pred = {"prediction_snapshot_id": sid, "replay_run_id": RUN_ID, "model_version": MODEL, "target_round": t,
            "available_data_through_round": avail, "replay_mode": mode, "prediction_created_at": created,
            "regions": c["focus_regions"] if mode == "live" else c["focus_regions"][:30],
            "focus_regions": c["focus_regions"][:10], "store_top": c["store_top"],
            "active_hypotheses": int((eng.disc_row < pr["ti"]).sum()),
            "live_hypotheses_applied": [eng.st.H[i]["hypothesis_id"] for i in np.where(pr["applied_live"])[0]],
            "explore_hypotheses_fired": int(pr["applied_explore"].sum()), "snapshot_hash": h,
            "data_provenance": {"replay_mode": mode, "data_cutoff_round": avail,
                                "computed_after_draw": mode == "sequential_replay",
                                "sources": ["lottery_stores", "winning_history", "lotto_winning_numbers", "research_prize_stats"],
                                "store_universe": "현재 판매점 목록 기준 (개업·폐업일 미확보)",
                                "hypotheses_discovered_through_round": avail}}
    return pred, agent_rows, lists, h


def evaluate(u, eng, pr, lists_override=None):
    """실제 결과(t)로 지방장·중앙 평가. lists_override: 동결 저장본 목록 {agent: [codes]}"""
    dv, ti = pr["dv"], pr["ti"]
    Et, Ft = u.E[ti], u.F[ti]
    A = len(u.agent_ids)
    p_model = np.clip(dv["s_live"], 1e-7, 1 - 1e-7)
    p_base = np.clip(dv["mreg"], 1e-7, 1 - 1e-7)
    y = Et.astype(float)
    llm = -(y * np.log(p_model) + (1 - y) * np.log(1 - p_model))
    llb = -(y * np.log(p_base) + (1 - y) * np.log(1 - p_base))
    ag = np.where(u.st_agent >= 0, u.st_agent, A)
    ll_model = np.bincount(ag, llm, minlength=A + 1)[:A]
    ll_base = np.bincount(ag, llb, minlength=A + 1)[:A]
    ev = np.bincount(ag, Et, minlength=A + 1)[:A]
    fv = np.bincount(ag, Ft, minlength=A + 1)[:A]
    per = {}
    for a, agid in enumerate(u.agent_ids):
        n_st = len(u.members[a])
        if lists_override is not None and agid in lists_override:
            live = [u.cidx[c] for c in lists_override[agid] if c in u.cidx]
        else:
            live = [int(s) for s in dv["live"][a]]
        hist = [int(s) for s in dv["hist"][a]]
        expl = [int(s) for s in dv["expl"][a]]
        k = min(K_DELIVER, n_st)
        per[agid] = {"hits_any": int(Et[live].sum()) if live else 0, "hits_first": int(Ft[live].sum()) if live else 0,
                     "by_rank": [int(Et[s]) for s in live] + [0] * (K_DELIVER - len(live)),
                     "history_hits": int(Et[hist].sum()) if hist else 0, "explore_hits": int(Et[expl].sum()) if expl else 0,
                     "region_events": int(ev[a]), "region_first": int(fv[a]),
                     "expected_uniform": float(k / max(n_st, 1) * ev[a]),
                     "expected_model": float(dv["s_live"][live].sum()) if live else 0.0,
                     "ll_model": float(ll_model[a]), "ll_base": float(ll_base[a]), "n_stores": int(n_st),
                     "evaluated_stored_snapshot": lists_override is not None}
    rf = u.RF[ti].astype(float)

    def ll(p):
        return float(-np.mean(rf * np.log(p) + (1 - rf) * np.log(1 - p)))
    focus = np.argsort(-dv["p_model"], kind="stable")[:W.CENTRAL_REGIONS]
    focus0 = np.argsort(-dv["p_m0"], kind="stable")[:W.CENTRAL_REGIONS]
    if lists_override is not None:
        cand = np.array([u.cidx[c] for v in lists_override.values() for c in v if c in u.cidx], int)
        cstore = cand[np.argsort(-dv["s_live"][cand], kind="stable")][:W.CENTRAL_STORES]
    else:
        cstore = dv["cstore"]
    cm = {"logloss_model": ll(dv["p_model"]), "logloss_m0": ll(dv["p_m0"]), "logloss_m1": ll(dv["p_m1"]),
          "focus_hits": int(rf[focus].sum()), "focus_hits_m0": int(rf[focus0].sum()),
          "focus_expected": float(dv["p_model"][focus].sum()), "regions_with_first": int(rf.sum()),
          "store_hits_any": int(Et[cstore].sum()), "store_hits_first": int(Ft[cstore].sum()),
          "store_hits_history": int(Et[dv["hstore"]].sum()),
          "store_expected_uniform": float(W.CENTRAL_STORES / u.S * Et.sum()), "events": int(Et.sum())}
    return per, cm, focus


def agent_perf(u, eng, tr):
    """지방장 누적 성과 (최근 10·30·50·100회, 표본 경고, 가설·공유)"""
    A = len(u.agent_ids)
    keys = ("hits_any", "hits_first", "history_hits", "explore_hits", "expected_uniform", "expected_model",
            "ll_model", "ll_base", "region_events")
    hs = eng.st.H
    hyp_by_agent = defaultdict(Counter)
    shared_out = Counter()
    shared_in = defaultdict(list)
    for h in hs:
        i = h["idx"]
        hyp_by_agent[h["agent_id"]][STATUS[eng.status[i]]] += 1
        if h.get("shared_to_count"):
            shared_out[h["agent_id"]] += h["shared_to_count"]
        if h.get("shared_from"):
            shared_in[h["agent_id"]].append((STATUS[eng.status[i]], float(eng.test_ratio[i])))
    out = {}
    for a, ag in enumerate(u.agent_ids):
        rows = [r["agents"].get(ag) for r in tr.rounds if r["agents"].get(ag) is not None]

        def topk(rs):
            out_ = {}
            for kk in (1, 3, 5):
                hits = sum(sum(r["by_rank"][:kk]) for r in rs)
                exp_ = sum(min(kk, r["n_stores"]) / max(r["n_stores"], 1) * r["region_events"] for r in rs)
                out_[str(kk)] = {"hits": int(hits), "expected_uniform": round(exp_, 3),
                                 "lift": (hits / exp_) if exp_ > 0 else None}
            return out_

        def agg(rs):
            s = {k: float(sum(r[k] for r in rs)) for k in keys}
            return {"rounds": len(rs), "hits_any": int(s["hits_any"]), "expected_uniform": round(s["expected_uniform"], 3),
                    "history_hits": int(s["history_hits"]), "top": topk(rs),
                    "ll_skill": (1 - s["ll_model"] / s["ll_base"]) if s["ll_base"] > 0 else None}
        tot = {k: float(sum(r[k] for r in rows)) for k in keys}
        sh = shared_in.get(ag, [])
        hc = hyp_by_agent.get(ag, Counter())
        out[ag] = {"rounds": len(rows), "delivered": int(sum(min(K_DELIVER, r["n_stores"]) for r in rows)),
                   "hits_any": int(tot["hits_any"]), "hits_first": int(tot["hits_first"]),
                   "history_hits": int(tot["history_hits"]), "explore_hits": int(tot["explore_hits"]),
                   "expected_uniform": round(tot["expected_uniform"], 3), "expected_model": round(tot["expected_model"], 3),
                   "lift_vs_uniform": (tot["hits_any"] / tot["expected_uniform"]) if tot["expected_uniform"] > 0 else None,
                   "hits_vs_model": (tot["hits_any"] / tot["expected_model"]) if tot["expected_model"] > 0 else None,
                   "ll_skill": (1 - tot["ll_model"] / tot["ll_base"]) if tot["ll_base"] > 0 else None,
                   "recent": {str(n): agg(rows[-n:]) for n in (10, 30, 50, 100)},
                   "top": topk(rows),
                   "contribution": {"verified_hypotheses_hits": int(tot["hits_any"] - tot["history_hits"]),
                                    "unverified_signals_hits": int(tot["explore_hits"] - tot["history_hits"]),
                                    "note": "실전 목록 = 이력 기준 + 검증 통과 가설 보정, 탐색 목록 = 미검증 신호까지 보정"},
                   "baselines": {"random_in_region": "expected_uniform", "store_count": "지역 내 판매점 수 비례 = 무작위와 동일",
                                 "sales_volume": "데이터 미확보 (판매점별 판매량 없음)",
                                 "history_only": "history_hits (최근 가중 당첨 빈도만)"},
                   "hypotheses": {"found": int(sum(hc.values())), **{s: int(hc.get(s, 0)) for s in STATUS}},
                   "shared_out": int(shared_out.get(ag, 0)),
                   "shared_in": {"count": len(sh), "by_status": dict(Counter(x[0] for x in sh)),
                                 "mean_ratio": float(np.mean([x[1] for x in sh])) if sh else None},
                   "data_quality": {"region_events": int(tot["region_events"]), "stores": int(len(u.members[a])),
                                    "sample_flag": "표본 부족" if tot["region_events"] < 30 else None}}
    return out


def hyp_example(u, eng, i, **extra):
    d = summarize_h(u, eng, eng.st.H[i])
    d.update(extra)
    return d


def pre_briefing(u, eng, pr, pred, new_by_kind, mode):
    st = Counter(STATUS[s] for s in eng.status[eng.disc_row < pr["ti"]])
    live_ids = np.where(pr["applied_live"])[0]
    lines = [f"{pred['target_round']}회 예측: {pred['available_data_through_round']}회까지의 실제 결과만 사용"
             f"{'' if mode == 'live' else ' (추첨 이후 사후 재현)'}.",
             f"중앙 엔진 주목 지역: " + ", ".join(x["region_id"] for x in pred["focus_regions"][:5]) + ".",
             f"이 시점 가설 {sum(st.values())}건 중 검증 통과 {st.get('passed', 0) + st.get('combined', 0)}건, "
             f"실전 반영 {len(live_ids)}건 · 탐색 반영 {pred['explore_hypotheses_fired']}건."]
    return {"target_round": pred["target_round"], "available_data_through_round": pred["available_data_through_round"],
            "replay_mode": mode, "focus_regions": pred["focus_regions"][:5],
            "top_stores": [{k: s.get(k) for k in ("store_code", "agent_id", "name", "score", "agent_rank", "verification")}
                           for s in pred["store_top"][:10]],
            "active_hypotheses": pred["active_hypotheses"],
            "live_applied": [hyp_example(u, eng, i) for i in live_ids[:5]], "explore_fired": pred["explore_hypotheses_fired"],
            "new_hypotheses": {"count": int(sum(new_by_kind.values())), "by_kind": dict(new_by_kind)},
            "status_counts": {s: int(st.get(s, 0)) for s in STATUS}, "lines": lines}


def post_briefing(u, eng, pr, per, cm, focus, changes, tr, lists):
    t, ti = pr["target"], pr["ti"]
    first_idx = np.where(u.F[ti] == 1)[0]
    first_regions = sorted({u.agent_ids[u.st_agent[s]] for s in first_idx if u.st_agent[s] >= 0})
    focus_ids = {u.reg_ids[j] for j in focus}
    rank1 = []
    for ag, lst in lists.items():
        if lst and lst[0] in u.cidx and u.E[ti, u.cidx[lst[0]]]:
            rank1.append({"agent_id": ag, "store_code": lst[0], "name": u.name[u.cidx[lst[0]]]})
    tot = Counter()
    for m in per.values():
        for k in ("hits_any", "hits_first", "history_hits", "explore_hits", "expected_uniform", "ll_model", "ll_base"):
            tot[k] += m[k]
    skill = 1 - tot["ll_model"] / tot["ll_base"] if tot["ll_base"] > 0 else None
    prev = [r["skill"] for r in tr.rounds[-31:-1] if r.get("skill") is not None]
    trail = float(np.mean(prev)) if prev else None
    in_top = sum(1 for s in np.where(u.E[ti] == 1)[0] if any(u.codes[s] in v for v in lists.values()))
    if skill is None or trail is None:
        reason = "비교할 이전 회차 부족"
    elif skill >= trail:
        reason = f"당첨 판매점 {int(u.E[ti].sum())}곳 중 {in_top}곳이 지방장 상위 5 안 — 최근 30회 평균보다 확률 점수 개선"
    else:
        reason = f"당첨 판매점 {int(u.E[ti].sum())}곳 중 {in_top}곳만 지방장 상위 5 안 — 이력 하위 판매점 당첨 비중이 커 확률 점수 악화"
    ch = Counter(f"{c['status_from']}→{c['status_to']}" for c in changes)
    ex = [hyp_example(u, eng, eng.st.H_index[c["hypothesis_id"]], **{"from": c["status_from"], "to": c["status_to"]})
          for c in sorted(changes, key=lambda c: (c["status_to"] not in ("passed", "combined"), c["test_p"]))[:5]]
    lines = [f"{t}회 결과: 1등 지역 {len(first_regions)}곳 중 주목 지역 적중 {len(focus_ids & set(first_regions))}곳 "
             f"(판매점 수 기준 상위 10은 {cm['focus_hits_m0']}곳).",
             f"지방장 상위 5 납품 1·2등 적중 {tot['hits_any']}건 (이력만 {tot['history_hits']} · 무작위 기대 {tot['expected_uniform']:.1f}).",
             f"가설 상태 변화 {len(changes)}건" + (": " + ", ".join(f"{k} {v}" for k, v in ch.most_common(3)) if ch else "") + ".",
             reason + "."]
    return {"target_round": t,
            "actual": {"first_regions": first_regions,
                       "first_stores": [{"store_code": u.codes[s], "name": u.name[s],
                                         "agent_id": u.agent_ids[u.st_agent[s]] if u.st_agent[s] >= 0 else None} for s in first_idx],
                       "focus_hit_regions": sorted(focus_ids & set(first_regions))},
            "agents": {"hits_any": int(tot["hits_any"]), "hits_first": int(tot["hits_first"]), "history_hits": int(tot["history_hits"]),
                       "explore_hits": int(tot["explore_hits"]), "expected_uniform": round(tot["expected_uniform"], 2),
                       "rank1_hits": rank1[:10]},
            "central": {k: cm[k] for k in ("logloss_model", "logloss_m0", "focus_hits", "focus_hits_m0")},
            "hypothesis_changes": {"counts": dict(ch), "examples": ex},
            "trend": {"skill_round": skill, "skill_trailing30": trail, "reason": reason}, "lines": lines}, skill


def _verdict_evidence(eng, h, latest):
    v, detail = verdict_of(eng, h, latest)
    e = float(eng.e[h["idx"]])
    kmin = poisson_min_k(e)
    return {"verdict": v, "verdict_detail": detail,
            "power": {"expected": round(e, 4), "min_k_p05": kmin,
                      "min_detectable_ratio": round(kmin / e, 2) if kmin and e > 0 else None}}


def poisson_min_k(e, alpha=0.05):
    """기대 e 에서 단측 p<alpha 가 되는 최소 관측 수"""
    from scipy.stats import poisson
    if e <= 0:
        return None
    k = int(math.ceil(e))
    while poisson.sf(k - 1, e) >= alpha and k < 10000:
        k += 1
    return k


def verdict_of(eng, h, latest):
    """'연구 중'을 세분화: 검증 통과 / 검증 실패 / 검증 중(관측 누적·표본 부족·발화 대기)"""
    i = h["idx"]
    st = eng.status[i]
    n, e, k = float(eng.n[i]), float(eng.e[i]), float(eng.k[i])
    eoff = float(eng.eoff[i])
    active_rounds = max(1, latest - h["discovered_round"])
    if st in (S_PASS, S_COMB):
        return "검증 통과", f"순방향 {int(n)}회 발화 · 관측 {int(k)}건 / 기대 {e:.1f}건 · BH q<0.05"
    if st == S_REJ:
        return "검증 실패", f"반대 방향 (관측 {int(k)} / 기대 {e:.1f}, 대조군 대비 ×{eng.test_ratio[i]:.2f})"
    if st == S_WEAK:
        return "검증 실패", f"판정 가능 표본에서 우위 미확인 (×{eng.test_ratio[i]:.2f}, p={eng.test_p[i]:.3f})"
    if n == 0:
        if active_rounds < 50:
            return "검증 중: 미래 관측 누적 중", f"발견({h['discovered_round']}회) 후 {active_rounds}회 — 아직 발화 없음"
        return "검증 중: 표본 부족", f"발견({h['discovered_round']}회) 후 {active_rounds}회 동안 발화 0회 (조건이 드묾)"
    rate = e / active_rounds
    need = max(W.MIN_EXPECTED - e, 0) / rate if rate > 0 else float("inf")
    if eoff and eoff < W.MIN_EXPECTED:
        need = max(need, (W.MIN_EXPECTED - eoff) / max(eoff / active_rounds, 1e-12))
    if n < W.MIN_TRIALS:
        need = max(need, (W.MIN_TRIALS - n) / max(n / active_rounds, 1e-12))
    if need <= 100:
        return "검증 중: 미래 관측 누적 중", f"판정까지 약 {need:.0f}회 더 필요 (기대 {e:.2f}건 / 필요 {W.MIN_EXPECTED:.0f}건)"
    return "검증 중: 표본 부족", (f"기대 {e:.2f}건 — 판정에 {W.MIN_EXPECTED:.0f}건 필요, 현 속도로 약 "
                                 + (f"{need:.0f}회" if math.isfinite(need) else "무한") + " 필요")


def hypothesis_rows(u, eng, tr, latest):
    rows = []
    for h in eng.st.H:
        i = h["idx"]
        rows.append({"replay_run_id": RUN_ID, "hypothesis_id": h["hypothesis_id"], "model_version": MODEL,
                     "agent_id": h["agent_id"], "kind": h["kind"], "scope": h["scope"], "canonical_key": h["canonical_key"],
                     "direction": h["direction"], "predictive": h["predictive"], "source_region": h["source_region"],
                     "target_region": h["target_region"], "source_store": h["source_store"], "target_store": h["target_store"],
                     "related_regions": h["related_regions"], "related_stores": h["related_stores"], "lag": h["lag"],
                     "params": h["params"], "shared_from": h["shared_from"], "shared_by_agent": h["shared_by_agent"],
                     "shared_to_count": h["shared_to_count"], "first_discovered_round": h["discovered_round"],
                     "discovery_significant": h["discovery_significant"],
                     "first_applied_live_round": int(tr.first_live[i]) if tr.first_live[i] >= 0 else None,
                     "first_applied_explore_round": int(tr.first_explore[i]) if tr.first_explore[i] >= 0 else None,
                     "applied_live_count": int(tr.cnt_live[i]), "applied_explore_count": int(tr.cnt_explore[i]),
                     "train_n": h["train_n"], "train_k": h["train_k"], "train_expected": h["train_expected"],
                     "train_p": h["train_p"], "train_q": h["train_q"], "test_n": int(eng.n[i]), "test_k": int(eng.k[i]),
                     "test_expected": float(eng.e[i]), "k_off": int(eng.koff[i]), "e_off": float(eng.eoff[i]),
                     "relative_ratio": float(eng.test_ratio[i]), "test_p": float(eng.test_p[i]), "test_q": float(eng.test_q[i]),
                     "status": STATUS[eng.status[i]], "evaluated_round": latest, "summary": h_summary(u, h),
                     "evidence": dict(h["evidence"], **_verdict_evidence(eng, h, latest)), "updated_at": now()})
    return rows


# ── 실행 ──────────────────────────────────────────────────────────
class Writer:
    def __init__(self, db, dry):
        self.db, self.dry = db, dry
        self.buf = defaultdict(list)
        self.bytes = Counter()

    def add(self, table, rows):
        self.buf[table].extend(rows if isinstance(rows, list) else [rows])

    def flush(self):
        spec = {"research_replay_predictions": "prediction_snapshot_id",
                "research_replay_agent_predictions": "prediction_snapshot_id,agent_id",
                "research_replay_results": "prediction_snapshot_id",
                "research_replay_agent_evals": "prediction_snapshot_id,agent_id",
                "research_replay_central_evals": "prediction_snapshot_id",
                "research_replay_briefings": "prediction_snapshot_id,kind",
                "research_replay_hypothesis_events": "replay_run_id,hypothesis_id,round",
                "research_replay_checkpoints": "replay_run_id,target_round,stage"}
        for table in list(spec):          # 순서: 예측 → 결과 → 검증 → 브리핑 → 이벤트 → 원장
            rows = self.buf.pop(table, [])
            if not rows:
                continue
            rows = rnd(clean(rows))
            self.bytes[table] += len(json.dumps(rows, ensure_ascii=False, default=_json_default).encode("utf-8"))
            if not self.dry:
                self.db.upsert(table, rows, spec[table], ignore_duplicates=(table != "research_replay_checkpoints"))

    def put(self, table, rows, on, ignore=False):
        rows = rnd(clean(rows))
        self.bytes[table] += len(json.dumps(rows, ensure_ascii=False, default=_json_default).encode("utf-8"))
        if not self.dry and rows:
            self.db.upsert(table, rows, on, ignore_duplicates=ignore)


def run(db, key, a, raw=None, ready=None):
    t_start = time.time()
    raw = raw or load(db)
    if ready is None:
        ready, _ = W.ready_latest(raw)
    latest = min(ready, a.until) if a.until else ready
    stst = StateStore(db, key, a.state_dir)
    stst.ensure_bucket()
    state = None if a.fresh else stst.load("state.pkl.gz")
    if state and (state.get("version") != STATE_VERSION or state.get("run_id") != RUN_ID):
        log("[state] 버전 불일치 → 처음부터 재현"); state = None
    if state and state["last_completed_round"] > latest:
        log("[state] 상태가 대상 회차보다 앞섬 → 처음부터 재현"); state = None
    provenance = {"state_restored": bool(state)}
    if state:
        u = Universe(raw, latest, base=state["universe_base"])
        TUNED.update(state["tuned"])
        eng, tr = state["engine"], state["track"]
        last = state["last_completed_round"]
        fp = fingerprint(u, u.row(last), state["universe_base_ncodes"])
        provenance["past_data_unchanged"] = fp == state["fingerprint"]
        if not provenance["past_data_unchanged"]:
            log("[state] 경고: 저장 이후 과거 회차 데이터가 바뀜 (동결 기록은 유지, 이후 계산은 새 데이터 사용)")
        attach(eng, u)
        tuned = state["tuned"]
        log(f"[state] {last}회까지 복원 (가설 {eng.H})")
    else:
        u = Universe(raw, latest)
        tuned = tune(u)
        TUNED.update({k: tuned[k] for k in ("store_half_life", "central_half_life", "central_beta")})
        eng = Engine(u)
        tr = Track()
        start_ti = u.row(LEARN_START)
        for ti in range(0, start_ti):
            eng.advance(ti)
        ci = start_ti - 1
        ps, pcnt = store_rates(u, ci)
        eng.relations_by_cp = {}
        discover(u, eng.st, ci, ps, pcnt, region_rates(u, ci), eng.stats, full=True)
        eng.rebuild()
        eng.update_status(ci)
        last = LEARN_START - 1
        log(f"[baseline] 999회 기준선, 가설 {eng.H} (tune {tuned['store_half_life']:g}/{tuned['central_half_life']:g}/{tuned['central_beta']:g})")
    eng.st.H_index = {h["hypothesis_id"]: h["idx"] for h in eng.st.H}
    tr.grow(eng.H)

    # 원장: 이미 동결/검증된 회차
    done = defaultdict(set)
    if not a.dry_run or a.read_stored:
        for r in db.select_all("research_replay_checkpoints", {"select": "target_round,stage,status", "order": "target_round,stage", "replay_run_id": f"eq.{RUN_ID}",
                                                               "status": "eq.done"}):
            done[r["stage"]].add(r["target_round"])
    wr = Writer(db, a.dry_run)
    unmatched = Counter((h["round"], h["prize_tier"]) for h in raw["hist"] if h["dhlottery_code"] not in u.cidx)
    events_cursor = len(eng.events)
    summary_rounds = []
    replayed = 0
    last_eval = None

    def save_state(last_round):
        eng.u = None
        blob_state = {"version": STATE_VERSION, "run_id": RUN_ID, "last_completed_round": last_round,
                      "universe_base": {"codes": u.codes, "agent_ids": u.agent_ids, "stores": u.store_snapshot},
                      "universe_base_ncodes": len(u.codes), "fingerprint": fingerprint(u, u.row(last_round), len(u.codes)),
                      "tuned": tuned, "engine": eng, "track": tr, "saved_at": now()}
        size = stst.save("state.pkl.gz", blob_state)
        log(f"  [state] {last_round}회 지문 {blob_state['fingerprint'][:12]} (판매점 {len(u.codes)} · 행 {u.row(last_round) + 1})")
        eng.u = u
        return size

    def flush_research(last_round, write_hyp=False):
        wr.flush()
        if not a.dry_run and write_hyp:
            wr.put("research_replay_hypotheses", hypothesis_rows(u, eng, tr, last_round), "replay_run_id,hypothesis_id")
        size = save_state(last_round)
        if not a.dry_run:
            wr.put("research_replay_runs", [{"replay_run_id": RUN_ID, "model_version": MODEL, "replay_mode": REPLAY_MODE,
                                             "status": "running", "start_round": LEARN_START, "last_completed_round": last_round,
                                             "config": {"tuned": tuned, "k_deliver": K_DELIVER, "light_discovery": "every round",
                                                        "full_discovery": f"every {CP_STEP} rounds from {CP_FIRST}"},
                                             "data_provenance": provenance, "updated_at": now()}], "replay_run_id")
        log(f"  [checkpoint] {last_round}회 상태 저장 {size / 1e6:.1f}MB · 가설 {eng.H} ({time.time() - t_start:.0f}s)")

    stored_cache = {}

    def stored_lists(t):
        if (a.dry_run and not a.read_stored) or t not in done["predicted"]:
            return None
        rows = db.select_all("research_replay_agent_predictions", {"select": "agent_id,store_ids", "order": "agent_id",
                                                                    "prediction_snapshot_id": f"eq.{snap_id(t)}"})
        return {r["agent_id"]: r["store_ids"] for r in rows} if rows else None

    for t in range(last + 1, latest + 1):
        ti = u.row(t)
        created = now()
        n_before = eng.H
        # A~D 예측 동결
        pr = predict(u, eng, ti, t)
        pred, agent_rows, lists, hsh = prediction_rows(u, eng, pr, t - 1, "sequential_replay", created)
        new_by_kind = Counter(h["kind"] for h in eng.st.H if h["discovered_round"] == t - 1)
        stored = stored_lists(t)
        if stored is None:
            wr.add("research_replay_predictions", pred)
            wr.add("research_replay_agent_predictions", agent_rows)
            wr.add("research_replay_briefings", {"prediction_snapshot_id": snap_id(t), "kind": "pre", "replay_run_id": RUN_ID,
                                                 "target_round": t, "payload": pre_briefing(u, eng, pr, pred, new_by_kind,
                                                                                            "sequential_replay")})
            wr.add("research_replay_checkpoints", {"replay_run_id": RUN_ID, "target_round": t, "stage": "predicted", "status": "done"})
        else:
            if stored != lists:
                provenance.setdefault("stored_snapshot_mismatch", []).append(t)
            lists = stored
        # E 결과 공개 · F 검증
        verified_at = now()
        per, cm, focus = evaluate(u, eng, pr, lists_override=stored)
        unk1, unk2 = unmatched.get((t, "first"), 0), unmatched.get((t, "second"), 0)
        first_idx = np.where(u.F[ti] == 1)[0]
        if t not in done["verified"]:
            wr.add("research_replay_results", {"prediction_snapshot_id": snap_id(t), "replay_run_id": RUN_ID, "target_round": t,
                                               "result_verified_at": verified_at,
                                               "first_store_ids": [u.codes[s] for s in first_idx],
                                               "first_regions": sorted({u.agent_ids[u.st_agent[s]] for s in first_idx if u.st_agent[s] >= 0}),
                                               "event_store_count": int(u.E[ti].sum()), "unmatched_first": unk1, "unmatched_second": unk2,
                                               "data_provenance": {"source": "winning_history (lotto first/second)",
                                                                   "store_id_match": "dhlottery_code ↔ lottery_stores",
                                                                   "round_valid": bool(u.valid[ti])}})
            wr.add("research_replay_agent_evals", [{"prediction_snapshot_id": snap_id(t), "agent_id": ag, "replay_run_id": RUN_ID,
                                                    "target_round": t, "result_verified_at": verified_at, "hits_any": m["hits_any"],
                                                    "hits_first": m["hits_first"], "expected_uniform": m["expected_uniform"],
                                                    "evaluation_metrics": {k: v for k, v in m.items()
                                                                           if k not in ("hits_any", "hits_first", "expected_uniform")}}
                                                   for ag, m in per.items()])
            wr.add("research_replay_central_evals", {"prediction_snapshot_id": snap_id(t), "replay_run_id": RUN_ID, "target_round": t,
                                                     "result_verified_at": verified_at, "evaluation_metrics": cm})
            wr.add("research_replay_checkpoints", {"replay_run_id": RUN_ID, "target_round": t, "stage": "verified", "status": "done"})
        # G 연구 갱신
        if u.valid[ti]:
            fire2, trials2, expv2, _, _ = eng.fire(ti, with_cowin=True)
            k, koff, eoff = eng.outcomes(ti, fire2)
            eng.n += trials2
            eng.k += k
            eng.e += expv2
            eng.koff += koff
            eng.eoff += eoff
        for arr_first, arr_cnt, mask in ((tr.first_live, tr.cnt_live, pr["applied_live"]),
                                         (tr.first_explore, tr.cnt_explore, pr["applied_explore"])):
            idx = np.where(mask)[0]
            arr_cnt[idx] += 1
            fresh = idx[arr_first[idx] < 0]
            arr_first[fresh] = t
        eng.advance(ti)
        eng.update_status(ti)
        changes = eng.events[events_cursor:]
        events_cursor = len(eng.events)
        full = (t - CP_FIRST) % CP_STEP == 0
        ps, pcnt = store_rates(u, ti)
        discover(u, eng.st, ti, ps, pcnt, region_rates(u, ti), eng.stats, full=full)
        eng.rebuild()
        eng.update_status(ti)
        events_cursor = len(eng.events)
        tr.grow(eng.H)
        eng.st.H_index = {h["hypothesis_id"]: h["idx"] for h in eng.st.H}
        # H 사후 브리핑
        post, skill = post_briefing(u, eng, pr, per, cm, focus, changes, tr, lists)
        tr.rounds.append({"t": t, "agents": per, "skill": skill, "hash": hsh})
        last_eval = {"t": t, "per": {ag: (m["hits_any"], m["hits_first"]) for ag, m in per.items()}, "central": cm,
                     "stored": stored is not None}
        tr.central.append({"t": t, **cm})
        if t not in done["verified"]:
            wr.add("research_replay_briefings", {"prediction_snapshot_id": snap_id(t), "kind": "post", "replay_run_id": RUN_ID,
                                                 "target_round": t, "payload": post})
        wr.add("research_replay_hypothesis_events", [{"replay_run_id": RUN_ID, "hypothesis_id": c["hypothesis_id"], "round": c["round"],
                                                     "status_from": c["status_from"], "status_to": c["status_to"],
                                                     "test_n": c["test_n"], "test_k": c["test_k"], "test_expected": c["test_expected"],
                                                     "test_p": c["test_p"],
                                                     "relative_ratio": float(eng.test_ratio[eng.st.H_index[c["hypothesis_id"]]])}
                                                    for c in changes])
        wr.add("research_replay_checkpoints", {"replay_run_id": RUN_ID, "target_round": t, "stage": "updated", "status": "done"})
        summary_rounds.append(t)
        replayed += 1
        if replayed % 25 == 0 or t == latest:
            log(f"  [round {t}] H={eng.H} (+{eng.H - n_before}) passed={(np.isin(eng.status, (S_PASS, S_COMB))).sum()} "
                f"hits={sum(m['hits_any'] for m in per.values())} ({time.time() - t_start:.0f}s)")
        if t % WRITE_EVERY == 0:
            wr.flush()
        if t % STATE_EVERY == 0 and t != latest:
            flush_research(t)
        last = t

    # 마지막 실제 회차 이후 → 다음 미추첨 회차 실전 동결
    target = latest + 1
    ti = u.R
    pr = predict(u, eng, ti, target)
    created = now()
    pred, agent_rows, lists, hsh = prediction_rows(u, eng, pr, latest, "live", created)
    live_new = target not in done["predicted"]
    if not live_new:
        st_live = stored_lists(target)
        provenance["live_snapshot_matches_recompute"] = (st_live == lists) if st_live is not None else None
    if live_new:
        new_by_kind = Counter(h["kind"] for h in eng.st.H if h["discovered_round"] == latest)
        wr.add("research_replay_predictions", pred)
        wr.add("research_replay_agent_predictions", agent_rows)
        wr.add("research_replay_briefings", {"prediction_snapshot_id": snap_id(target), "kind": "pre", "replay_run_id": RUN_ID,
                                             "target_round": target, "payload": pre_briefing(u, eng, pr, pred, new_by_kind, "live")})
        wr.add("research_replay_checkpoints", {"replay_run_id": RUN_ID, "target_round": target, "stage": "predicted", "status": "done"})
    perf = agent_perf(u, eng, tr)
    compat = compat_live(u, eng, pr, perf, tr, latest, live_new)
    compat["live_hash"] = hsh
    if a.dry_run:
        compat["hyp_sample"] = hypothesis_rows(u, eng, tr, latest)[:30]
    compat["last_eval"] = last_eval if replayed else None
    if not a.dry_run:
        write_compat(wr, compat, immutable=live_new)   # 동결 행은 처음 한 번만, 지방장 성과·브리핑은 매번 갱신
    flush_research(latest, write_hyp=True)
    totals = summarize(u, eng, tr, perf, latest, replayed, provenance)
    totals["write_bytes"] = dict(wr.bytes)
    totals["elapsed_sec"] = round(time.time() - t_start, 1)
    if not a.dry_run:
        totals["db_usage"] = db_usage(db)
        wr.put("research_replay_runs", [{"replay_run_id": RUN_ID, "model_version": MODEL, "replay_mode": REPLAY_MODE,
                                         "status": "completed", "start_round": LEARN_START, "last_completed_round": latest,
                                         "last_prediction_round": target, "config": {"tuned": tuned, "k_deliver": K_DELIVER},
                                         "data_provenance": provenance, "stats": clean(totals), "error": None,
                                         "updated_at": now()}], "replay_run_id")
    return totals, compat


def compat_live(u, eng, pr, perf, tr, latest, live_new):
    """실전 회차를 기존 화면(지역·내 주변·경로·연구소) 테이블 형식으로 (model_version='ag-1.1')"""
    dv, target = pr["dv"], pr["target"]
    related = defaultdict(list)
    for h in eng.st.H:
        for cd in h["related_stores"]:
            related[cd].append(h["idx"])
    scores, deliveries = [], []
    live_ratio, explore_ratio = eng.ratios()
    for a, ag in enumerate(u.agent_ids):
        order = dv["order"][dv["starts"][a]:dv["ends"][a]]
        for r, s in enumerate(order):
            s = int(s)
            scores.append({"model_version": MODEL, "target_round": target, "store_code": u.codes[s], "agent_id": ag,
                           "agent_rank": r + 1, "agent_size": len(order), "score": float(dv["s_live"][s]),
                           "p_first": float(dv["s_live"][s] * dv["phi"]), "live_factor": float(dv["f_live"][s]),
                           "explore_factor": float(dv["f_exp"][s]), "hyp_count": len(related.get(u.codes[s], [])),
                           "training_end_round": latest})
        for r, s in enumerate(dv["live"][a]):
            s = int(s)
            cd = u.codes[s]
            ev = np.where(u.E[:, s] == 1)[0]
            fr = np.where(u.F[:, s] == 1)[0]
            gaps = np.diff(ev)
            hy = []
            app = set(pr["per_store_live"].get(s, []))
            for i in related.get(cd, [])[:4]:
                h = eng.st.H[i]
                hy.append({"id": h["hypothesis_id"], "kind": h["kind"], "status": STATUS[eng.status[i]], "summary": h_summary(u, h),
                           "firing": bool(pr["fire"][i]), "applied_live": h["hypothesis_id"] in app,
                           "factor_live": float(min(max(live_ratio[i], 1 / FACTOR_CAP), FACTOR_CAP)) if h["hypothesis_id"] in app else 1.0,
                           "shared_from": h.get("shared_from")})
            deliveries.append({"model_version": MODEL, "target_round": target, "agent_id": ag, "store_code": cd, "mode": "live",
                               "rank": r + 1, "score": float(dv["s_live"][s]), "p_first": float(dv["s_live"][s] * dv["phi"]),
                               "store_name": u.name[s], "address": u.addr[s],
                               "lat": None if np.isnan(u.lat[s]) else float(u.lat[s]),
                               "lng": None if np.isnan(u.lng[s]) else float(u.lng[s]),
                               "history": {"first": int(len(fr)), "second": int(len(ev) - len(fr)),
                                           "first_rounds": [int(u.rounds[x]) for x in fr[::-1][:10]],
                                           "last_event_round": int(u.rounds[ev[-1]]) if len(ev) else None,
                                           "gap_mean": float(gaps.mean()) if len(gaps) else None,
                                           "gap_median": float(np.median(gaps)) if len(gaps) else None,
                                           "rounds_since_last": int(u.R - 1 - ev[-1]) if len(ev) else None},
                               "components": {"base": float(dv["lam"][s]), "region_prior": float(dv["mreg"][s]),
                                              "live_factor": float(dv["f_live"][s]), "explore_factor": float(dv["f_exp"][s]),
                                              "first_share": float(dv["phi"])},
                               "hypotheses": hy,
                               "verification": "검증 가설 반영" if dv["f_live"][s] != 1 else "이력 기반(검증 가설 없음)",
                               "data_quality": {"events": int(len(ev)), "has_geo": bool(u.geo[s]), "possible_duplicate": bool(u.dup[s]),
                                                "first_event_round": int(u.rounds[ev[0]]) if len(ev) else None},
                               "training_end_round": latest})
    central = {"model_version": MODEL, "target_round": target, "mode": "live", "training_end_round": latest,
               **dv_central(u, dv, all_regions=True)}
    hc = defaultdict(Counter)
    for h in eng.st.H:
        hc[h["agent_id"]][STATUS[eng.status[h["idx"]]]] += 1
    agents = []
    for a, ag in enumerate(u.agent_ids):
        mem = u.members[a]
        sido, unit = (ag.split("|") + [ag])[:2] if ag != "internet" else ("internet", "인터넷 판매")
        subs = defaultdict(lambda: [0, 0, 0])
        for s in mem:
            sb = u.sub[s] or "(미상)"
            subs[sb][0] += 1
            subs[sb][1] += int(u.E[:, s].sum())
            subs[sb][2] += int(u.F[:, s].sum())
        p = perf.get(ag, {})
        agents.append({"agent_id": ag, "model_version": MODEL, "level": "internet" if ag == "internet" else "sigungu",
                       "sido": sido, "unit_name": unit,
                       "sub_units": [{"name": k, "stores": v[0], "events": v[1], "first": v[2]}
                                     for k, v in sorted(subs.items(), key=lambda x: (-x[1][1], x[0]))],
                       "store_count": int(len(mem)), "active_store_count": int((u.E[max(u.R - 200, 0):, mem].sum(0) > 0).sum()),
                       "geo_store_count": int(u.geo[mem].sum()), "duplicate_groups": int(u.dup_groups_by_agent.get(a, 0)),
                       "status": "completed", "last_processed_round": latest, "last_target_round": target,
                       "hypothesis_counts": dict(hc[ag]), "delivery_count": int(p.get("delivered", 0) + min(K_DELIVER, len(mem))),
                       "performance": p, "error": None, "last_run_at": now(), "updated_at": now()})
    st = Counter(STATUS[s] for s in eng.status)
    tot = Counter()
    for r in tr.rounds:
        for m in r["agents"].values():
            for k in ("hits_any", "hits_first", "history_hits", "explore_hits", "expected_uniform"):
                tot[k] += m[k]
    cm = Counter()
    for c in tr.central:
        for k, v in c.items():
            if k != "t":
                cm[k] += v
    n = max(len(tr.central), 1)
    by_kind = defaultdict(list)
    for h in eng.st.H:
        by_kind[h["kind"]].append(h)

    def top(hs, k=3):
        hs = sorted(hs, key=lambda h: (eng.status[h["idx"]] not in (S_PASS, S_COMB), eng.test_p[h["idx"]], h["hypothesis_id"]))
        return [summarize_h(u, eng, h) for h in hs[:k]]
    shared = [h for h in eng.st.H if h.get("shared_from")]
    perf_all = {"rounds": [tr.rounds[0]["t"], tr.rounds[-1]["t"]] if tr.rounds else [], "n_rounds": len(tr.rounds),
                "agent_hits_live": int(tot["hits_any"]), "agent_hits_first": int(tot["hits_first"]),
                "agent_hits_history": int(tot["history_hits"]), "agent_hits_explore": int(tot["explore_hits"]),
                "expected_uniform": round(float(tot["expected_uniform"]), 2),
                "central_logloss": {"model": cm["logloss_model"] / n, "m0": cm["logloss_m0"] / n, "m1": cm["logloss_m1"] / n},
                "central_region_hits": int(cm["focus_hits"]), "central_region_hits_m0": int(cm["focus_hits_m0"]),
                "central_region_expected": round(float(cm["focus_expected"]), 2),
                "central_store_hits": int(cm["store_hits_any"]), "central_store_hits_history": int(cm["store_hits_history"]),
                "central_store_expected_uniform": round(float(cm["store_expected_uniform"]), 2),
                "live_rounds_evaluated": 0, "replay": True}
    briefing = {"target_round": target, "training_end_round": latest, "model_version": MODEL,
                "agents": {"total": len(u.agent_ids), "completed": len(u.agent_ids), "failed": 0, "stores": u.S},
                "focus_regions": central["focus_regions"][:5],
                "top_stores": [dict(s, reason=f"{s['agent_id']} 지방장 {s['agent_rank']}위 · 최근 가중 당첨 빈도 상위"
                                    + (f" · 검증 가설 보정 ×{s['live_factor']:.2f}" if s["live_factor"] != 1 else " · 검증 통과 가설 미적용"))
                               for s in central["store_top"][:10]],
                "famous_cycles": {"tested": len([h for h in by_kind["store_cycle"] if h["params"].get("famous")]),
                                  "by_status": dict(Counter(STATUS[eng.status[h["idx"]]] for h in by_kind["store_cycle"] if h["params"].get("famous"))),
                                  "examples": top([h for h in by_kind["store_cycle"] if h["params"].get("famous")])},
                "cowin": {"counts": {"store_pairs": len(by_kind["store_cowin"]), "region_pairs": len(by_kind["region_cowin"])},
                          "store_pairs": top(by_kind["store_cowin"]), "region_pairs": top(by_kind["region_cowin"])},
                "lead_lag": {"counts": {k: len(by_kind[k]) for k in ("store_lead", "region_store_lead", "region_lead", "self_repeat",
                                                                    "neighbor_spill", "store_spill")},
                             "examples": top(by_kind["store_lead"] + by_kind["region_store_lead"] + by_kind["region_lead"] + by_kind["neighbor_spill"], 4)},
                "shared": {"templates": len({h["shared_from"] for h in shared}), "instances": len(shared),
                           "new_this_checkpoint": len([h for h in shared if h["discovered_round"] == latest]),
                           "conflicts": int(eng.stats.get("template_conflicts", 0)), "examples": top(shared)},
                "status_counts": {s: int(st.get(s, 0)) for s in STATUS}, "performance": perf_all, "rank_changes": [],
                "agent_performance": agent_perf_summary(perf),
                "hypothesis_verdicts": verdict_summary(eng, latest),
                "data_limits": ["판매점별 판매량 자료 없음 → 점수는 회차당 1·2등 기대 빈도(판매량 미보정)이며 한 장당 당첨확률이 아님",
                                "1000~마지막 회차 기록은 당시 데이터만 사용해 추첨 이후 재현한 '사후 재현'이며, 'live' 회차만 추첨 전 동결",
                                "판매점 개업·폐업일 미확보 → 판매점 목록은 현재 기준"],
                "lines": [f"{target}회 대상: 지방장 {len(u.agent_ids)}명 실전 납품 (실전형 재현 계보 {RUN_ID}).",
                          f"가설 {eng.H}건 — 검증 통과 {st.get('passed', 0) + st.get('combined', 0)} · 연구 중 {st.get('researching', 0)} · "
                          f"약화 {st.get('weakened', 0)} · 기각 {st.get('rejected', 0)} · 발견 {st.get('discovered', 0)}.",
                          f"재현 {perf_all['rounds'][0] if perf_all['rounds'] else '-'}~{perf_all['rounds'][-1] if perf_all['rounds'] else '-'}회: "
                          f"지방장 상위 5 적중 {perf_all['agent_hits_live']}건 (이력만 {perf_all['agent_hits_history']} · 무작위 기대 {perf_all['expected_uniform']:.0f}).",
                          f"중앙 엔진 지역 log-loss {perf_all['central_logloss']['model']:.4f} (판매점 수 기준 {perf_all['central_logloss']['m0']:.4f})."]}
    return {"scores": scores, "deliveries": deliveries, "central": central, "agents": agents, "briefing": briefing,
            "first_share": float(dv["phi"]),
            "hashes": {r["t"]: r.get("hash") for r in tr.rounds}}


STORE_KINDS = ("store_cycle", "store_cowin", "store_lead", "region_store_lead", "store_spill", "composite",
               "cycle_pooled", "neighbor_spill")


def verdict_summary(eng, latest):
    """가설 판정 분포와 판매점 단위 검증 통과 0건 이유 (실제 수치)"""
    by_kind = defaultdict(Counter)
    exp_store = []
    ratios_decided = []
    for h in eng.st.H:
        v, _ = verdict_of(eng, h, latest)
        by_kind[h["kind"]][v] += 1
        if h["kind"] in STORE_KINDS:
            i = h["idx"]
            exp_store.append(float(eng.e[i]))
            if eng.status[i] in (S_WEAK, S_REJ, S_PASS, S_COMB):
                ratios_decided.append(float(eng.test_ratio[i]))
    tot = Counter()
    for k, c in by_kind.items():
        if k in STORE_KINDS:
            tot.update(c)
    e = np.array(exp_store) if exp_store else np.zeros(1)
    med = float(np.median(e))
    kmin = poisson_min_k(med) if med > 0 else None
    why = {"store_level_total": int(sum(tot.values())), "by_verdict": dict(tot),
           "median_expected_events": round(med, 3),
           "share_expected_below_3": round(float((e < W.MIN_EXPECTED).mean()), 3),
           "min_detectable_ratio_at_median": round(kmin / med, 1) if kmin and med > 0 else None,
           "decided": len(ratios_decided),
           "decided_ratio_median": round(float(np.median(ratios_decided)), 3) if ratios_decided else None,
           "decided_ratio_gt1_share": round(float(np.mean([r > 1 for r in ratios_decided])), 3) if ratios_decided else None}
    return {"by_kind": {k: dict(v) for k, v in by_kind.items()}, "store_level": why}


def agent_perf_summary(perf):
    ps = [(a, p) for a, p in perf.items() if p.get("rounds")]
    sk = [p["ll_skill"] for _, p in ps if p.get("ll_skill") is not None]
    lf = [p["lift_vs_uniform"] for _, p in ps if p.get("lift_vs_uniform")]
    ok = [(a, p) for a, p in ps if not p["data_quality"]["sample_flag"] and p.get("ll_skill") is not None]
    ok.sort(key=lambda x: -x[1]["ll_skill"])
    pick = lambda xs: [{"agent_id": a, "ll_skill": round(p["ll_skill"], 4), "lift": round(p["lift_vs_uniform"] or 0, 2),
                        "top1": p["top"]["1"], "top5": p["top"]["5"], "rounds": p["rounds"]} for a, p in xs]
    tot = Counter()
    for _, p in ps:
        for kk in ("1", "3", "5"):
            tot[f"top{kk}_hits"] += p["top"][kk]["hits"]
            tot[f"top{kk}_expected"] += p["top"][kk]["expected_uniform"]
        tot["history_hits"] += p["history_hits"]
        tot["explore_hits"] += p["explore_hits"]
    return {"agents": len(ps), "skill_positive": sum(1 for x in sk if x > 0), "skill_median": float(np.median(sk)) if sk else None,
            "lift_median": float(np.median(lf)) if lf else None, "low_sample": sum(1 for _, p in ps if p["data_quality"]["sample_flag"]),
            "totals": {k: (round(v, 2) if isinstance(v, float) else int(v)) for k, v in tot.items()},
            "best": pick(ok[:5]), "worst": pick(ok[-5:])}


def write_compat(wr, c, immutable=True):
    wr.put("research_agents", c["agents"], "agent_id,model_version")
    wr.put("research_agent_briefings", [{"model_version": MODEL, "target_round": c["briefing"]["target_round"],
                                         "training_end_round": c["briefing"]["training_end_round"], "payload": c["briefing"]}],
           "model_version,target_round,training_end_round")
    if not immutable:
        return
    wr.put("research_agent_deliveries", c["deliveries"], "model_version,target_round,agent_id,store_code,mode", True)
    if wr.db is not None and wr.db.exists("research_agent_score_sets"):
        by_agent = defaultdict(list)
        for r in c["scores"]:
            by_agent[r["agent_id"]].append(r)
        sets = []
        for ag, rs in by_agent.items():
            rs.sort(key=lambda r: r["agent_rank"])
            lf = [r["live_factor"] for r in rs]
            ef = [r["explore_factor"] for r in rs]
            sets.append({"model_version": MODEL, "target_round": rs[0]["target_round"], "agent_id": ag,
                         "store_codes": [r["store_code"] for r in rs], "scores": [r["score"] for r in rs],
                         "live_factors": lf if any(x != 1 for x in lf) else [],
                         "explore_factors": ef if any(x != 1 for x in ef) else [],
                         "hyp_counts": [r["hyp_count"] for r in rs], "first_share": c["first_share"],
                         "training_end_round": rs[0]["training_end_round"]})
        wr.put("research_agent_score_sets", sets, "model_version,target_round,agent_id", True)
    else:
        wr.put("research_agent_store_scores", c["scores"], "model_version,target_round,store_code", True)
    wr.put("research_agent_central", [c["central"]], "model_version,target_round,mode", True)
    wr.put("research_agent_briefings", [{"model_version": MODEL, "target_round": c["briefing"]["target_round"],
                                         "training_end_round": c["briefing"]["training_end_round"], "payload": c["briefing"]}],
           "model_version,target_round,training_end_round")


def summarize(u, eng, tr, perf, latest, replayed, provenance):
    st = Counter(STATUS[s] for s in eng.status)
    by_kind = defaultdict(Counter)
    for h in eng.st.H:
        by_kind[h["kind"]][STATUS[eng.status[h["idx"]]]] += 1
    store_level_passed = sum(c.get("passed", 0) + c.get("combined", 0) for k, c in by_kind.items() if k in STORE_SHARED_KINDS)
    tot = Counter()
    for r in tr.rounds:
        for m in r["agents"].values():
            for k in ("hits_any", "hits_first", "history_hits", "explore_hits", "expected_uniform", "ll_model", "ll_base"):
                tot[k] += m[k]
    cm = Counter()
    for c in tr.central:
        for k, v in c.items():
            if k != "t":
                cm[k] += v
    n = max(len(tr.central), 1)
    passed = [dict(summarize_h(u, eng, h), ratio=float(eng.test_ratio[h["idx"]]), q=float(eng.test_q[h["idx"]]),
                   first_discovered=h["discovered_round"])
              for h in eng.st.H if eng.status[h["idx"]] in (S_PASS, S_COMB)]
    return {"replay_run_id": RUN_ID, "model_version": MODEL, "latest": latest, "live_target": latest + 1,
            "rounds_replayed_this_run": replayed, "rounds_total": len(tr.rounds),
            "rounds_range": [tr.rounds[0]["t"], tr.rounds[-1]["t"]] if tr.rounds else [],
            "agents": len(u.agent_ids), "stores": u.S, "hypotheses": eng.H, "status_counts": dict(st),
            "status_by_kind": {k: dict(v) for k, v in by_kind.items()}, "store_level_passed": store_level_passed,
            "passed": passed, "shared_instances": sum(1 for h in eng.st.H if h.get("shared_from")),
            "agent_totals": {k: (int(v) if k in ("hits_any", "hits_first", "history_hits", "explore_hits") else round(float(v), 3))
                             for k, v in tot.items()},
            "agent_ll_skill": (1 - tot["ll_model"] / tot["ll_base"]) if tot["ll_base"] else None,
            "central": {"logloss_model": cm["logloss_model"] / n, "logloss_m0": cm["logloss_m0"] / n,
                        "logloss_m1": cm["logloss_m1"] / n, "focus_hits": int(cm["focus_hits"]),
                        "focus_hits_m0": int(cm["focus_hits_m0"]), "focus_expected": round(float(cm["focus_expected"]), 2),
                        "store_hits_any": int(cm["store_hits_any"]), "store_hits_history": int(cm["store_hits_history"]),
                        "store_expected_uniform": round(float(cm["store_expected_uniform"]), 2)},
            "agents_low_sample": sum(1 for p in perf.values() if p["data_quality"]["sample_flag"]),
            "provenance": provenance, "external_ai_api_calls": 0}


FREE_TIER_BYTES = 500 * 1024 * 1024     # Supabase 무료 플랜 DB 한도 (유료 전환은 하지 않는다)
WARN_PCT, CRITICAL_PCT, WARN_WEEKS = 70.0, 90.0, 26


def db_usage(db):
    """research_db_usage() RPC (service_role) — DB 전체·테이블별 바이트"""
    try:
        r = requests.post(db.base + "rpc/research_db_usage", headers=dict(db.h, **{"Content-Type": "application/json"}),
                          data="{}", timeout=60)
        if r.status_code == 200:
            d = r.json()
            tables = d.get("tables") or {}
            return {"database_bytes": d.get("database_bytes"), "free_tier_bytes": FREE_TIER_BYTES,
                    "research_bytes": int(sum(v for k, v in tables.items() if k.startswith("research_"))),
                    "tables": {k: int(v) for k, v in sorted(tables.items(), key=lambda x: -x[1])}}
        return {"error": f"{r.status_code} {r.text[:120]}"}
    except Exception as e:
        return {"error": str(e)[:120]}


def usage_update(prev, cur, latest_round):
    """사용량 이력·주간 증가량·한도 도달 예상·경고 단계"""
    prev = prev or {}
    hist = list(prev.get("history") or [])
    if cur.get("database_bytes") is None:
        return dict(prev, last_error=cur.get("error"))
    at = now()
    hist.append({"at": at, "database_bytes": int(cur["database_bytes"]), "research_bytes": int(cur.get("research_bytes") or 0),
                 "latest_round": latest_round})
    hist = hist[-80:]
    pct = 100.0 * cur["database_bytes"] / FREE_TIER_BYTES
    weekly = None
    t_now = datetime.fromisoformat(at)
    window = [h for h in hist if (t_now - datetime.fromisoformat(h["at"])).days <= 60]
    if len(window) >= 2:
        days = (datetime.fromisoformat(window[-1]["at"]) - datetime.fromisoformat(window[0]["at"])).total_seconds() / 86400
        if days >= 3:
            weekly = (window[-1]["database_bytes"] - window[0]["database_bytes"]) / days * 7
    est = prev.get("estimated_weekly_growth_bytes")
    use = weekly if weekly is not None else est
    weeks = (FREE_TIER_BYTES - cur["database_bytes"]) / use if use and use > 0 else None
    if pct >= CRITICAL_PCT:
        level, msg = "critical", f"DB {pct:.0f}% 사용 — 연구 기록 저장을 일시 중지했습니다. 유료 전환은 하지 않습니다. 정리 방안 승인이 필요합니다."
    elif pct >= WARN_PCT or (weeks is not None and weeks < WARN_WEEKS):
        level, msg = "warn", (f"DB {pct:.0f}% 사용" + (f" · 약 {weeks:.0f}주 뒤 무료 한도 도달 예상" if weeks is not None else "")
                              + " — 정리 계획이 필요합니다.")
    else:
        level, msg = "ok", f"DB {pct:.0f}% 사용" + (f" · 한도까지 약 {weeks:.0f}주" if weeks is not None else "")
    return {"latest": {"at": at, "database_bytes": int(cur["database_bytes"]), "research_bytes": int(cur.get("research_bytes") or 0),
                       "free_tier_bytes": FREE_TIER_BYTES, "pct": round(pct, 2)},
            "history": hist, "weekly_growth_bytes": weekly, "estimated_weekly_growth_bytes": est,
            "weeks_to_limit": weeks, "alert": {"level": level, "message": msg},
            "tables": {k: v for k, v in (cur.get("tables") or {}).items() if k.startswith("research_")},
            "top_tables": dict(list((cur.get("tables") or {}).items())[:10])}


def estimate_weekly(cur, rounds_total, score_sets):
    """측정된 테이블 크기로 회차당 증가량 추정 (실측 이력이 쌓이기 전 사용)"""
    t = cur.get("tables") or {}
    if not t or not rounds_total:
        return None
    replay = sum(v for k, v in t.items() if k.startswith("research_replay_") and k not in ("research_replay_hypotheses",
                                                                                           "research_replay_runs",
                                                                                           "research_replay_rounds"))
    per_round = replay / (rounds_total + 1)
    deliveries = t.get("research_agent_deliveries", 0) / 2          # ag-1.0·ag-1.1 의 1246 두 묶음
    scores = (t.get("research_agent_store_scores", 0) / 2) if not score_sets else 300_000
    return int(per_round + deliveries + scores)


def patch_run_stats(db, stats):
    requests.patch(db.base + "research_replay_runs", params={"replay_run_id": f"eq.{RUN_ID}"},
                   headers=dict(db.h, **{"Content-Type": "application/json", "Prefer": "return=minimal"}),
                   data=json.dumps(clean({"stats": stats, "updated_at": now()}), ensure_ascii=False, default=_json_default).encode("utf-8"),
                   timeout=60)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out", default=None)
    ap.add_argument("--until", type=int, default=None, help="이 회차까지만 처리 (재개 검증용)")
    ap.add_argument("--state-dir", default=None, help="로컬 상태 폴더 (지정 시 Storage 대신 사용)")
    ap.add_argument("--fresh", action="store_true", help="저장 상태 무시하고 999회 기준선부터 재현")
    ap.add_argument("--usage-only", action="store_true", help="DB 사용량만 측정·기록")
    ap.add_argument("--read-stored", action="store_true", help="dry-run 에서도 DB 의 동결 예측을 읽어 그대로 검증 (읽기 전용)")
    a = ap.parse_args()
    url, key = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY")
    if not url or not key:
        log("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다"); sys.exit(1)
    db = Db(url, key)
    if key.startswith("sb_"):
        db.h.pop("Authorization", None)
    if a.dry_run and not a.state_dir:
        log("--dry-run 은 --state-dir 와 함께 사용하세요 (Storage 쓰기 방지)"); sys.exit(1)
    raw = load(db)
    ready, pending = W.ready_latest(raw)
    if pending:
        log(f"[ready] 데이터 미준비 회차는 학습하지 않음: {pending}")
    usage = None
    if not a.dry_run:
        role = key_role(key)
        if role != "service_role":
            print(f"::warning::SUPABASE_KEY 역할이 service_role 이 아님({role}) — 실전형 재현 기록은 service_role 만 쓸 수 있습니다")
            print(json.dumps({"skipped": True, "reason": f"키 역할 {role}"})); return
        if not all(db.exists(t) for t in REPLAY_TABLES):
            print("::warning::research_v6_replay.sql 미적용 — 실전형 재현을 건너뜁니다")
            print(json.dumps({"skipped": True, "reason": "SQL 미적용"})); return
        run_row = db.select_all("research_replay_runs", {"select": "status,last_completed_round,last_prediction_round,stats", "order": "replay_run_id",
                                                         "replay_run_id": f"eq.{RUN_ID}"})
        prev_stats = (run_row[0].get("stats") or {}) if run_row else {}
        cur = db_usage(db)
        prev_usage = dict(prev_stats.get("usage") or {})
        est = estimate_weekly(cur, prev_stats.get("rounds_total"), db.exists("research_agent_score_sets"))
        if est:
            prev_usage["estimated_weekly_growth_bytes"] = est
        usage = usage_update(prev_usage, cur, ready)
        level = usage.get("alert", {}).get("level")
        if level in ("warn", "critical"):
            print(f"::warning::{usage['alert']['message']}")
        if pending:
            usage["pending_rounds"] = pending
        if run_row:
            patch_run_stats(db, dict(prev_stats, usage=usage))
        if a.usage_only:
            print(json.dumps(clean({"usage": {k: v for k, v in usage.items() if k != "history"}}), ensure_ascii=False)); return
        if level == "critical":
            print(json.dumps({"skipped": True, "reason": usage["alert"]["message"]}, ensure_ascii=False)); return
        if run_row and run_row[0]["status"] == "completed" and run_row[0]["last_completed_round"] == ready \
                and run_row[0]["last_prediction_round"] == ready + 1:
            log(f"[refresh] {ready}회까지 재현·{ready + 1}회 실전 동결 완료 — 새 회차 없음, 가설 판정·지방장 성과·브리핑만 갱신"
                + (f" ({pending[0]['round']}회 데이터 미준비)" if pending else ""))
    if not a.dry_run and run_row:
        dp = dict((db.select_all("research_replay_runs", {"select": "data_provenance", "order": "replay_run_id",
                                                           "replay_run_id": f"eq.{RUN_ID}"})[0].get("data_provenance")) or {})
        if dp.get("integrity_check") != INTEGRITY_CHECK:
            dp["integrity_check"] = INTEGRITY_CHECK
            requests.patch(db.base + "research_replay_runs", params={"replay_run_id": f"eq.{RUN_ID}"},
                           headers=dict(db.h, **{"Content-Type": "application/json", "Prefer": "return=minimal"}),
                           data=json.dumps({"data_provenance": dp, "updated_at": now()}, ensure_ascii=False).encode("utf-8"),
                           timeout=60)
    try:
        totals, compat = run(db, key, a, raw=raw, ready=ready)
    except Exception as e:
        if not a.dry_run:
            try:
                db.upsert("research_replay_runs", [{"replay_run_id": RUN_ID, "model_version": MODEL, "replay_mode": REPLAY_MODE,
                                                    "status": "failed", "start_round": LEARN_START, "error": str(e)[:500],
                                                    "updated_at": now()}], "replay_run_id")
            except Exception:
                pass
        raise
    if not a.dry_run:
        cur = db_usage(db)
        u2 = usage_update(usage, cur, ready)
        if pending:
            u2["pending_rounds"] = pending
        totals["usage"] = u2
        patch_run_stats(db, clean(totals))
    if a.out:
        json.dump(clean({"summary": totals, "hashes": compat.get("hashes"), "live_hash": compat.get("live_hash"),
                         "last_eval": compat.get("last_eval"), "hyp_sample": compat.get("hyp_sample"), "agent_perf_summary": compat["briefing"].get("agent_performance"), "verdicts": compat["briefing"].get("hypothesis_verdicts"),
                         "live_central_top": compat["central"]["focus_regions"][:10],
                         "live_store_top": compat["central"]["store_top"][:10], "briefing": compat["briefing"],
                         "agent_perf_sample": {k: v for k, v in list({x["agent_id"]: x["performance"] for x in compat["agents"]}.items())
                                               if k in ("서울|노원구", "인천|남동구", "충남|천안시", "internet")}}),
                  open(a.out, "w", encoding="utf-8"), ensure_ascii=False, default=_json_default)
    print(json.dumps(clean({k: v for k, v in totals.items() if k not in ("passed", "usage")}), ensure_ascii=False, default=_json_default))


if __name__ == "__main__":
    # 상태 파일의 클래스 경로를 실행 방식과 무관하게 research_agent_replay.Track 으로 고정
    sys.modules.setdefault("research_agent_replay", sys.modules[__name__])
    Track.__module__ = "research_agent_replay"
    main()
