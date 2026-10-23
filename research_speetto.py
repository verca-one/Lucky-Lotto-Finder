"""
스피또 연구 (sp-1.0) — 게임별(스피또2000 · 1000 · 500) 1등 판매점 (브리핑 '스피또' 탭 · 일반 모드 복권연구 '스피또' 탭)

  · 기록: winning_history (lottery_type speedlotto_2000 · speedlotto_1000 · speedlotto_500, 회차 = 게임 차수)
  · 점수: 1등 기록을 차수 기준 반감기 20차수로 감쇠 누적 (2등은 0.3배, 스피또2000 만 2등 기록 있음)
  · 게임마다 상위 10곳 (시·군·구당 1곳) — 이름 · 주소 · 1·2등 횟수 · 최근 당첨 차수
  · 판매 현황 (research_speetto_status, 수집기 speetto_status_collector.py): 가장 최근 수집일의 판매 중 차수별
    출고율 · 남은 1·2·3등 → '남은 1등 지수' = (남은 1등 ÷ 전체 1등) ÷ (1 − 출고율) — 1보다 크면 팔린 만큼보다 1등이 많이 남음
    (출고율은 판매점으로 나간 비율이라 실제 판매와 다를 수 있다)
  · 데이터 검사: 차수마다 1등 판매점 목록이 거의 같으면(예전 크롤러 문제 — 회차 구분 없이 전체 목록 저장)
    결과를 만들지 않고 '데이터 정리 필요'로 둔다. 고친 크롤러가 다시 모으면 자동으로 공개된다.
  결과는 과거 기록 정리이며 한 장의 당첨 확률을 바꾸지 않는다.
읽기: winning_history · lottery_stores (크롤링 테이블은 읽기만)
쓰기: research_results (speetto_briefing) · research_public_extra (lottery = speetto) — 서버(service_role)만
외부 사이트 접속 없음.

사용: python research_speetto.py [--dry-run]
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone

import research_review_worker as R

VERSION = "sp-1.0"
RESULT_TYPE = "speetto_briefing"
GAMES = [("speedlotto_2000", "스피또2000"), ("speedlotto_1000", "스피또1000"), ("speedlotto_500", "스피또500")]
HALF_LIFE = 20.0
SECOND_W = 0.3
N_STORES = 10
SAME_LIMIT = 0.5

# ── 스피또 가설 어휘 (spec.level = speetto) — 판매 현황이 날마다 쌓이면 검정한다 ─────────
SPEETTO_CONDITIONS = {
    "sp_ship_high": "출고율 50% 이상인 차수",
    "sp_ship_low": "출고율 20% 이하인 차수",
    "sp_left_high": "1등이 80% 이상 남은 차수",
    "sp_new": "판매 시작 30일 이내 차수",
    "sp_old": "판매 시작 120일 지난 차수",
    "sp_game_500": "스피또500",
    "sp_game_1000": "스피또1000",
    "sp_game_2000": "스피또2000",
    "sp_index_high": "남은 1등 지수 1.2 이상",
}
SPEETTO_OUTCOMES = {
    "sp_rnk1_out": "다음 7일 안에 나가는 1등 수",
    "sp_ship_speed": "다음 7일 출고율 상승폭",
    "sp_rnk2_out": "다음 7일 안에 나가는 2등 수",
}


def speetto_statement(spec):
    conds = [c for c in (spec.get("condition"), spec.get("condition2")) if c and c != "none"]
    more = "많다" if spec["expect"] == "higher" else "적다"
    return f"[스피또] {' · '.join(SPEETTO_CONDITIONS[c] for c in conds)}는 {SPEETTO_OUTCOMES[spec['outcome']]}가 {more}"


def speetto_code(spec):
    conds = sorted(c for c in (spec.get("condition"), spec.get("condition2")) if c and c != "none")
    return f"speetto:{'+'.join(conds)}|{spec['outcome']}|{spec['expect']}"     # 연속 차수의 1등 판매점 목록이 이 비율 넘게 '완전히 같으면' 잘못된 데이터


def game_block(db, lt, label):
    rows = db.all("winning_history", {"select": "round,dhlottery_code,prize_tier", "lottery_type": f"eq.{lt}",
                                      "order": "round,dhlottery_code"}, key="round")
    if not rows:
        return {"game": lt, "label": label, "status": "no_data", "stores": []}
    firsts = defaultdict(set)
    ev = defaultdict(list)
    for r in rows:
        c = r["dhlottery_code"]
        if not c or c in ("00000000",):
            continue
        ev[c].append((r["round"], r["prize_tier"]))
        if r["prize_tier"] == "first":
            firsts[r["round"]].add(c)
    eds = sorted(firsts)
    pairs = list(zip(eds, eds[1:]))
    same = sum(1 for a, b in pairs if firsts[a] and firsts[a] == firsts[b])
    same_ratio = same / len(pairs) if pairs else 0.0
    latest = max(eds) if eds else max(r["round"] for r in rows)
    base = {"game": lt, "label": label, "editions": len(eds), "latest_edition": latest,
            "same_ratio": round(same_ratio, 3), "records": len(rows)}
    if same_ratio > SAME_LIMIT:
        return dict(base, status="data_invalid", stores=[],
                    note=f"차수마다 1등 판매점 목록이 같은 비율 {same_ratio:.0%} — 예전 크롤러 기록, 정리 후 다시 수집 필요")
    g = 0.5 ** (1 / HALF_LIFE)
    score = {c: sum(g ** (latest - r) * (1 if t == "first" else SECOND_W) for r, t in e) for c, e in ev.items()}
    codes = sorted(score, key=lambda c: -score[c])[:200]
    info = {}
    for i in range(0, len(codes), 150):
        for s in db.get("lottery_stores", {"select": "dhlottery_code,store_name,address,region",
                                           "lottery_type": f"eq.{lt}", "dhlottery_code": f"in.({','.join(codes[i:i + 150])})"}):
            info[s["dhlottery_code"]] = s
    out, used = [], set()
    for c in codes:
        if len(out) >= N_STORES:
            break
        s = info.get(c, {})
        addr = s.get("address") or ""
        a = addr.split()
        reg = f"{a[0]} {a[1]}" if len(a) >= 2 else (s.get("region") or "")
        if reg and reg != "미상" and reg in used:
            continue
        used.add(reg)
        e = ev[c]
        out.append({"store_code": c, "name": s.get("store_name") or c, "address": addr, "region": reg,
                    "first": sum(t == "first" for _, t in e), "second": sum(t == "second" for _, t in e),
                    "last_edition": max(r for r, _ in e), "score": round(score[c], 4)})
    return dict(base, status="ok", stores=out,
                rule=f"1등 기록 반감기 {HALF_LIFE:.0f}차수 감쇠 누적 (2등 {SECOND_W}배) · 시·군·구당 1곳")


def status_block(db):
    try:
        last = db.get("research_speetto_status", {"select": "snap_date", "order": "snap_date.desc", "limit": "1"})
    except RuntimeError as e:
        return {"status": "no_table", "note": f"research_v17_speetto_status.sql 실행 필요 ({str(e)[:80]})", "games": []}
    if not last:
        return {"status": "no_data", "note": "아직 수집 전 (매일 10시)", "games": []}
    snap = last[0]["snap_date"]
    rows = db.get("research_speetto_status", {"select": "game,edition,price,sale_start,sale_end,ship_rate,rnk1_total,rnk1_left,"
                                                        "rnk2_total,rnk2_left,rnk3_total,rnk3_left,prize1,prize2,prize3,odds",
                                              "snap_date": f"eq.{snap}", "order": "game,edition"})
    out = []
    for r in rows:
        ship = (r.get("ship_rate") or 0) / 100
        t1, l1 = r.get("rnk1_total") or 0, r.get("rnk1_left")
        near_end = ship >= 0.95   # 출고 거의 끝 — 남은 1등은 판매점 재고이거나 팔렸지만 아직 안 찾아간 표일 수 있어 지수를 쓰지 않는다
        idx = round((l1 / t1) / (1 - ship), 3) if t1 and l1 is not None and not near_end else None
        out.append(dict(r, index=idx, near_end=near_end))
    out.sort(key=lambda r: (r["near_end"], -(r["index"] or 0)))
    return {"status": "ok", "snap_date": snap, "editions": out,
            "rule": "남은 1등 지수 = (남은 1등 ÷ 전체 1등) ÷ (1 − 출고율) · 1보다 크면 출고된 만큼보다 1등이 많이 남음"}


def public_summary(p):
    return {"lottery": "speetto", "generated_at": p["generated_at"],
            "games": [{"game": g["game"], "label": g["label"], "status": g["status"], "latest_edition": g.get("latest_edition"),
                       "stores": [{k: s[k] for k in ("store_code", "name", "region", "address", "first", "second", "last_edition")}
                                  for s in g.get("stores", [])]} for g in p["games"]],
            "status": p.get("status"),
            "disclaimer": "스피또 1·2등이 나온 판매점 기록과 동행복권 판매 현황을 정리한 참고용입니다. 어느 판매점에서 사도 한 장의 당첨 확률은 같습니다."}


def run(db, dry=False):
    now = datetime.now(timezone.utc)
    p = {"version": VERSION, "generated_at": now.isoformat(), "games": [game_block(db, lt, label) for lt, label in GAMES],
         "status": status_block(db)}
    st = p["status"]
    print(f"판매 현황: {st['status']} {st.get('snap_date') or st.get('note') or ''}")
    for e in st.get("editions", []):
        print(f"   {e['game']} {e['edition']}차 출고 {e['ship_rate']}% · 1등 {e['rnk1_left']}/{e['rnk1_total']} · 지수 {e['index']}")
    for g in p["games"]:
        print(f"{g['label']}: {g['status']} · 차수 {g.get('editions', 0)}개 (최신 {g.get('latest_edition')}) · "
              f"같은 목록 비율 {g.get('same_ratio')} · 판매점 {len(g['stores'])}곳")
        for s in g["stores"][:5]:
            print(f"   {s['name']} ({s['region']}) 1등 {s['first']} · 2등 {s['second']} · 최근 {s['last_edition']}차")
    ok = any(g["status"] == "ok" for g in p["games"]) or p["status"]["status"] == "ok"
    tag = int(now.strftime("%Y%m%d"))        # 스피또는 회차가 게임마다 달라 날짜를 키로 쓴다
    row = {"research_type": RESULT_TYPE, "model_version": VERSION, "training_end_round": tag, "target_round": tag, "payload": p}
    pub = {"lottery": "speetto", "target_round": tag, "payload": public_summary(p), "is_public_approved": ok,
           "updated_at": now.isoformat()}
    json.dumps([row, pub], ensure_ascii=False)
    if dry:
        print("드라이런 — 저장 안 함")
        return p
    db.upsert("research_results", [row], "research_type,model_version,training_end_round,target_round")
    db.upsert("research_public_extra", [pub], "lottery,target_round")
    print(f"저장 · 공개 {'함' if ok else '안 함 (데이터 정리 필요)'}")
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다")
    if not a.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("저장은 서버(GitHub Actions)에서만 합니다. 로컬은 --dry-run 만 허용")
    run(R.Db(url, key, dry=a.dry_run), a.dry_run)


if __name__ == "__main__":
    main()
