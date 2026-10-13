"""
엔진 복기 연구소 — 중앙 엔진 회차 복기 · 지방장 누적 성적표 · 비서 복기 브리핑 (rv-1.0)

입력 (모두 저장된 결과, 읽기 전용):
  · 지방장 회차 복기  research_review_agent_rounds   (research_agent_replay.py 가 회차 루프에서 저장)
  · 지방장 사전 예측  research_replay_predictions / results / central_evals (ag-1.1-r1)
  · 번호 사전 예측    research_results(final_recommendation fr-1.0, purchase_model) · research_public_purchase
                       · research_predictions(사전 등록·채점) · rpa_prediction_results(number_base)
  · 실제 결과         lotto_winning_numbers · winning_history
출력: research_review_rounds(회차별 중앙 복기 + 브리핑), research_review_agent_cards(지방장 성적표), research_review_runs

원칙
  · 추첨 후에 만든 예측은 사전 예측으로 평가하지 않는다 (생성 시각 > 판매 마감이면 '사후 생성'으로 분리 표시)
  · 번호 일치와 판매점 적중을 하나의 당첨확률로 섞지 않는다. 모든 6개 조합의 1등 확률은 같다.
  · 판매량 분모가 없으므로 판매점별 한 장당 당첨확률을 주장하지 않는다.
  · 브리핑 문장은 저장된 수치로만 만든다 (수치가 없으면 '데이터 미확보').
  · 과거 순차 재현(sequential_replay)은 실제 당시 실전 기록이 아니라고 표시한다.

사용
  python research_review_worker.py            # 미확정 회차 + 성적표 + 최신 브리핑 (서버, service_role)
  python research_review_worker.py --all      # 1000회부터 전 회차 다시 작성 (확정 회차는 건너뜀)
  python research_review_worker.py --dry-run  # 쓰기 없이 계산만 (anon 키로도 가능)
"""

import argparse
import json
import math
import os
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

import requests

REVIEW_VERSION = "rv-1.0"
REPLAY_RUN = "ag-1.1-r1"
AGENT_MODEL = "ag-1.1"
FR_VERSION = "fr-1.0"
NUMBER_ENGINE_VERSION = "2.1"
START_ROUND = 1000
RANDOM_MEAN_MATCHES = 6 * 6 / 45   # 무작위 조합의 기대 일치 개수 0.8
GROUP_LABEL = {"cycle": "주기", "lead": "선행·후행", "cowin": "동시 당첨", "spatial": "공간전이(인접 확산)",
               "trend": "지역 추세", "composite": "복합 조건", "other": "기타"}
RANK_LABEL = {1: "1등", 2: "2등", 3: "3등", 4: "4등", 5: "5등", 0: "낙첨"}


def now_iso():
    return datetime.now(timezone.utc).isoformat()


class Db:
    def __init__(self, url, key, dry=False):
        self.base = url.rstrip("/") + "/rest/v1/"
        self.h = {"apikey": key, "Content-Type": "application/json"}
        if not key.startswith("sb_"):
            self.h["Authorization"] = f"Bearer {key}"
        self.dry = dry

    def get(self, table, params):
        r = requests.get(self.base + table, params=params, headers=self.h, timeout=120)
        if r.status_code != 200:
            raise RuntimeError(f"select {table} {r.status_code} {r.text[:200]}")
        return r.json()

    def all(self, table, params, key="target_round", page=1000):
        """키 순서 페이지 조회 (정렬 키 고유하지 않으면 offset 대신 order+range 전체)"""
        out, off = [], 0
        while True:
            h = dict(self.h, **{"Range-Unit": "items", "Range": f"{off}-{off + page - 1}"})
            r = requests.get(self.base + table, params=params, headers=h, timeout=120)
            if r.status_code not in (200, 206):
                raise RuntimeError(f"select {table} {r.status_code} {r.text[:200]}")
            rows = r.json()
            out.extend(rows)
            if len(rows) < page:
                return out
            off += page

    def exists(self, table):
        r = requests.get(self.base + table, params={"select": "*", "limit": "0"}, headers=self.h, timeout=60)
        return r.status_code in (200, 206)

    def upsert(self, table, rows, on, ignore=False):
        if self.dry or not rows:
            return
        pref = "resolution=ignore-duplicates" if ignore else "resolution=merge-duplicates"
        for i in range(0, len(rows), 50):
            r = requests.post(self.base + table, params={"on_conflict": on}, headers=dict(self.h, Prefer=pref + ",return=minimal"),
                              data=json.dumps(rows[i:i + 50], ensure_ascii=False).encode("utf-8"), timeout=120)
            if r.status_code not in (200, 201, 204):
                raise RuntimeError(f"upsert {table} {r.status_code} {r.text[:300]}")

    def insert(self, table, row):
        if self.dry:
            return None
        r = requests.post(self.base + table, headers=dict(self.h, Prefer="return=representation"),
                          data=json.dumps(row, ensure_ascii=False).encode("utf-8"), timeout=60)
        if r.status_code not in (200, 201):
            raise RuntimeError(f"insert {table} {r.status_code} {r.text[:200]}")
        return r.json()[0]["id"]

    def patch(self, table, params, row):
        if self.dry:
            return
        r = requests.patch(self.base + table, params=params, headers=dict(self.h, Prefer="return=minimal"),
                           data=json.dumps(row, ensure_ascii=False).encode("utf-8"), timeout=60)
        if r.status_code not in (200, 204):
            raise RuntimeError(f"patch {table} {r.status_code} {r.text[:200]}")


# ── 공통 계산 ──────────────────────────────────────────────────────
def score_set(nums, actual, bonus):
    m = len(set(nums) & set(actual))
    b = bonus in nums
    rank = 1 if m == 6 else 2 if (m == 5 and b) else 3 if m == 5 else 4 if m == 4 else 5 if m == 3 else 0
    return {"numbers": sorted(nums), "matches": m, "bonus": int(b), "rank": rank}


def score_sets(sets, actual, bonus):
    sc = [score_set(s, actual, bonus) for s in sets if s and len(s) == 6]
    if not sc:
        return None
    ranks = [x["rank"] for x in sc if x["rank"] > 0]
    return {"sets": sc, "mean_matches": round(sum(x["matches"] for x in sc) / len(sc), 3),
            "best_matches": max(x["matches"] for x in sc), "best_rank": min(ranks) if ranks else 0,
            "random_expected_mean": round(RANDOM_MEAN_MATCHES, 3)}


def sales_close_utc(draw_date, round_no):
    """추첨일(토) 20:00 KST 판매 마감 = 11:00 UTC. DB 추첨일이 없으면 공식 일정(1회 = 2002-12-07, 매주)."""
    try:
        d = datetime.strptime(str(draw_date)[:10].replace(".", "-"), "%Y-%m-%d")
    except ValueError:
        d = datetime(2002, 12, 7) + timedelta(days=7 * (round_no - 1))
    return datetime(d.year, d.month, d.day, 11, tzinfo=timezone.utc)


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except ValueError:
        return None


def poisson_sf(k, lam):
    """P(X ≥ k), X~Poisson(lam)"""
    if k <= 0:
        return 1.0
    if lam <= 0:
        return 0.0
    term = math.exp(-lam)
    cdf = term
    for i in range(1, k):
        term *= lam / i
        cdf += term
    return max(0.0, 1 - cdf)


# ── 데이터 로드 ────────────────────────────────────────────────────
def load(db, rounds_needed):
    lo, hi = min(rounds_needed), max(rounds_needed)
    rng = {"target_round": f"gte.{lo}", "and": f"(target_round.lte.{hi + 1})"}
    nums = {r["round"]: r for r in db.all("lotto_winning_numbers", {"select": "round,draw_date,num1,num2,num3,num4,num5,num6,bonus",
                                                                    "round": f"gte.{lo - 1}", "order": "round"})}
    agent_rounds = {}
    for r in db.all("research_review_agent_rounds", {"select": "target_round,prediction_mode,round_valid,agent_ids,entries,spatial,summary,integrity",
                                                     "review_version": f"eq.{REVIEW_VERSION}", "order": "target_round"}, page=25):
        agent_rounds[r["target_round"]] = r
    preds = {r["target_round"]: r for r in db.all("research_replay_predictions", dict(rng, **{
        "select": "target_round,replay_mode,prediction_created_at,available_data_through_round,focus_regions,store_top,live_hypotheses_applied",
        "replay_run_id": f"eq.{REPLAY_RUN}", "order": "target_round"}), page=200)}
    results = {r["target_round"]: r for r in db.all("research_replay_results", dict(rng, **{
        "select": "target_round,first_store_ids,first_regions,event_store_count,unmatched_first,data_provenance",
        "replay_run_id": f"eq.{REPLAY_RUN}", "order": "target_round"}))}
    cevals = {r["target_round"]: r["evaluation_metrics"] for r in db.all("research_replay_central_evals", dict(rng, **{
        "select": "target_round,evaluation_metrics", "replay_run_id": f"eq.{REPLAY_RUN}", "order": "target_round"}))}
    fr = defaultdict(list)
    for r in db.all("research_results", dict(rng, **{"select": "id,target_round,training_end_round,created_at,payload->sets,payload->generated_at,payload->signals,payload->verified_edge",
                                                      "research_type": "eq.final_recommendation", "model_version": f"eq.{FR_VERSION}",
                                                      "order": "target_round,training_end_round"})):
        fr[r["target_round"]].append(r)
    pur = defaultdict(list)
    for r in db.all("research_results", dict(rng, **{"select": "id,target_round,training_end_round,model_version,created_at,payload->recommendations,payload->validation_status,payload->ranking_source",
                                                      "research_type": "eq.purchase_model", "order": "target_round,training_end_round"})):
        pur[r["target_round"]].append(r)
    public = {}
    if db.exists("research_public_purchase"):
        public = {r["target_round"]: r for r in db.all("research_public_purchase", dict(rng, **{
            "select": "target_round,source_research_id,sets,updated_at", "order": "target_round"}))}
    reg = defaultdict(list)
    for r in db.all("research_predictions", dict(rng, **{"select": "algorithm,version,target_round,sets,created_at,status,verification",
                                                          "order": "target_round,algorithm,version"})):
        reg[r["target_round"]].append(r)
    nb = {}
    for r in db.all("rpa_prediction_results", dict(rng, **{
            "select": "target_round,training_end_round,generated_at,payload->sets,verification",
            "model_version": f"eq.{NUMBER_ENGINE_VERSION}", "prediction_type": "eq.number_base",
            "order": "target_round,training_end_round"})):
        if r["training_end_round"] == r["target_round"] - 1:
            nb[r["target_round"]] = r
    corr = {r["target_round"]: r for r in db.all("rpa_round_scores", dict(rng, **{
        "select": "target_round,theory_score,correction_score,correction_effect", "order": "target_round"}))}
    return dict(nums=nums, agent_rounds=agent_rounds, preds=preds, results=results, cevals=cevals, fr=fr, pur=pur,
                public=public, reg=reg, nb=nb, corr=corr)


def store_names(db, codes):
    out = {}
    codes = sorted({c for c in codes if c})
    for i in range(0, len(codes), 150):
        for r in db.get("lottery_stores", {"select": "dhlottery_code,store_name,region", "lottery_type": "eq.lotto",
                                           "dhlottery_code": f"in.({','.join(codes[i:i + 150])})"}):
            out.setdefault(r["dhlottery_code"], r["store_name"])
    return out


# ── 회차 복기 ──────────────────────────────────────────────────────
def numbers_review(t, d):
    w = d["nums"].get(t)
    if not w:
        return {"status": "당첨번호 미확보"}, False
    actual = [w[f"num{i}"] for i in range(1, 7)]
    bonus = w["bonus"]
    close = sales_close_utc(w["draw_date"], t)
    out = {"actual": sorted(actual), "bonus": bonus, "draw_date": w["draw_date"]}

    def pre(ts):
        p = parse_ts(ts)
        return None if p is None else p < close

    # 공식 최종 추천번호 (목표 회차의 최신 학습 스냅샷 = 화면에 공식으로 쓰던 것)
    frs = d["fr"].get(t, [])
    if frs:
        f = max(frs, key=lambda r: r["training_end_round"])
        sc = score_sets(f.get("sets") or [], actual, bonus)
        out["official"] = dict(sc or {}, snapshot_id=f["id"], training_end_round=f["training_end_round"],
                               generated_at=f.get("generated_at") or f["created_at"],
                               pre_draw=pre(f.get("generated_at") or f["created_at"]), model_version=FR_VERSION)
    else:
        out["official"] = {"status": "이 회차 공식 최종 추천번호 저장본 없음"}
    # 구매예측 (최신 모델 → 최신 학습)
    ps = d["pur"].get(t, [])
    if ps:
        p = max(ps, key=lambda r: (tuple(int(x) for x in r["model_version"].replace("pp-", "").split(".")), r["training_end_round"]))
        sets = [r["numbers"] for r in (p.get("recommendations") or [])]
        sc = score_sets(sets, actual, bonus)
        out["purchase"] = dict(sc or {"status": "추천 세트 없음 (검증 미통과 회차)"}, research_id=p["id"], model_version=p["model_version"],
                               training_end_round=p["training_end_round"], pre_draw=pre(p["created_at"]),
                               validation_status=p.get("validation_status"))
        pub = d["public"].get(t)
        if pub:
            psets = [x["numbers"] for x in pub.get("sets") or []]
            out["public"] = dict(score_sets(psets, actual, bonus) or {}, source_research_id=pub["source_research_id"],
                                 matches_admin_top3=psets == [sorted(s) for s in sets[:3]], pre_draw=pre(pub["updated_at"]))
    else:
        out["purchase"] = {"status": "이 회차 구매예측 저장본 없음"}
    # 사전 등록·채점 (번호 엔진·구매예측·무작위 대조군)
    regs = []
    for r in d["reg"].get(t, []):
        sc = score_sets(r.get("sets") or [], actual, bonus)
        regs.append(dict(sc or {}, algorithm=r["algorithm"], version=r["version"], status=r.get("status"),
                         pre_draw=pre(r["created_at"])))
    out["registry"] = regs
    # 번호 엔진 기본 조합 (t-1 학습)
    nbr = d["nb"].get(t)
    if nbr:
        sc = score_sets(nbr.get("sets") or [], actual, bonus)
        out["number_engine"] = dict(sc or {}, training_end_round=nbr["training_end_round"], pre_draw=pre(nbr["generated_at"]),
                                    model_version=NUMBER_ENGINE_VERSION)
    return out, True


def regions_stores_review(t, d, names):
    p, res, ce = d["preds"].get(t), d["results"].get(t), d["cevals"].get(t)
    if not (p and res and ce):
        return {"status": "지역 예측·결과 미확보"}, {"status": "판매점 예측·결과 미확보"}, False
    first_regions = set(res.get("first_regions") or [])
    focus = [x["region_id"] for x in (p.get("focus_regions") or [])][:10]
    regions = {"focus_top10": [{"region_id": r, "hit": r in first_regions} for r in focus],
               "focus_hits": ce.get("focus_hits"), "focus_hits_store_count_baseline": ce.get("focus_hits_m0"),
               "focus_expected": round(ce.get("focus_expected") or 0, 3), "regions_with_first": ce.get("regions_with_first"),
               "logloss_model": ce.get("logloss_model"), "logloss_store_count_baseline": ce.get("logloss_m0"),
               "logloss_frequency_baseline": ce.get("logloss_m1")}
    firsts = res.get("first_store_ids") or []
    top = p.get("store_top") or []
    top_codes = [x["store_code"] for x in top]
    stores = {"store_top20": [{"store_code": x["store_code"], "name": x.get("name"), "agent_id": x.get("agent_id"),
                               "hit_first": x["store_code"] in firsts} for x in top],
              "first_stores": [{"store_code": c, "name": names.get(c), "in_top20": c in top_codes} for c in firsts],
              "hits_first": ce.get("store_hits_first"), "hits_any": ce.get("store_hits_any"),
              "history_baseline_hits_any": ce.get("store_hits_history"),
              "uniform_expected_any": round(ce.get("store_expected_uniform") or 0, 3), "events": ce.get("events"),
              "unmatched_first": res.get("unmatched_first")}
    return regions, stores, True


def agents_review(t, d, names):
    r = d["agent_rounds"].get(t)
    if not r:
        return {"status": "지방장 복기 미확보"}, {}, {}, False
    ids, ents = r["agent_ids"], r["entries"]
    good, missed, chg = [], [], []
    for ag, e in zip(ids, ents):
        if e.get("h") and e["h"][2] > 0:
            good.append({"agent_id": ag, "top1": e["h"][0], "top3": e["h"][1], "top5": e["h"][2], "expected_top5": e["x"][2],
                         "n_stores": e["n"]})
        for w in e.get("w", []):
            if w[2] is None and w[1] is not None:
                missed.append({"agent_id": ag, "store_code": w[0], "name": names.get(w[0]), "prior_rank": w[1], "n_stores": e["n"]})
        for c in e.get("c", []):
            chg.append({"agent_id": ag, "hypothesis_id": c[0], "kind": c[1], "from": c[2], "to": c[3],
                        "live_before": bool(c[4]), "live_after": bool(c[5]), "factor_before": c[6], "factor_after": c[7],
                        "test_n": c[8], "test_k": c[9], "test_expected": c[10], "test_p": c[11],
                        "applied": c[4] != c[5],
                        "reason": ("실전 배수 반영" if c[5] and not c[4] else "실전 배수 해제" if c[4] and not c[5]
                                   else "실전 반영 상태 변화 없음 (검증 기준·표본 기준 미달 또는 이미 반영 중)")})
    missed.sort(key=lambda x: (x["prior_rank"], x["n_stores"]))
    sm = r["summary"]
    agents = {"mode": r["prediction_mode"], "round_valid": r["round_valid"], "summary": sm,
              "top_hits": sorted(good, key=lambda x: (-x["top5"], -x["top1"], x["expected_top5"]))[:10],
              "near_misses": missed[:10], "integrity": r["integrity"]}
    spatial = {k: {"label": GROUP_LABEL.get(k, k), "fired": v[0], "success": v[1], "expected": v[2], "live_fired": v[3]}
               for k, v in (r.get("spatial") or {}).items()}
    corrections = {"items": chg[:60], "count": len(chg), "applied": sum(1 for c in chg if c["applied"]),
                   "routine_transitions": sm.get("routine_changes", 0), "new_hypotheses": sm.get("new_hypotheses", 0),
                   "by_to_status": dict(Counter(c["to"] for c in chg))}
    return agents, spatial, corrections, True


def signals_review(t, d):
    """적용 신호 vs 연구용 신호 (공식 최종 추천 스냅샷의 signals), 다음 회차 비교"""
    def sig(tt):
        frs = d["fr"].get(tt, [])
        if not frs:
            return None
        s = max(frs, key=lambda r: r["training_end_round"]).get("signals") or {}
        return {"hypothesis_applied": (s.get("hypothesis") or {}).get("applied"),
                "hypothesis_directions": (s.get("hypothesis") or {}).get("directions"),
                "correction_applied": (s.get("correction") or {}).get("applied"),
                "joint_applied": (s.get("joint") or {}).get("applied"),
                "store_spatial_mnd": (s.get("store_spatial_mnd") or {}).get("reason")}
    nxt_pred = d["preds"].get(t + 1)
    cur_pred = d["preds"].get(t)
    return {"this_round": sig(t), "next_round": sig(t + 1),
            "agent_live_hypotheses_this": len((cur_pred or {}).get("live_hypotheses_applied") or []) if cur_pred else None,
            "agent_live_hypotheses_next": len((nxt_pred or {}).get("live_hypotheses_applied") or []) if nxt_pred else None,
            "next_prediction_frozen": bool(nxt_pred), "number_engine_correction": d["corr"].get(t)}


# ── 비서 브리핑 (저장 수치로만) ─────────────────────────────────────
def _fmt_sets(x, label):
    if not x or "sets" not in x:
        return f"{label}: {x.get('status', '데이터 미확보') if x else '데이터 미확보'}"
    tag = "" if x.get("pre_draw") is not False else " (추첨 후 생성본 — 사전 예측 아님)"
    br = RANK_LABEL.get(x["best_rank"], "낙첨")
    return (f"{label} {len(x['sets'])}세트: 최고 {x['best_matches']}개 일치({br}) · 평균 {x['mean_matches']:.2f}개 "
            f"(무작위 기대 {x['random_expected_mean']:.1f}개){tag}")


def build_briefing(t, rv, cards_rank):
    nums, regions, stores, agents = rv["numbers"], rv["regions"], rv["stores"], rv["agents"]
    sp, corr, sig = rv["spatial"], rv["corrections"], rv["signals"]
    mode = agents.get("mode") if isinstance(agents, dict) else None
    lines = [f"마스터, {t}회 복기 결과를 보고드리겠습니다."]
    if mode == "sequential_replay":
        lines.append("※ 이 회차는 과거 순차 재현(당시 데이터만 사용해 다시 계산)이며, 실제 당시 실전 사전 예측 기록이 아닙니다.")
    elif mode == "live":
        lines.append("※ 추첨 전에 동결해 둔 실전 사전 예측과 실제 결과를 비교했습니다.")
    sec = {}
    if "focus_hits" in regions:
        sec["1"] = (f"중앙 엔진 총평: 추천 지역 TOP10 중 실제 1등 지역 {regions['focus_hits']}곳 "
                    f"(판매점 수 비례 기준 {regions['focus_hits_store_count_baseline']}곳 · 모델 기대 {regions['focus_expected']:.1f}곳), "
                    f"이번 회차 1등이 나온 지역 {regions['regions_with_first']}곳.")
    else:
        sec["1"] = "중앙 엔진 총평: 지역 예측 또는 결과 데이터 미확보."
    if "actual" in nums:
        parts = [_fmt_sets(nums.get("official"), "공식 최종 추천번호"), _fmt_sets(nums.get("purchase"), "구매예측번호")]
        if nums.get("public"):
            parts.append(_fmt_sets(nums["public"], "일반 공개"))
        if nums.get("number_engine"):
            parts.append(_fmt_sets(nums["number_engine"], "번호 엔진 기본 조합"))
        rc = [x for x in nums.get("registry", []) if x.get("algorithm") == "random_control" and "sets" in x]
        if rc:
            parts.append(_fmt_sets(rc[0], "무작위 대조군"))
        sec["2"] = f"추천번호 적중 (당첨번호 {' '.join(map(str, nums['actual']))} + {nums['bonus']}): " + " / ".join(parts) \
            + ". 모든 번호 조합의 1등 확률은 같습니다."
    else:
        sec["2"] = "추천번호 적중: 당첨번호 데이터 미확보."
    if "hits_first" in stores:
        sm = agents.get("summary", {}) if isinstance(agents, dict) else {}
        sec["3"] = (f"지역·판매점: 1등 판매점 {len(stores['first_stores'])}곳 중 중앙 추천 TOP20 포함 {stores['hits_first']}곳 "
                    f"(1·2등 기준 {stores['hits_any']}곳, 무작위 기대 {stores['uniform_expected_any']:.2f}곳, 과거 빈도 기준 {stores['history_baseline_hits_any']}곳)"
                    + (f" · 지방장 TOP5 1등 적중 {sm.get('top_first_hits', [0, 0, 0])[2]}곳 (지역 내 무작위 기대 {sm.get('top_expected_uniform', [0, 0, 0])[2]:.2f}곳, "
                       f"과거 빈도만 쓴 TOP5 {sm.get('history_first_hits5', 0)}곳)" if sm else ""))
    else:
        sec["3"] = "지역·판매점: 데이터 미확보."
    if isinstance(agents, dict) and agents.get("summary"):
        sm = agents["summary"]
        sec["4"] = (f"지방장 복기: {sm['agents']}명 중 {sm['reviewed']}명 복기 완료 · 1등이 나온 지역 {sm['region_first_agents']}곳"
                    + (f" · 지역 미배정 1등 {sm['unassigned_first']}곳" if sm.get("unassigned_first") else "")
                    + (f" · 재계산 목록과 동결 목록 {'일치' if agents['integrity'].get('recompute_matches_stored') else '불일치'}"
                       if agents["integrity"].get("stored_snapshot_used") else ""))
        good = agents.get("top_hits") or []
        sec["5"] = ("이번 회차 적중 지방장: " + ", ".join(f"{g['agent_id']}(TOP5 {g['top5']}곳, 무작위 기대 {g['expected_top5']:.2f})" for g in good[:5])
                    if good else "이번 회차 TOP5 안에서 1등을 맞힌 지방장은 없습니다.")
        if cards_rank and cards_rank.get("best"):
            sec["5"] += " · 누적(기대 3곳 이상) 상위: " + ", ".join(
                f"{c['agent_id']}(적중 {c['hits']}/기대 {c['expected']:.1f})" for c in cards_rank["best"][:3]) \
                + " · 하위: " + ", ".join(f"{c['agent_id']}(적중 {c['hits']}/기대 {c['expected']:.1f})" for c in cards_rank["worst"][:3])
        nm = agents.get("near_misses") or []
        sec["6"] = ("놓친 주요 사례(추천 밖에서 1등): " + ", ".join(
            f"{m['agent_id']} {m['name'] or m['store_code']} (사전 {m['prior_rank']}위/{m['n_stores']}곳)" for m in nm[:5])
                    if nm else "추천 밖에서 나온 1등은 없거나 지역에 1등이 없었습니다.")
    else:
        sec["4"] = sec["5"] = sec["6"] = "지방장 복기 미완료 (데이터 대기)."
    if sp:
        sec["7"] = "공간전이·동시 당첨·관계 가설: " + ", ".join(
            f"{v['label']} 발화 {v['fired']}건 중 적중 {v['success']}건(대조 기대 {v['expected']:.1f}건)" for v in sp.values()) \
            + ". 판정은 누적 검정(최소 표본·다중 검정 보정) 기준이며 한 회차로 바꾸지 않습니다."
    else:
        sec["7"] = "공간전이·동시 당첨 가설: 발화 기록 없음 또는 데이터 미확보."
    if corr:
        bt = corr.get("by_to_status") or {}
        sec["8"] = ("가설 판정 변화: " + (", ".join(f"{k} {v}건" for k, v in bt.items()) if bt else "주요 판정 변화 없음")
                    + f" · 일상 전환 {corr.get('routine_transitions', 0)}건 · 신규 후보 {corr.get('new_hypotheses', 0)}건")
        ap = [c for c in corr.get("items", []) if c["applied"]]
        sec["9"] = ("이번 회차 보정: " + ", ".join(
            f"{c['agent_id']} {c['kind']} 배수 {c['factor_before']}→{c['factor_after']}" for c in ap[:5])
                    if ap else "이번 회차 실전 배수가 바뀐 보정은 없습니다 (검증 기준 미달 — 한 번의 실패·성공으로 가중치를 바꾸지 않음).")
        ne = (sig or {}).get("number_engine_correction")
        if ne and ne.get("correction_effect") is not None:
            sec["9"] += f" 번호 엔진 보정 효과(이론 대비) {ne['correction_effect']:+.3f}."
    else:
        sec["8"] = sec["9"] = "가설·보정: 데이터 미확보."
    if sig:
        nx = sig.get("next_round") or {}
        sec["10"] = (f"다음 회차 반영: 지방장 실전 적용 가설 {sig.get('agent_live_hypotheses_this')}→{sig.get('agent_live_hypotheses_next')}개"
                     if sig.get("next_prediction_frozen") else "다음 회차 지방장 예측: 아직 동결 전")
        if nx:
            sec["10"] += (f" · 다음 회차 공식 번호 신호: 가설 {'적용' if nx.get('hypothesis_applied') else '미적용'}, "
                          f"보정 {'적용' if nx.get('correction_applied') else '미적용'}, Joint {'적용' if nx.get('joint_applied') else '미적용'}")
    else:
        sec["10"] = "다음 회차 반영: 데이터 미확보."
    order = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
    marks = "①②③④⑤⑥⑦⑧⑨⑩"
    lines += [f"{marks[i]} {sec[k]}" for i, k in enumerate(order)]
    return {"lines": lines, "sections": sec, "generated_at": now_iso(), "source": "research_review_rounds 저장 수치"}


# ── 지방장 성적표 ───────────────────────────────────────────────────
def build_cards(d, agents_meta, hyp_counts):
    rounds = sorted(d["agent_rounds"])
    if not rounds:
        return [], {}
    ids = d["agent_rounds"][rounds[-1]]["agent_ids"]
    focus_by_round = {t: {x["region_id"] for x in (d["preds"].get(t, {}).get("focus_regions") or [])[:10]} for t in rounds}
    first_by_round = {t: set((d["results"].get(t) or {}).get("first_regions") or []) for t in rounds}
    cards, rank_pool = [], []
    for a, ag in enumerate(ids):
        seq = []
        for t in rounds:
            r = d["agent_rounds"][t]
            idx = a if r["agent_ids"][a:a + 1] == [ag] else (r["agent_ids"].index(ag) if ag in r["agent_ids"] else None)
            if idx is not None:
                seq.append((t, r["entries"][idx]))

        def agg(rs):
            if not rs:
                return {"rounds": 0}
            h = [sum(e.get("h", [0, 0, 0])[j] for _, e in rs) for j in range(3)]
            x = [sum(e.get("x", [0, 0, 0])[j] for _, e in rs) for j in range(3)]
            winners = sum(e.get("rf", 0) for _, e in rs)
            ranks = [w[1] for _, e in rs for w in e.get("w", []) if w[1] is not None]
            fr_rounds = [(t, e) for t, e in rs if t in focus_by_round]
            in_focus = [t for t, _ in fr_rounds if ag in focus_by_round[t]]
            return {"rounds": len(rs), "rounds_with_first": sum(1 for _, e in rs if e.get("rf")), "first_winners": winners,
                    "no_winner_rounds": sum(1 for _, e in rs if not e.get("rf")),
                    "top_hits": h, "top_expected_uniform": [round(v, 3) for v in x],
                    "top5_lift": round(h[2] / x[2], 3) if x[2] > 0 else None,
                    "top5_p_value": round(poisson_sf(h[2], x[2]), 5) if x[2] > 0 else None,
                    "sample_flag": "표본 부족" if x[2] < 3 else None,
                    "history_top5_hits": sum(e.get("hh", 0) for _, e in rs), "any_top5_hits": sum(e.get("a5", 0) for _, e in rs),
                    "outside_winners": sum(1 for _, e in rs for w in e.get("w", []) if w[2] is None),
                    "winner_prior_rank_median": statistics.median(ranks) if ranks else None,
                    "winner_prior_rank_top5": sum(1 for v in ranks if v <= 5),
                    "focus_rounds": len(in_focus), "focus_region_first": sum(1 for t in in_focus if ag in first_by_round.get(t, set())),
                    "hypotheses_fired": {k: sum(e.get("g", {}).get(k, [0])[0] for _, e in rs) for k in GROUP_LABEL},
                    "hypotheses_success": {k: sum((e.get("g", {}).get(k, [0, 0])[1]) for _, e in rs) for k in GROUP_LABEL}}
        all_ = agg(seq)
        card = {"10": agg(seq[-10:]), "30": agg(seq[-30:]), "100": agg(seq[-100:]), "all": all_,
                "live_rounds": agg([(t, e) for t, e in seq if d["agent_rounds"][t]["prediction_mode"] == "live"])}
        meta = agents_meta.get(ag, {})
        chg = [c for _, e in seq for c in e.get("c", [])]
        cards.append({"review_version": REVIEW_VERSION, "agent_id": ag, "agent_index": a, "sido": meta.get("sido"),
                      "unit_name": meta.get("unit_name"), "through_round": rounds[-1], "n_stores": seq[-1][1]["n"] if seq else None,
                      "cards": card, "hypotheses": hyp_counts.get(ag, {}),
                      "corrections": {"meaningful": len(chg), "live_changed": sum(1 for c in chg if c[4] != c[5]),
                                      "routine": sum(e.get("cc", 0) for _, e in seq), "new_hypotheses": sum(e.get("nw", 0) for _, e in seq)},
                      "updated_at": now_iso()})
        if all_["rounds"] and all_["top_expected_uniform"][2] >= 3 and ag != "internet":
            rank_pool.append({"agent_id": ag, "hits": all_["top_hits"][2], "expected": all_["top_expected_uniform"][2],
                              "lift": all_["top5_lift"], "p": all_["top5_p_value"]})
    rank_pool.sort(key=lambda c: (-(c["lift"] or 0), c["p"] or 1))
    return cards, {"best": rank_pool[:5], "worst": list(reversed(rank_pool[-5:])), "eligible": len(rank_pool)}


def hypothesis_counts(db):
    out = defaultdict(Counter)
    rows = db.all("research_replay_hypotheses", {"select": "agent_id,status,evidence->>verdict",
                                                  "replay_run_id": f"eq.{REPLAY_RUN}", "order": "hypothesis_id"})
    for r in rows:
        out[r.get("agent_id")][r.get("verdict") or r.get("status")] += 1
    return {k: dict(v) for k, v in out.items()}


def agents_meta(db):
    return {r["agent_id"]: r for r in db.all("research_agents", {"select": "agent_id,sido,unit_name",
                                                                  "model_version": f"eq.{AGENT_MODEL}", "order": "agent_id"})}


# ── 실행 ──────────────────────────────────────────────────────────
def run(db, all_rounds=False, only=None):
    started = now_iso()
    run_id = None
    if not db.dry and db.exists("research_review_runs"):
        run_id = db.insert("research_review_runs", {"review_version": REVIEW_VERSION, "kind": "central", "status": "running",
                                                    "runner": os.environ.get("GITHUB_RUN_ID")})
    try:
        latest = db.get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})[0]["round"]
        done = {}
        for r in db.all("research_review_rounds", {"select": "target_round,status", "review_version": f"eq.{REVIEW_VERSION}",
                                                   "order": "target_round"}):
            done[r["target_round"]] = r["status"]
        targets = [only] if only else [t for t in range(START_ROUND, latest + 1) if all_rounds or done.get(t) != "final"]
        need = targets or [latest]
        d = load(db, list(range(min(need), max(need) + 1)) + [latest])
        codes = set()
        for t in targets:
            codes.update((d["results"].get(t) or {}).get("first_store_ids") or [])
            for e in (d["agent_rounds"].get(t) or {}).get("entries", []):
                codes.update(w[0] for w in e.get("w", []))
        names = store_names(db, codes)
        cards, rank = build_cards(d, agents_meta(db), hypothesis_counts(db))
        rows, statuses = [], Counter()
        for t in targets:
            if done.get(t) == "final" and not all_rounds:
                continue
            nums, ok_n = numbers_review(t, d)
            regions, stores, ok_rs = regions_stores_review(t, d, names)
            agents, spatial, corrections, ok_a = agents_review(t, d, names)
            signals = signals_review(t, d)
            status = "final" if (ok_n and ok_rs and ok_a) else "partial"
            rv = {"numbers": nums, "regions": regions, "stores": stores, "agents": agents, "spatial": spatial,
                  "corrections": corrections, "signals": signals}
            briefing = build_briefing(t, rv, rank if t == latest else None)
            rows.append(dict(rv, review_version=REVIEW_VERSION, target_round=t, status=status,
                             prediction_mode=agents.get("mode") if isinstance(agents, dict) else None,
                             briefing=briefing, updated_at=now_iso(),
                             data_status={"numbers": ok_n, "regions_stores": ok_rs, "agents": ok_a}))
            statuses[status] += 1
        if done and not all_rounds:
            # 확정(final) 회차는 다시 쓰지 않는다
            rows = [r for r in rows if done.get(r["target_round"]) != "final"]
        db.upsert("research_review_rounds", rows, "review_version,target_round")
        db.upsert("research_review_agent_cards", cards, "review_version,agent_id")
        stats = {"rounds_written": len(rows), "statuses": dict(statuses), "cards": len(cards), "latest": latest,
                 "agent_review_rounds": len(d["agent_rounds"]),
                 "missing_agent_review": [t for t in range(START_ROUND, latest + 1) if t not in d["agent_rounds"]][:50]}
        if run_id:
            db.patch("research_review_runs", {"id": f"eq.{run_id}"},
                     {"status": "success" if statuses.get("partial", 0) == 0 else "partial", "from_round": min(targets) if targets else None,
                      "to_round": max(targets) if targets else None, "stats": stats, "finished_at": now_iso()})
        return stats, rows, cards
    except Exception as e:
        if run_id:
            db.patch("research_review_runs", {"id": f"eq.{run_id}"}, {"status": "failed", "error": str(e)[:500], "finished_at": now_iso()})
        raise


def record_pipeline_step(db, stats, error):
    """서버 파이프라인 실행 기록(research_pipeline_runs)의 최신 목표 회차 행에 복기 단계를 덧붙인다"""
    if db.dry or not db.exists("research_pipeline_runs"):
        return
    target = (stats or {}).get("latest", 0) + 1 if stats else None
    q = {"select": "id,status,steps,outputs", "status": "in.(success,partial,failed)", "order": "started_at.desc", "limit": "1"}
    if target:
        q["target_round"] = f"eq.{target}"
    runs = db.get("research_pipeline_runs", q)
    if not runs:
        return
    run = runs[0]
    ok = error is None and stats and stats.get("statuses", {}).get("partial", 0) == 0
    why = error or (None if ok else f"미확정 회차 {stats.get('statuses', {}).get('partial', 0)}개 (입력 데이터 대기)")
    steps = [x for x in (run.get("steps") or []) if x.get("name") != "engine_review"]
    steps.append({"name": "engine_review", "ok": bool(ok), "at": now_iso(), **({"error": why} if why else {})})
    row = {"steps": steps, "outputs": dict(run.get("outputs") or {}, review={k: stats.get(k) for k in ("rounds_written", "statuses", "cards")} if stats else None)}
    if not ok and run["status"] == "success":
        row["status"] = "partial"
        row["error"] = f"복기 단계: {why}"
    db.patch("research_pipeline_runs", {"id": f"eq.{run['id']}"}, row)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="1000회부터 전 회차 다시 작성")
    ap.add_argument("--round", type=int, default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out", default=None)
    ap.add_argument("--record-run", action="store_true", help="서버 파이프라인 실행 기록에 복기 단계를 남긴다")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        print("SUPABASE_URL / SUPABASE_KEY 환경변수 필요"); sys.exit(1)
    db = Db(url, key, dry=a.dry_run)
    if not db.exists("research_review_rounds"):
        print("research_v10_review.sql 미적용 — 복기 생략"); return
    try:
        stats, rows, cards = run(db, all_rounds=a.all, only=a.round)
    except Exception as e:
        if a.record_run:
            record_pipeline_step(db, None, str(e)[:300])
        raise
    if a.record_run:
        record_pipeline_step(db, stats, None)
    print(json.dumps(stats, ensure_ascii=False))
    if rows:
        print("\n".join(rows[-1]["briefing"]["lines"]))
    if a.out:
        json.dump({"stats": stats, "rows": rows[-3:], "cards_sample": cards[:3]}, open(a.out, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
