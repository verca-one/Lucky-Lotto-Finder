"""
연금 · 스피또 지방장 (ax-1.0) — 로또 지방장(ag-1.1)과 같은 시·군·구 지방장이 연금복권 · 스피또를 따로 연구한다

  지방장 = 시·군·구 (주소 앞 두 마디, 시·도 이름 통일). 지방장마다 복권 종류별로 따로:
  · 연금: 그 지역 판매점의 연금 1·2등 기록을 반감기 100회로 감쇠 누적 → 다음 회차 TOP5
      성적: 최근 100회를 회차마다 '그 직전까지 기록'으로 다시 뽑아, 실제 1·2등이 TOP5 에 들었는지 (지역 1·2등 중 몇 개)
  · 스피또: 게임(500 · 1000 · 2000)별 1·2등 기록을 차수 기준 반감기 20차수로 감쇠 누적 (게임마다 최신 차수 기준) → TOP5
      성적: 게임마다 최근 10차수를 같은 방식으로 다시 뽑아 확인
      예전 크롤러 기록(차수마다 같은 목록)이면 '데이터 정리 필요'로 내지 않는다
  인터넷 판매는 지방장에서 뺀다. 결과는 과거 기록 정리이며 한 장의 당첨 확률을 바꾸지 않는다.
읽기: winning_history · lottery_stores (크롤링 테이블은 읽기만)
쓰기: research_results (agent_extra · ax-1.0) — 서버(service_role)만
외부 사이트 접속 없음.

사용: python research_agent_extra.py [--dry-run]
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

import research_review_worker as R

VERSION = "ax-1.0"
RESULT_TYPE = "agent_extra"
TOP = 5
PENSION_HL = 100.0
SPEETTO_HL = 20.0
PENSION_BACK = 100
SPEETTO_BACK = 10
ONLINE = {"00000000", "001160"}
SPEETTO_GAMES = [("speedlotto_2000", "스피또2000"), ("speedlotto_1000", "스피또1000"), ("speedlotto_500", "스피또500")]
SIDO = {"서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천", "광주광역시": "광주",
        "대전광역시": "대전", "울산광역시": "울산", "세종특별자치시": "세종", "경기도": "경기", "강원도": "강원",
        "강원특별자치도": "강원", "충청북도": "충북", "충청남도": "충남", "전라북도": "전북", "전북특별자치도": "전북",
        "전라남도": "전남", "경상북도": "경북", "경상남도": "경남", "제주특별자치도": "제주"}


def region_of(address):
    a = (address or "").split()
    if len(a) < 2 or "dhlottery" in (address or ""):
        return None
    return f"{SIDO.get(a[0], a[0])}|{a[1]}"


def store_info(db, lottery_types, codes):
    info = {}
    codes = sorted(codes)
    for lt in lottery_types:
        for i in range(0, len(codes), 150):
            for s in db.get("lottery_stores", {"select": "dhlottery_code,store_name,address",
                                               "lottery_type": f"eq.{lt}", "dhlottery_code": f"in.({','.join(codes[i:i + 150])})"}):
                info.setdefault(s["dhlottery_code"], s)
    return info


def rank_region(events, upto, hl):
    """events: {code: [(t, tier)]} · upto 이전 기록만 → 점수"""
    g = 0.5 ** (1 / hl)
    sc = {}
    for c, e in events.items():
        v = sum(g ** (upto - 1 - t) * (1.0 if tier == "first" else 0.5) for t, tier in e if t < upto)
        if v > 0:
            sc[c] = v
    return sorted(sc, key=lambda c: -sc[c]), sc


def build_regions(events, info, latest, hl, back, label_fn=None):
    by_region = defaultdict(dict)
    for c, e in events.items():
        rg = region_of((info.get(c) or {}).get("address"))
        if rg:
            by_region[rg][c] = e
    out, tot_hits, tot_events = {}, 0, 0
    for rg, ev in by_region.items():
        order, sc = rank_region(ev, latest + 1, hl)
        hits = n = 0
        for t in range(max(1, latest - back + 1), latest + 1):
            at = {c for c, e in ev.items() if any(x == t for x, _ in e)}
            if not at:
                continue
            o, _ = rank_region(ev, t, hl)
            n += len(at)
            hits += len(at & set(o[:TOP]))
        tot_hits += hits
        tot_events += n
        out[rg] = {
            "top": [{"store_code": c, "name": (info.get(c) or {}).get("store_name") or c,
                     "address": (info.get(c) or {}).get("address") or "",
                     "first": sum(1 for _, x in ev[c] if x == "first"), "second": sum(1 for _, x in ev[c] if x == "second"),
                     "last": max(t for t, _ in ev[c]), "score": round(sc[c], 4)} for c in order[:TOP]],
            "stores": len(ev), "events": sum(len(e) for e in ev.values()), "back_hits": hits, "back_events": n,
        }
    return out, {"hits": tot_hits, "events": tot_events, "regions": len(out)}


def pension_block(db):
    rows = db.all("winning_history", {"select": "round,dhlottery_code,prize_tier", "lottery_type": "eq.pension",
                                      "order": "round,dhlottery_code"}, key="round")
    events = defaultdict(list)
    for r in rows:
        if r["dhlottery_code"] and r["dhlottery_code"] not in ONLINE:
            events[r["dhlottery_code"]].append((int(r["round"]), r["prize_tier"]))
    if not events:
        return {"status": "no_data", "regions": {}}
    latest = max(t for e in events.values() for t, _ in e)
    info = store_info(db, ["pension"], events.keys())
    regions, back = build_regions(events, info, latest, PENSION_HL, PENSION_BACK)
    return {"status": "ok", "latest_round": latest, "target_round": latest + 1, "regions": regions, "backtest": back,
            "rule": f"연금 1·2등 기록 반감기 {PENSION_HL:.0f}회 감쇠 (2등 0.5배) · 지역 TOP{TOP} · 성적 = 최근 {PENSION_BACK}회 다시 뽑아 확인"}


def speetto_block(db):
    games = {}
    for lt, label in SPEETTO_GAMES:
        rows = db.all("winning_history", {"select": "round,dhlottery_code,prize_tier", "lottery_type": f"eq.{lt}",
                                          "order": "round,dhlottery_code"}, key="round")
        firsts = defaultdict(set)
        events = defaultdict(list)
        for r in rows:
            c = r["dhlottery_code"]
            if not c or c in ONLINE:
                continue
            events[c].append((int(r["round"]), r["prize_tier"]))
            if r["prize_tier"] == "first":
                firsts[int(r["round"])].add(c)
        eds = sorted(firsts)
        pairs = list(zip(eds, eds[1:]))
        same = sum(1 for a, b in pairs if firsts[a] and firsts[a] == firsts[b]) / len(pairs) if pairs else 0.0
        if not events:
            games[lt] = {"label": label, "status": "no_data", "regions": {}}
            continue
        if same > 0.5:
            games[lt] = {"label": label, "status": "data_invalid", "same_ratio": round(same, 3), "regions": {}}
            continue
        latest = max(t for e in events.values() for t, _ in e)
        info = store_info(db, [lt], events.keys())
        regions, back = build_regions(events, info, latest, SPEETTO_HL, SPEETTO_BACK)
        games[lt] = {"label": label, "status": "ok", "latest_edition": latest, "regions": regions, "backtest": back}
    return {"status": "ok" if any(g["status"] == "ok" for g in games.values()) else "waiting", "games": games,
            "rule": f"게임별 1·2등 기록 차수 기준 반감기 {SPEETTO_HL:.0f}차수 감쇠 · 지역 TOP{TOP} · 성적 = 최근 {SPEETTO_BACK}차수"}


def run(db, dry=False):
    now = datetime.now(timezone.utc)
    p = {"version": VERSION, "generated_at": now.isoformat(), "pension": pension_block(db), "speetto": speetto_block(db)}
    pb = p["pension"]
    print(f"연금 지방장: {pb['status']} · 지역 {len(pb['regions'])}곳 · 최근 {PENSION_BACK}회 성적 {pb.get('backtest')}")
    for lt, g in p["speetto"]["games"].items():
        print(f"스피또 지방장 {g['label']}: {g['status']} · 지역 {len(g['regions'])}곳 · 성적 {g.get('backtest')} {g.get('same_ratio', '')}")
    tag = int((now + timedelta(hours=9)).strftime("%Y%m%d"))
    row = {"research_type": RESULT_TYPE, "model_version": VERSION, "training_end_round": tag, "target_round": tag, "payload": p}
    json.dumps(row, ensure_ascii=False)
    if dry:
        print(f"드라이런 — 저장 안 함 (크기 {len(json.dumps(p, ensure_ascii=False)) // 1024}KB)")
        return p
    db.upsert("research_results", [row], "research_type,model_version,training_end_round,target_round")
    print("저장 완료")
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
