"""
research_prize_stats_collector.py — 회차별 판매액·등수별 당첨자 수 독립 수집기 (2026-10-09 수집 승인)

* 기존 크롤러(lotto_verca_*.py)·GitHub Actions 와 무관한 독립 스크립트. 기존 테이블은 건드리지 않는다.
* 출처: 동행복권 공개 당첨결과 JSON  GET /lt645/selectPstLt645InfoNew.do?srchDir=center|older&srchLtEpsd|srchCursorLtEpsd
  (10회차/페이지). 요청 간격 1초, 식별 가능한 User-Agent, 재시도 3회.
* 저장: --out JSON 파일(항상) + SUPABASE_URL/SUPABASE_KEY 환경변수가 있으면 research_prize_stats 테이블 upsert.

사용:  python research_prize_stats_collector.py --from 1 --to 1244 --out research_prize_stats.json
       python research_prize_stats_collector.py --latest 20        # 최신 20회차만
       python research_prize_stats_collector.py --upload-only research_prize_stats.json
"""
import argparse, json, os, sys, time
from datetime import datetime, timezone

import requests
import urllib3

urllib3.disable_warnings()
BASE = "https://www.dhlottery.co.kr"
API = BASE + "/lt645/selectPstLt645InfoNew.do"
UA = "LuckyLottoFinder-Research/1.0 (prize-stats collector; contact: app admin)"
HEADERS = {"User-Agent": UA, "Accept": "application/json, text/javascript, */*; q=0.01",
           "X-Requested-With": "XMLHttpRequest", "Accept-Language": "ko-KR,ko;q=0.9",
           "Referer": BASE + "/lt645/result"}
SLEEP = 1.0


def session_with_warmup():
    s = requests.Session()
    try:
        s.get(BASE + "/common.do", params={"method": "main"}, headers={"User-Agent": UA}, timeout=15, verify=False)
        time.sleep(SLEEP)
        s.get(BASE + "/lt645/result", headers={"User-Agent": UA}, timeout=15, verify=False)
        time.sleep(SLEEP)
    except Exception as e:
        print(f"[warn] warm-up failed (continuing): {e}", file=sys.stderr)
    return s


def fetch_page(s, params):
    for attempt in range(3):
        try:
            r = s.get(API, params=params, headers=HEADERS, timeout=40, verify=False)
            txt = r.text.strip()
            if r.status_code == 200 and txt.startswith("{"):
                data = r.json().get("data") or {}
                return data.get("list") or []
            print(f"[warn] non-JSON response (status {r.status_code}) attempt {attempt+1}", file=sys.stderr)
        except Exception as e:
            print(f"[warn] request error attempt {attempt+1}: {e}", file=sys.stderr)
        time.sleep(SLEEP * 10 * (attempt + 1))  # 차단·타임아웃 시 길게 대기 후 재시도
    return []


def to_int(v):
    try:
        return int(v) if v is not None else None
    except (TypeError, ValueError):
        return None


def normalize(item):
    ymd = str(item.get("ltRflYmd") or "")
    draw_date = f"{ymd[0:4]}-{ymd[4:6]}-{ymd[6:8]}" if len(ymd) == 8 else None
    row = {
        "round": to_int(item.get("ltEpsd")), "draw_date": draw_date,
        "num1": to_int(item.get("tm1WnNo")), "num2": to_int(item.get("tm2WnNo")), "num3": to_int(item.get("tm3WnNo")),
        "num4": to_int(item.get("tm4WnNo")), "num5": to_int(item.get("tm5WnNo")), "num6": to_int(item.get("tm6WnNo")),
        "bonus": to_int(item.get("bnsWnNo")),
        "total_sales_amount": to_int(item.get("wholEpsdSumNtslAmt")),
        "prize_pool_amount": to_int(item.get("rlvtEpsdSumNtslAmt")),
        "auto_winners": to_int(item.get("winType1")), "manual_winners": to_int(item.get("winType2")),
        "semi_auto_winners": to_int(item.get("winType3")),
        "raw": item,
    }
    for k in range(1, 6):
        row[f"rank{k}_winners"] = to_int(item.get(f"rnk{k}WnNope"))
        row[f"rank{k}_amount"] = to_int(item.get(f"rnk{k}WnAmt"))
        row[f"rank{k}_total"] = to_int(item.get(f"rnk{k}SumWnAmt"))
    return row


def collect(from_round, to_round):
    s = session_with_warmup()
    rows = {}
    cursor = to_round
    # center 페이지로 시작 → older 커서로 과거 방향 진행
    page = fetch_page(s, {"srchDir": "center", "srchLtEpsd": str(to_round)})
    while True:
        if not page:
            print(f"[info] empty page at cursor {cursor}; stop", file=sys.stderr)
            break
        for it in page:
            r = normalize(it)
            if r["round"] and from_round <= r["round"] <= to_round:
                rows[r["round"]] = r
        min_round = min(to_int(it.get("ltEpsd")) or 10**9 for it in page)
        print(f"[fetch] {min_round}~{max(to_int(it.get('ltEpsd')) or 0 for it in page)} ({len(rows)} collected)", file=sys.stderr)
        if min_round <= from_round or min_round <= 1:
            break
        cursor = min_round
        time.sleep(SLEEP)
        page = fetch_page(s, {"srchDir": "older", "srchCursorLtEpsd": str(cursor)})
    return [rows[k] for k in sorted(rows)]


def upload(rows):
    url, key = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY")
    if not url or not key:
        print("[info] SUPABASE_URL/SUPABASE_KEY not set → upload skipped", file=sys.stderr)
        return 0
    from supabase import create_client
    client = create_client(url, key)
    done = 0
    for i in range(0, len(rows), 200):
        chunk = [{k: v for k, v in r.items()} for r in rows[i:i + 200]]
        for r in chunk:
            r["collected_at"] = datetime.now(timezone.utc).isoformat()
        client.table("research_prize_stats").upsert(chunk, on_conflict="round").execute()
        done += len(chunk)
        print(f"[upload] {done}/{len(rows)}", file=sys.stderr)
    return done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="from_round", type=int, default=1)
    ap.add_argument("--to", dest="to_round", type=int, default=None)
    ap.add_argument("--latest", type=int, default=None, help="최신 N회차만")
    ap.add_argument("--out", default="research_prize_stats.json")
    ap.add_argument("--upload-only", default=None, help="기존 JSON 을 업로드만")
    ap.add_argument("--sleep", type=float, default=1.0, help="요청 간격(초)")
    a = ap.parse_args()
    global SLEEP
    SLEEP = a.sleep

    if a.upload_only:
        rows = json.load(open(a.upload_only, encoding="utf-8"))["rows"]
        n = upload(rows)
        print(json.dumps({"uploaded": n, "rows": len(rows)}))
        return

    to_round = a.to_round
    if to_round is None:
        s = session_with_warmup()
        latest = fetch_page(s, {"srchDir": "latest", "srchCursorLtEpsd": "9999"}) or fetch_page(s, {"srchDir": "center", "srchLtEpsd": "1244"})
        to_round = max(to_int(it.get("ltEpsd")) or 0 for it in latest) if latest else 1244
    from_round = a.from_round if a.latest is None else max(1, to_round - a.latest + 1)

    rows = collect(from_round, to_round)
    json.dump({"source": API, "collected_at": datetime.now(timezone.utc).isoformat(),
               "from": from_round, "to": to_round, "count": len(rows), "rows": rows},
              open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    n = upload(rows)
    missing = [r for r in range(from_round, to_round + 1) if r not in {x["round"] for x in rows}]
    print(json.dumps({"from": from_round, "to": to_round, "collected": len(rows), "missing": missing[:20],
                      "missing_count": len(missing), "uploaded": n, "out": a.out}))


if __name__ == "__main__":
    main()
