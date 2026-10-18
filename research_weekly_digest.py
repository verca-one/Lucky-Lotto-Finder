"""
비서 주간 취합 (wd-1.0) — AI 전략기획부가 매일 낸 가설을 모아 수요일 엔진 실행 기준으로 묶고, 토요일 아침 최종 점검

  · 수요일 (--stage wed): 다음 회차(N) 엔진이 돌아 구매할 번호가 사전 등록되면 그 시점 스냅샷을 남긴다
      - 구매할 번호 ①②③ (장부 등록 세트), 적용 후보 가설(검증 통과·유지 + 번호 가설은 모의에서 확률 상승),
        이번 주 AI·비서 활동(가설 수·판정·아깝게 탈락한 가설)
  · 토요일 아침 (--stage sat): 같은 항목을 다시 계산해 수요일과 비교 → '변경점 없음' / '변경점 있음(무엇이)'
      - 구매할 번호는 사전 등록 장부에 잠겨 있어 자동으로 바뀌지 않는다. 새로 적용 후보가 생기면 '반영 여부 결정 필요'로 알린다.
저장: research_results (research_type weekly_digest, model_version wd-1.0, training_end_round=D, target_round=N) — 서버 전용
읽기: research_predictions · strategy_hypotheses · strategy_directions · lotto_winning_numbers (크롤링 테이블은 읽기만)

사용: python research_weekly_digest.py --stage wed|sat [--dry-run]
"""

import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone

import research_review_worker as R

VERSION = "wd-1.0"
AREAS = [("official", "official_final", "fr-1.0", "① 공식 최종 추천번호"),
         ("popularity", "popularity_pick", "pop-1.0", "② 비인기 추천조합"),
         ("purchase", "purchase_prediction", None, "③ 구매예측 번호")]
NUM_OUTCOMES = {"win_sum", "win_odd", "win_consec", "win_low", "win_high40"}


def ver_key(v):
    try:
        return tuple(int(x) for x in str(v).lstrip("rpvfdb-").split("."))
    except ValueError:
        return (0,)


def buy_sets(db, target):
    rows = db.get("research_predictions", {"select": "algorithm,version,sets,generated_at", "target_round": f"eq.{target}"})
    out = {}
    for key, algo, version, label in AREAS:
        rs = [r for r in rows if r["algorithm"] == algo and (version is None or r["version"] == version)]
        if rs:
            r = max(rs, key=lambda r: ver_key(r["version"]))
            out[key] = {"label": label, "version": r["version"], "generated_at": r["generated_at"],
                        "sets": [sorted(s) for s in r["sets"]]}
    return out


def qualifying(hyps):
    """적용 후보: 검증 통과·유지 · (번호 특징 가설은 모의에서 확률 상승까지)"""
    q = []
    for h in hyps:
        if h["status"] not in ("validated", "maintained"):
            continue
        sim = h.get("simulation") or {}
        if (h.get("spec") or {}).get("outcome") in NUM_OUTCOMES and not sim.get("raised"):
            continue
        q.append({"code": h["code"], "statement": h["statement"], "status": h["status"],
                  "kind": (h.get("spec") or {}).get("kind", "base"), "simulation": sim.get("note")})
    return sorted(q, key=lambda x: x["code"])


def activity(db, hyps, since_iso):
    dirs = db.get("strategy_directions", {"select": "source,model,created_at", "created_at": f"gte.{since_iso}"})
    week = [h for h in hyps if (h.get("created_at") or "") >= since_iso]
    near = sorted([h for h in hyps if h["status"] == "rejected" and (h.get("discovery") or {}).get("direction_ok")
                   and (h["discovery"].get("p") or 1) < 0.1], key=lambda h: h["discovery"]["p"])[:5]
    sims = [h for h in week if (h.get("simulation") or {}).get("status") == "done"]
    return {
        "since": since_iso,
        "directions": dict(Counter("Gemini" if "gemini" in (d.get("model") or "") else
                                   "Claude" if "claude" in (d.get("model") or "") else "관리자" for d in dirs)),
        "hypotheses": len(week),
        "by_kind": dict(Counter((h.get("spec") or {}).get("kind", "base") for h in week)),
        "by_status": dict(Counter(h["status"] for h in week)),
        "simulated": len(sims), "sim_raised": sum(1 for h in sims if h["simulation"].get("raised")),
        "near_misses": [{"code": h["code"], "statement": h["statement"], "p": h["discovery"]["p"]} for h in near],
    }


def snapshot(db, D, N, draw_date):
    try:
        hyps = db.get("strategy_hypotheses", {"select": "code,statement,status,spec,discovery,simulation,created_at"})
    except RuntimeError:
        hyps = []
    d = datetime.strptime(str(draw_date)[:10], "%Y-%m-%d")
    since = (datetime(d.year, d.month, d.day, tzinfo=timezone.utc) - timedelta(hours=9)).isoformat()  # 추첨일 0시 KST
    return {"at": datetime.now(timezone.utc).isoformat(), "buy": buy_sets(db, N), "qualifying": qualifying(hyps),
            "activity": activity(db, hyps, since)}


def compare(wed, sat):
    changes = []
    for key, _, _, label in AREAS:
        a, b = (wed["buy"].get(key) or {}).get("sets"), (sat["buy"].get(key) or {}).get("sets")
        if a != b:
            changes.append({"type": "sets", "area": label, "note": f"{label} 세트가 수요일과 다릅니다"})
    qa, qb = {x["code"]: x for x in wed["qualifying"]}, {x["code"]: x for x in sat["qualifying"]}
    for c in sorted(set(qb) - set(qa)):
        changes.append({"type": "new_hypothesis", "code": c, "note": f"새로 적용 후보가 된 가설: {qb[c]['statement']}"})
    for c in sorted(set(qa) - set(qb)):
        changes.append({"type": "dropped_hypothesis", "code": c, "note": f"적용 후보에서 빠진 가설: {qa[c]['statement']}"})
    if not changes:
        verdict = "변경점 없음 — 수요일에 정한 구매할 번호 그대로 구매하시면 됩니다"
    elif any(c["type"] == "sets" for c in changes):
        verdict = "변경점 있음 — 구매할 번호가 수요일과 다릅니다. 아래 내용을 확인하세요"
    else:
        verdict = ("변경점 있음 — 이번 주에 적용 후보 가설이 바뀌었습니다. 구매할 번호는 장부에 잠겨 그대로이며, "
                   "새 가설 반영 여부는 관리자가 결정합니다")
    return changes, verdict


def run(db, stage, dry=False):
    w = db.get("lotto_winning_numbers", {"select": "round,draw_date", "order": "round.desc", "limit": "1"})[0]
    D, N = w["round"], w["round"] + 1
    rows = db.get("research_results", {"select": "payload", "research_type": "eq.weekly_digest", "model_version": f"eq.{VERSION}",
                                       "training_end_round": f"eq.{D}", "target_round": f"eq.{N}"})
    payload = rows[0]["payload"] if rows else {"version": VERSION, "round": D, "next": N}
    if stage == "wed":
        if payload.get("wed"):
            print(f"{N}회 수요일 취합 이미 있음 — 건너뜀")
            return payload
        snap = snapshot(db, D, N, w["draw_date"])
        if not snap["buy"]:
            print(f"{N}회 구매할 번호가 아직 없음 (엔진 실행 전) — 수요일 취합 대기")
            return None
        payload["wed"] = snap
    else:
        snap = snapshot(db, D, N, w["draw_date"])
        if not payload.get("wed"):
            payload["sat"] = dict(snap, changes=[], verdict="수요일 취합 기록이 없어 비교할 수 없습니다 (엔진 실행 여부 확인 필요)")
        else:
            changes, verdict = compare(payload["wed"], snap)
            payload["sat"] = dict(snap, changes=changes, verdict=verdict)
        print(payload["sat"]["verdict"])
        for c in payload["sat"]["changes"]:
            print("  ·", c["note"])
    a = payload[stage]["activity"]
    print(f"{N}회 {stage}: 이번 주 가설 {a['hypotheses']}개 {a['by_status']} · 적용 후보 {len(payload[stage]['qualifying'])}개")
    if dry:
        print("드라이런 — 저장 안 함")
        return payload
    db.upsert("research_results", [{"research_type": "weekly_digest", "model_version": VERSION, "training_end_round": D,
                                    "target_round": N, "payload": payload}],
              "research_type,model_version,training_end_round,target_round")
    return payload


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", choices=["wed", "sat"], required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
    if not a.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("저장은 서버(GitHub Actions)에서만 합니다. 로컬은 --dry-run 만 허용")
    run(R.Db(url, key, dry=a.dry_run), a.stage, a.dry_run)


if __name__ == "__main__":
    main()
