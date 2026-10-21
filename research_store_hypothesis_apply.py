"""
판매점 가설 적용 (hs-apply-1.0) — 가설 공장이 검증 통과로 판정한 판매점 가설을 다음 회차 판매점 예측에 반영한다

  · 기준 = 지방장 모델(ag-1.1)이 낸 판매점별 다음 회차 1등 추정 확률 p_first (research_agent_store_scores, 읽기 전용)
  · 반영 가설 = strategy_hypotheses 중 판매점 가설(spec.level=store) · 상태 validated(검증 통과)·maintained(유지)
                · 기대 방향 '높다' 만 (낮다 가설은 순위를 내리는 용도라 이번 버전에서 제외)
  · 가설 배수 = 확인 구간(1001회~)의 '실제 1등 ÷ 지방장 기대' (mean_cond), 1~CAP 로 자름
  · 한 판매점에 여러 가설이 맞으면 가장 큰 배수 하나만 (겹치는 조건 중복 계산 방지)
  · 조건은 다음 회차(target) 직전까지의 정보로만 판정 (research_store_hypotheses.StoreData.cond)
  · 반영 확률 = p_first × 배수 → 전국 '적중 예측 높은 순' 순위 · 판매점별 배수 저장 (브리핑 ④ 선정에 사용)
  · 과거 모의(1001~1246회)에서 이 가설 가중은 시·군·구 TOP5 1등 적중을 바꾸지 못했다 → 그 결과도 함께 저장해 화면에 그대로 보인다
읽기: strategy_hypotheses · research_agent_store_scores · lottery_stores · winning_history (크롤링 테이블은 읽기만)
쓰기: research_results (research_type store_hypothesis_apply) — 서버(service_role)만
외부 사이트 접속 없음.

사용: python research_store_hypothesis_apply.py [--dry-run]
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

import research_review_worker as R
import research_store_hypotheses as H

VERSION = "hs-apply-1.0"
RESULT_TYPE = "store_hypothesis_apply"
AGENT_MODEL = "ag-1.1"
LIVE = ("validated", "maintained")
CAP = 2.0
TOP_N = 50


def factor_of(h):
    cf = h.get("confirm") or {}
    m = cf.get("mean_cond")
    if not isinstance(m, (int, float)) or m <= 1:
        return None
    return round(min(float(m), CAP), 4)


def short_label(spec):
    return " · ".join(H.STORE_CONDITIONS.get(c, c) for c in (spec.get("condition"), spec.get("condition2")) if c and c != "none")


def build(db, latest, target, sd=None):
    hyps = [h for h in db.all("strategy_hypotheses", {"select": "code,statement,status,spec,confirm,simulation",
                                                       "status": f"in.({','.join(LIVE)})", "order": "code"}, key="code")
            if (h.get("spec") or {}).get("level") == "store" and (h["spec"].get("expect") == "higher")]
    applied = []
    for h in hyps:
        f = factor_of(h)
        if f is None:
            continue
        sim = h.get("simulation") or {}
        applied.append({"code": h["code"], "label": short_label(h["spec"]), "statement": h["statement"],
                        "outcome": h["spec"].get("outcome"), "status": h["status"], "factor": f,
                        "sim": {k: sim.get(k) for k in ("status", "hits_hyp", "hits_base", "lift", "raised", "note")}})
    scores = db.all("research_agent_store_scores", {"select": "store_code,agent_id,agent_rank,p_first,score",
                                                    "model_version": f"eq.{AGENT_MODEL}", "target_round": f"eq.{target}",
                                                    "order": "store_code,agent_id"}, key="store_code")
    if not scores:
        return None, f"{target}회 지방장 판매점 점수 없음 ({AGENT_MODEL})"
    best = {}
    for r in scores:
        p = r.get("p_first")
        if p is None:
            continue
        if r["store_code"] not in best or p > best[r["store_code"]]["p_first"]:
            best[r["store_code"]] = r

    factors, hits_of = {}, {}
    if applied:
        sd = sd or H.StoreData(db, latest)
        idx = {c: i for i, c in enumerate(sd.codes)}
        for k, a in enumerate(applied):
            spec_conds = [c for c in a["code"].split(":", 1)[1].split("|", 1)[0].split("+")]
            m = sd.mask(spec_conds, target)
            n = 0
            for code, i in idx.items():
                if m[i]:
                    n += 1
                    hits_of.setdefault(code, []).append(k)
                    factors[code] = max(factors.get(code, 1.0), a["factor"])
            a["stores_now"] = n

    ranked = sorted(best.values(), key=lambda r: (-(r["p_first"] * factors.get(r["store_code"], 1.0)), r["store_code"]))
    top = ranked[:TOP_N]
    info = {s["dhlottery_code"]: s for s in db.all("lottery_stores", {
        "select": "dhlottery_code,store_name,address,region,first_count,second_count,latitude,longitude",
        "lottery_type": "eq.lotto", "dhlottery_code": f"in.({','.join(r['store_code'] for r in top)})",
        "order": "dhlottery_code"}, key="dhlottery_code")} if top else {}
    base_rank = {r["store_code"]: i + 1 for i, r in enumerate(sorted(best.values(), key=lambda r: (-r["p_first"], r["store_code"])))}
    rows = []
    for i, r in enumerate(top):
        c = r["store_code"]
        s = info.get(c, {})
        f = factors.get(c, 1.0)
        rows.append({"rank": i + 1, "base_rank": base_rank[c], "store_code": c, "agent_id": r["agent_id"],
                     "name": s.get("store_name") or c, "address": s.get("address") or "", "region": s.get("region") or "",
                     "lat": s.get("latitude"), "lng": s.get("longitude"),
                     "first": s.get("first_count") or 0, "second": s.get("second_count") or 0,
                     "p_first": round(float(r["p_first"]), 6), "factor": f,
                     "p_adj": round(min(float(r["p_first"]) * f, 0.99), 6), "hyps": hits_of.get(c, [])})
    payload = {"version": VERSION, "agent_model": AGENT_MODEL, "target_round": target, "training_end_round": latest,
               "hypotheses": applied, "ranking": rows,
               "factors": {c: {"f": f, "h": hits_of.get(c, [])} for c, f in sorted(factors.items())},
               "stores_scored": len(best),
               "rule": "지방장 1등 추정 확률 × 검증 통과 판매점 가설 배수(여러 개면 가장 큰 것 하나)"}
    return payload, None


def run(db, dry=False, sd=None):
    latest = db.get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})[0]["round"]
    target = latest + 1
    payload, why = build(db, latest, target, sd)
    if payload is None:
        print(f"판매점 가설 적용 생략 — {why}")
        return {"version": VERSION, "target": target, "saved": False, "reason": why}
    row = {"research_type": RESULT_TYPE, "model_version": VERSION, "training_end_round": latest, "target_round": target,
           "payload": payload, "created_at": datetime.now(timezone.utc).isoformat()}
    json.dumps(row, ensure_ascii=False)
    moved = sum(1 for r in payload["ranking"] if r["rank"] != r["base_rank"])
    print(f"{target}회 판매점 가설 적용: 반영 가설 {len(payload['hypotheses'])}개 · 배수 적용 판매점 {len(payload['factors'])}곳 · "
          f"상위 {len(payload['ranking'])}곳 중 순위 바뀐 곳 {moved}")
    for a in payload["hypotheses"]:
        print(f"  ×{a['factor']:.2f} {a['label']} → {a['outcome']} · 지금 해당 {a.get('stores_now', 0)}곳")
    for r in payload["ranking"][:10]:
        print(f"  {r['rank']:>2}. {r['name']} ({r['region']}) p {r['p_first'] * 100:.3f}% ×{r['factor']:.2f} → {r['p_adj'] * 100:.3f}%"
              f" (이력만 {r['base_rank']}위)")
    if dry:
        print("드라이런 — 저장 안 함")
    else:
        db.upsert("research_results", [row], "research_type,model_version,training_end_round,target_round")
    return {"version": VERSION, "target": target, "saved": not dry, "hypotheses": len(payload["hypotheses"]),
            "factored": len(payload["factors"])}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        print("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
        sys.exit(1)
    run(R.Db(url, key, dry=a.dry_run), a.dry_run)


if __name__ == "__main__":
    main()
