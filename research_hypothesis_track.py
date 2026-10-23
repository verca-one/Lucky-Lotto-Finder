"""
가설 트랙 (ht-1.0) — AI 전략기획부(제미나이)가 낸 가설을 검증 통과를 기다리지 않고 바로 실전에 쓰는 '상상 예측' 부서

  역할 (다른 엔진·기관의 자리는 그대로 — 이 부서는 그 결과를 읽어 쓰기만 한다)
    · 가설 출처: strategy_hypotheses 중 AI(제미나이) 방향의 가설 전부 (기각·폐기 포함, 데이터 미확보 'unsupported' 만 제외)
    · 기준 데이터: 최근 200회차 — 가설이 말하는 방향이 최근 200회에서도 맞으면 그만큼 힘(가중)을 준다
    · 실전 성적: 이 트랙이 쓴 가설이 실제 회차에서 방향을 맞혔는지 누적 → 맞힌 가설은 커지고 틀린 가설은 작아진다
      성적 배수 m = (맞힘+1)/(사용+2) × 2  (처음 1, 다 맞히면 2 쪽, 다 틀리면 0 쪽)
  번호 5세트 (도구: 인기도 엔진 pop-1.0 의 점수기 — 인기도 엔진 자체는 그대로)
    · 1~4등 당첨자 쏠림(R1~R4) 가설: 쏠림이 '높다' = 당첨조합이 많이 팔린(인기) 조합 → 인기 쪽, '낮다' → 비인기 쪽
    · 당첨번호 특징 가설(합·홀수·연속·1~22·40 이상): 그 특징이 최근 200회 중앙값보다 높은/낮은 쪽 조합
    · 이번 회차에 조건이 참인 가설만 쓴다. 판매액 조건(sales_*)은 추첨 뒤에만 알 수 있어 쓰지 않는다
    · 조합 점수 = 인기 방향 맞춤 + 특징 방향 맞춤 (가설 힘 가중) → 상위에서 서로 3개 이상 겹치지 않게 5세트
  판매점 5곳 (도구: 지방장 모델 ag-1.1 의 1등 추정 확률)
    · 판매점 가설: 최근 200회 '실제 1등 vs 지방장 기대'가 가설 방향과 맞는 것만, 힘 = (실제−기대)/√기대 × 성적 배수
    · 1등 판매점 수도권 비율 가설(이번 회차 조건 참 · 높다): 수도권 판매점 조건으로 함께 경쟁
    · 힘 순서대로 가설마다 한 곳 — 조건이 같은 가설은 하나로, 그 조건 판매점 중 지방장 확률 최고
      (인터넷 판매 제외 · 이미 고른 곳·같은 시·군·구 제외 · 이력 전국 상위 20곳은 기존 트랙 몫이라 제외)
      → 5곳. 가게마다 '어느 가설 때문인지'가 붙는다
    · 표시 확률 = 지방장 확률 × 그 가설의 최근 200회 배수(성적 배수만큼 거듭제곱)
  공개·등록 규칙
    · 다음 회차 예측 실행 시점 규칙(research_release: 수요일 0시 또는 수동 추천) 이후 · 판매 마감(토 20:00 KST) 전만
    · 번호는 사전 등록 장부(research_predictions, hypothesis_track · ht-1.0)에 올린다 — 등록 후 변경 불가
    · 등록되면 그 회차 결과는 고정 (다시 계산하지 않음)
  이것은 검증된 확률이 아니라 가설 기반 예측이다. 복권 한 장의 1등 확률(1/8,145,060)은 바뀌지 않는다.
읽기: strategy_* · research_prize_stats · lotto_winning_numbers · winning_history · lottery_stores · research_agent_store_scores
      (크롤링 테이블은 읽기만)
쓰기: research_results (hypothesis_track) · research_predictions (hypothesis_track) — 서버(service_role)만
외부 사이트 접속 없음.

사용: python research_hypothesis_track.py [--dry-run]
"""

import argparse
import json
import math
import os
import sys
from datetime import date, datetime, timedelta, timezone

import numpy as np
import requests

import research_hypothesis_factory as F
import research_popularity as P
import research_review_worker as R
import research_store_hypotheses as H
from research_region_worker import Db as PDb

VERSION = "ht-1.0"
FINAL_VERSION = "ht-1.0-sat"   # 토요일 08:00 최종 점검 뒤 재선정 (수요일 선정본과 따로 등록)
ALGO = "hypothesis_track"
RESULT_TYPE = "hypothesis_track"
AGENT_MODEL = "ag-1.1"
WINDOW = 200
MIN_COND = 5
W_CAP = 3.0
POP_OUT = {"R1": 1.0, "R2": 0.8, "R3": 0.6, "R4": 0.5}
NUM_OUT = ("win_sum", "win_odd", "win_consec", "win_low", "win_high40")
UNKNOWN_BEFORE_DRAW = ("sales_surge", "sales_drop")
N_SETS = 5
N_STORES = 5
MAX_OVERLAP = 2
FACTOR_CLIP = (0.5, 3.0)
TOTAL_CLIP = (0.3, 5.0)
HISTORY_TOP = 20     # 이력(지방장 확률) 전국 상위 20곳은 기존 트랙(④) 몫 — 가설 트랙은 그 밖에서 고른다


def py(x):
    if isinstance(x, dict):
        return {k: py(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [py(v) for v in x]
    if isinstance(x, np.bool_):
        return bool(x)
    if isinstance(x, np.integer):
        return int(x)
    if isinstance(x, np.floating):
        return float(x)
    return x


def ai_hypotheses(db):
    dirs = {d["id"]: d for d in db.all("strategy_directions", {"select": "id,source,model,title", "order": "id"}, key="id")}
    out = []
    for h in db.all("strategy_hypotheses", {"select": "id,code,statement,status,spec,direction_id", "order": "code"}, key="code"):
        d = dirs.get(h.get("direction_id"))
        if not d or d.get("source") != "ai" or h["status"] == "unsupported" or not h.get("spec"):
            continue
        out.append(dict(h, model=d.get("model")))
    return out


def target_conditions(latest_row, latest_ps, target):
    """다음 회차(추첨 전)에 알 수 있는 조건만. 판매액 조건은 None(모름)."""
    d = date.fromisoformat(str(latest_ps["draw_date"])[:10]) + timedelta(days=7)
    ns = latest_row["nums"]
    r1 = latest_ps.get("rank1_winners") or 0
    return {
        "round_odd": target % 2 == 1, "day_odd": d.day % 2 == 1, "early_month": d.day <= 10,
        "first_half": d.month <= 6, "summer": d.month in (6, 7, 8), "winter": d.month in (12, 1, 2),
        "prev_rank1_many": r1 >= 15, "prev_rank1_few": r1 <= 5,
        "sales_surge": None, "sales_drop": None,
        "prev_sum_high": sum(ns) >= 160,
        "prev_consec": any(b - a == 1 for a, b in zip(ns, ns[1:])),
        "prev_low_heavy": sum(n <= 12 for n in ns) >= 3,
    }, d


def recent_stat(rows, conds, out, expect):
    """최근 WINDOW 회차: 조건 회차 vs 나머지 평균 차이 z (가설 방향 기준 +)"""
    c, o = [], []
    for r in rows:
        v = r["out"].get(out)
        if v is None:
            continue
        (c if all(r["cond"].get(k) for k in conds) else o).append(float(v))
    if len(c) < MIN_COND or len(o) < MIN_COND:
        return {"n_cond": len(c), "n_other": len(o), "z": None, "w": 0.0}
    mc, mo = float(np.mean(c)), float(np.mean(o))
    se = math.sqrt(np.var(c, ddof=1) / len(c) + np.var(o, ddof=1) / len(o)) or 1e-9
    z = (mc - mo) / se * (1 if expect == "higher" else -1)
    return {"n_cond": len(c), "n_other": len(o), "mean_cond": round(mc, 4), "mean_other": round(mo, 4),
            "z": round(z, 3), "w": round(float(np.clip(z, 0, W_CAP)), 3)}


def record_m(rec, code):
    p, h = rec.get(code, (0, 0))
    return (h + 1) / (p + 2) * 2


def score_previous(prev_payload, rows, sd, latest):
    """직전 회차 트랙이 쓴 가설이 실제로 방향을 맞혔나 → 누적 성적 갱신"""
    rec = {k: tuple(v) for k, v in (prev_payload.get("record") or {}).items()}
    if prev_payload.get("scored") or prev_payload.get("target_round") != latest:
        return rec, []
    row = next((r for r in rows if r["round"] == latest), None)
    scored = []
    for u in prev_payload.get("used", []):
        hit = None
        if u["family"] in ("pop", "num") and row is not None:
            v = row["out"].get(u["outcome"])
            med = u.get("median")
            if v is not None and med is not None and v != med:
                hit = (v > med) == (u["expect"] == "higher")
        elif u["family"] == "store" and sd is not None and u.get("conds"):
            y = sd.first[sd.ti(latest)].astype(bool)
            if y.any():
                b = sd.baseline(latest)
                m = sd.mask(u["conds"], latest)
                O, E = int(y[m].sum()), float(y.sum() * b[m].sum() / b.sum())
                if O != E:
                    hit = (O > E) == (u["expect"] == "higher")
        elif u["family"] == "capital" and row is not None:
            v = row["out"].get("first_capital_share")
            if v is not None and u.get("median") is not None and v != u["median"]:
                hit = (v > u["median"]) == (u["expect"] == "higher")
        if hit is None:
            continue
        p, h = rec.get(u["code"], (0, 0))
        rec[u["code"]] = (p + 1, h + int(hit))
        scored.append({"code": u["code"], "hit": hit})
    return rec, scored


def number_sets(sc, used_pop, used_num, past, rows_recent, prev):
    """인기도 점수기 표본에서 가설 방향 점수가 높은 조합 5세트"""
    D = sum(u["w_eff"] * (1 if u["expect"] == "higher" else -1) * POP_OUT[u["outcome"]] for u in used_pop)
    target_pct = 50 + 45 * math.tanh(D / 2)
    ranks = np.argsort(np.argsort(sc.sp)) / len(sc.sp) * 100
    inside = np.all((sc.sx >= sc.lo) & (sc.sx <= sc.hi), axis=1)
    feat = {}
    if used_num:
        S = np.array(sc.sample)
        feat = {"win_sum": S.sum(1), "win_odd": (S % 2).sum(1), "win_consec": (np.diff(S, axis=1) == 1).sum(1),
                "win_low": (S <= 22).sum(1), "win_high40": (S >= 40).sum(1)}
    score = -np.abs(ranks - target_pct) / 50 * (1.0 + abs(D))
    for u in used_num:
        side = np.sign(feat[u["outcome"]] - u["median"]) * (1 if u["expect"] == "higher" else -1)
        score = score + u["w_eff"] * side
    order = [i for i in np.argsort(-score) if inside[i]]
    out, seen = [], set()
    for i in order:
        c = tuple(sc.sample[i])
        if c in seen or c in past:
            continue
        seen.add(c)
        if all(len(set(c) & set(o)) <= MAX_OVERLAP for o in out):
            out.append(list(c))
        if len(out) == N_SETS:
            break
    return out, round(target_pct, 1), round(D, 3)


def store_picks(db, sd, latest, target, store_used, capital_used):
    """가설마다 한 곳: 최근 200회 힘(실제-기대)/√기대 × 성적 배수 순으로, 조건이 같은 가설은 하나로 묶고
    그 가설 조건에 맞는 판매점 중 지방장 1등 추정 확률이 가장 높은 곳 (이미 고른 곳·같은 시·군·구 제외)."""
    scores = db.all("research_agent_store_scores", {"select": "store_code,agent_id,p_first", "model_version": f"eq.{AGENT_MODEL}",
                                                    "target_round": f"eq.{target}", "order": "store_code,agent_id"}, key="store_code")
    if not scores:
        return [], f"{target}회 지방장 판매점 점수 없음"
    idx = {c: i for i, c in enumerate(sd.codes)}
    p = np.zeros(len(sd.codes))
    for r in scores:
        i = idx.get(r["store_code"])
        if i is not None and r.get("p_first") is not None and r.get("agent_id") != "internet":
            p[i] = max(p[i], float(r["p_first"]))
    cands = []
    for k, u in enumerate(store_used):
        rc = u["recent"]
        E = rc.get("expected_cond") or 0
        O = rc.get("n_cond") or 0
        strength = ((O - E) / math.sqrt(E) if E > 0 else 0) * u["m"]
        if u["expect"] == "lower":
            continue   # 낮다 가설은 고르는 데 쓰지 않음
        cands.append((strength, k, frozenset(u["conds"]), sd.mask(u["conds"], target), u["factor"] ** u["m"]))
    for j, u in enumerate(capital_used):
        if u["expect"] == "higher":
            cands.append((u["w_eff"], len(store_used) + j, frozenset(["capital"]), sd.capital.copy(), u["factor"] ** u["m"]))
    cands.sort(key=lambda c: -c[0])
    reserved = set(np.argsort(-p)[:HISTORY_TOP].tolist())
    out, regions, chosen, seen = [], set(), set(), set()
    for strength, k, cs, m, fac in cands:
        if len(out) >= N_STORES:
            break
        if cs in seen:
            continue
        seen.add(cs)
        ok = m & (p > 0)
        order = [i for i in np.argsort(-p) if ok[i] and i not in chosen and i not in reserved
                 and int(sd.region_of[i]) not in regions]
        if not order:
            continue
        i = order[0]
        chosen.add(i)
        regions.add(int(sd.region_of[i]))
        f = float(np.clip(fac, *TOTAL_CLIP))
        out.append({"store_code": sd.codes[i], "p_first": round(float(p[i]), 6), "factor": round(f, 4),
                    "p_adj": round(float(min(p[i] * f, 0.99)), 6), "hyps": [k], "strength": round(float(strength), 3),
                    "cond_stores": int(m.sum())})
    if out:
        info = {x["dhlottery_code"]: x for x in db.get("lottery_stores", {
            "select": "dhlottery_code,store_name,address,region,first_count,second_count,latitude,longitude",
            "lottery_type": "eq.lotto", "dhlottery_code": f"in.({','.join(o['store_code'] for o in out)})"})}
        for o in out:
            x = info.get(o["store_code"], {})
            o.update(name=x.get("store_name") or o["store_code"], address=x.get("address") or "", region=x.get("region") or "",
                     first=x.get("first_count") or 0, second=x.get("second_count") or 0,
                     lat=x.get("latitude"), lng=x.get("longitude"))
    return out, None


def run(url, key, dry=False, final=False):
    ver = FINAL_VERSION if final else VERSION
    db = R.Db(url, key, dry=dry)
    base = url.rstrip("/") + "/rest/v1/"

    def get(t, params):
        r = requests.get(base + t, params=params, headers=db.h, timeout=60)
        r.raise_for_status()
        return r.json()

    w = db.get("lotto_winning_numbers", {"select": "round,draw_date", "order": "round.desc", "limit": "1"})[0]
    latest, target = w["round"], w["round"] + 1
    now = datetime.now(timezone.utc)
    deadline = P.sales_deadline(w["draw_date"], latest)

    mine = db.get("research_results", {"select": "target_round,payload", "research_type": f"eq.{RESULT_TYPE}",
                                       "model_version": f"eq.{VERSION}", "order": "target_round.desc", "limit": "2"})
    cur = next((x for x in mine if x["target_round"] == target), None)
    if final:
        fin = db.get("research_results", {"select": "target_round,payload", "research_type": f"eq.{RESULT_TYPE}",
                                          "model_version": f"eq.{ver}", "target_round": f"eq.{target}", "limit": "1"})
        if fin and (fin[0]["payload"] or {}).get("status") == "registered":
            print(f"{target}회 토요일 최종본 이미 등록 — 고정")
            return fin[0]["payload"]
    elif cur and (cur["payload"] or {}).get("status") == "registered":
        print(f"{target}회 가설 트랙 이미 등록 — 고정 (다시 계산하지 않음)")
        return cur["payload"]
    from research_release import prediction_allowed
    ok, reason, _ = prediction_allowed(get, target, w["draw_date"], latest)
    if not ok:
        print(f"{target}회 가설 트랙 {reason} — 계산·등록하지 않음")
        return None
    if now >= deadline:
        print(f"{target}회 판매 마감 지남 — 등록하지 않음")
        return None

    rows = F.load_rounds(db)
    if rows[-1]["round"] != latest:
        print(f"{target}회 대기 — {latest}회 당첨자 수 미수집 (저장된 최신 {rows[-1]['round']}회)")
        return None
    recent = rows[-WINDOW:]
    ps = db.get("research_prize_stats", {"select": "round,draw_date,rank1_winners", "official": "eq.true",
                                         "round": f"eq.{latest}", "limit": "1"})[0]
    tcond, tdate = target_conditions(rows[-1], ps, target)

    hyps = ai_hypotheses(db)
    need_store = any((h["spec"] or {}).get("level") == "store" for h in hyps)
    sd = H.StoreData(db, latest) if need_store else None
    prev = next((x for x in mine if x["target_round"] == latest), None)
    rec, scored_prev = score_previous(prev["payload"] if prev else {}, rows, sd, latest)
    if prev and scored_prev and not dry and not final and not prev["payload"].get("scored"):
        db.patch("research_results", {"research_type": f"eq.{RESULT_TYPE}", "model_version": f"eq.{VERSION}",
                                      "target_round": f"eq.{latest}"},
                 {"payload": py(dict(prev["payload"], scored=True, scored_hits=scored_prev))})

    used_pop, used_num, store_used, capital_used, skipped = [], [], [], [], {"condition_false": 0, "unknown": 0, "weak": 0, "other": 0}
    lo = latest - WINDOW + 1
    for h in hyps:
        spec = h["spec"]
        conds, out, e = F.conds_of(spec), spec.get("outcome"), spec.get("expect")
        base = {"code": h["code"], "statement": h["statement"], "status": h["status"], "outcome": out, "expect": e,
                "conds": conds, "kind": spec.get("kind") or "base"}
        if spec.get("level") == "store":
            t = H.store_test(sd, conds, out, e, lo, latest)
            rc = t.get("mean_cond")
            agree = rc is not None and ((rc > 1) if e == "higher" else (rc < 1))
            if t.get("status") == "small" or not agree:
                skipped["weak"] += 1
                continue
            m = record_m(rec, h["code"])
            store_used.append(dict(base, family="store", factor=float(np.clip(rc, *FACTOR_CLIP)), m=round(m, 3),
                                   recent={k: t.get(k) for k in ("n_cond", "expected_cond", "mean_cond", "p")},
                                   now_stores=int(sd.mask(conds, target).sum())))
            continue
        if any(tcond.get(c) is None for c in conds):
            skipped["unknown"] += 1
            continue
        if not all(tcond.get(c) for c in conds):
            skipped["condition_false"] += 1
            continue
        if out not in POP_OUT and out not in NUM_OUT and out != "first_capital_share":
            skipped["other"] += 1
            continue
        st = recent_stat(recent, conds, out, e)
        if st["w"] <= 0:
            skipped["weak"] += 1
            continue
        m = record_m(rec, h["code"])
        vals = [float(r["out"][out]) for r in recent if r["out"].get(out) is not None]
        med = float(np.median(vals)) if vals else None
        u = dict(base, recent=st, w=st["w"], m=round(m, 3), w_eff=round(st["w"] * m, 3), median=med)
        if out in POP_OUT:
            used_pop.append(dict(u, family="pop"))
        elif out in NUM_OUT:
            used_num.append(dict(u, family="num"))
        else:
            allm = float(np.mean(vals)) if vals else 0
            fac = (st["mean_cond"] / allm) if allm > 0 else 1.0
            capital_used.append(dict(u, family="capital", factor=float(np.clip(fac, *FACTOR_CLIP))))

    data = P.load_rounds(PDb(url, key))
    pw = [rows[-1]["nums"]][0]
    sc = P.Scorer(data, pw, seed=P.SEED + target + 7)
    wins = db.all("lotto_winning_numbers", {"select": "round,num1,num2,num3,num4,num5,num6", "order": "round"}, key="round")
    past = {tuple(sorted(x[f"num{i}"] for i in range(1, 7))) for x in wins}
    sets, target_pct, D = number_sets(sc, used_pop, used_num, past, recent, pw)
    stores, store_err = store_picks(db, sd, latest, target, store_used, capital_used) if sd is not None else ([], "판매점 가설 없음")

    status = "pending"
    if not dry and sets:
        db.upsert("research_predictions", [{
            "algorithm": ALGO, "version": ver, "target_round": target, "data_end_round": latest,
            "sets": sets, "generated_at": now.isoformat(), "deadline_at": deadline.isoformat(),
            "pre_deadline": True, "locked": True, "status": "pending"}], "algorithm,version,target_round", ignore=True)
        reg = db.get("research_predictions", {"select": "sets", "algorithm": f"eq.{ALGO}", "version": f"eq.{ver}",
                                              "target_round": f"eq.{target}"})
        if reg:
            sets, status = reg[0]["sets"], "registered"
    payload = py({
        "version": ver, "final": final, "target_round": target, "training_end_round": latest, "window": [lo, latest],
        "wednesday": ({"sets": [s.get("set") for s in (cur["payload"] or {}).get("sets", [])],
                       "stores": [o.get("store_code") for o in (cur["payload"] or {}).get("stores", [])]} if final and cur else None),
        "draw_date": tdate.isoformat(), "conditions": tcond, "status": status,
        "sets": [sc.score(s) for s in sets], "popularity_target_pct": target_pct, "popularity_drive": D,
        "stores": stores, "store_error": store_err,
        "used": used_pop + used_num + store_used + capital_used,
        "skipped": skipped, "hypotheses_total": len(hyps),
        "record": {k: list(v) for k, v in rec.items()}, "scored_previous": scored_prev,
        "rule": "제미나이 가설 · 최근 200회 방향 일치 가중 × 실전 성적 배수 — 검증 전 가설 기반 예측",
        "deadline_at": deadline.isoformat(), "generated_at": now.isoformat(),
    })
    print(f"{target}회 가설 트랙 ({status}) · 가설 {len(hyps)}개 중 사용 번호 {len(used_pop) + len(used_num)} · "
          f"판매점 {len(store_used)} · 수도권 {len(capital_used)} · 제외 {skipped}")
    print(f"  인기 방향 D={D} → 목표 인기 백분위 {target_pct}")
    for s in payload["sets"]:
        print(f"  번호 {s['set']} 인기 {s['popularity_pct']}%")
    for u in payload["used"][:12]:
        print(f"  [{u['family']}] {u['statement']} · 최근200 {u.get('recent')} · 성적 ×{u['m']}")
    for o in stores:
        print(f"  명당 {o.get('name')} ({o.get('region')}) {o['p_first'] * 100:.3f}% ×{o['factor']:.2f} → {o['p_adj'] * 100:.3f}%")
    if scored_prev:
        print(f"  직전 {latest}회 성적: {sum(x['hit'] for x in scored_prev)}/{len(scored_prev)} 방향 맞힘")
    row = {"research_type": RESULT_TYPE, "model_version": ver, "training_end_round": latest, "target_round": target,
           "payload": payload}
    json.dumps(row, ensure_ascii=False)
    if dry:
        print("드라이런 — 저장·등록 안 함")
    else:
        db.upsert("research_results", [row], "research_type,model_version,training_end_round,target_round")
    return payload


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--final", action="store_true", help="토요일 08:00 최종 점검 뒤 재선정 (ht-1.0-sat)")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다")
    if not a.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("저장·등록은 서버(GitHub Actions)에서만 합니다. 로컬은 --dry-run 만 허용")
    run(url, key, a.dry_run, a.final)


if __name__ == "__main__":
    main()
