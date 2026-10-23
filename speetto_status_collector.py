"""
스피또 판매 현황 수집기 (새 파일 · 2026-10-24) — 기존 스피또 판매점 크롤러와 별개

  동행복권 스피또 소개 화면(/st/st10Intro 등)이 쓰는 주소로 게임별 '판매 중인 차수'의 출고율 · 남은 매수를 받는다.
    /st/selectSellStInfo.do?srchStGmTypeCd=SP500|SP1000|SP2000 → data.list = 판매 중 차수들
      stEpsd(차수) · stSpmtRt(출고율 %) · stRnkNWnQty(N등 전체) · stIvtRnkNQty(N등 남은) · stNtslBgngDt/EndDt(판매 기간) ...
  요청은 실행당 4번: 첫 화면(쿠키) → 게임 3개 각 1번. 요청 사이 3~5초 쉰다 (차단 방지).
  저장: research_speetto_status (research_v17_speetto_status.sql) — 그날(KST) 기록을 차수별로 (같은 날 다시 돌면 덮어씀).
  기존 크롤러 · 워크플로 · 다른 테이블은 건드리지 않는다. 서버(GitHub Actions)에서만 실행 (PC 에서 동행복권 접속 금지).

사용: python speetto_status_collector.py [--dry-run]
"""

import argparse
import json
import os
import random
import sys
import time
from datetime import datetime, timedelta, timezone

import requests
import urllib3

urllib3.disable_warnings()

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
HTML = {"User-Agent": UA, "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", "Accept-Language": "ko-KR,ko;q=0.9"}
AJAX = {"User-Agent": UA, "Accept": "application/json, text/javascript, */*; q=0.01", "Accept-Language": "ko-KR,ko;q=0.9",
        "X-Requested-With": "XMLHttpRequest", "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin"}
GAMES = [("SP500", "st5Intro"), ("SP1000", "st10Intro"), ("SP2000", "st20Intro")]
KST = timezone(timedelta(hours=9))


def _i(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _ts(v):
    v = (v or "").strip()
    return f"{v.replace(' ', 'T')}+09:00" if len(v) >= 10 else None


def to_row(x, snap):
    return {"snap_date": snap, "game": x.get("stGmTypeCd"), "edition": _i(x.get("stEpsd")), "price": _i(x.get("stNtslAmt")),
            "sale_start": _ts(x.get("stNtslBgngDt")), "sale_end": _ts(x.get("stNtslEndDt")), "ship_rate": _f(x.get("stSpmtRt")),
            "rnk1_total": _i(x.get("stRnk1WnQty")), "rnk1_left": _i(x.get("stIvtRnk1Qty")),
            "rnk2_total": _i(x.get("stRnk2WnQty")), "rnk2_left": _i(x.get("stIvtRnk2Qty")),
            "rnk3_total": _i(x.get("stRnk3WnQty")), "rnk3_left": _i(x.get("stIvtRnk3Qty")),
            "prize1": x.get("stRnk1GdsLstcCharCn"), "prize2": x.get("stRnk2GdsLstcCharCn"), "prize3": x.get("stRnk3GdsLstcCharCn"),
            "odds": x.get("stSumWnPbltNm"), "site_changed": x.get("dataChgDt"),
            "raw": {k: v for k, v in x.items() if not str(k).endswith("PathNm") or k in ("stMainImgStrgPathNm", "tm1StWnImgStrgPathNm")}}


def fetch():
    s = requests.Session()
    s.get("https://www.dhlottery.co.kr/common.do?method=main", headers=HTML, timeout=30, verify=False)
    out = []
    for code, page in GAMES:
        time.sleep(random.uniform(3.0, 5.0))
        r = s.get("https://www.dhlottery.co.kr/st/selectSellStInfo.do", timeout=60, verify=False,
                  headers=dict(AJAX, Referer=f"https://www.dhlottery.co.kr/st/{page}"), params={"srchStGmTypeCd": code})
        if r.status_code != 200 or "json" not in (r.headers.get("Content-Type") or ""):
            print(f"{code} 응답 이상: HTTP {r.status_code} {r.headers.get('Content-Type')}")
            continue
        lst = ((r.json().get("data") or {}).get("list")) or []
        print(f"{code}: 판매 중 {len(lst)}개 차수")
        out += lst
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("서버(GitHub Actions)에서만 실행합니다 — PC 에서 동행복권 접속 금지")
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다")
    snap = datetime.now(KST).date().isoformat()
    rows = [r for r in (to_row(x, snap) for x in fetch()) if r["game"] and r["edition"]]
    for r in rows:
        print(f"  {r['game']} {r['edition']}차 출고율 {r['ship_rate']}% · 1등 {r['rnk1_left']}/{r['rnk1_total']} · "
              f"2등 {r['rnk2_left']}/{r['rnk2_total']} · {r['prize1']}")
    if not rows:
        sys.exit("받은 판매 현황이 없습니다 — 저장하지 않음")
    if a.dry_run:
        print("드라이런 — 저장 안 함")
        return
    h = {"apikey": key, "Content-Type": "application/json", "Prefer": "resolution=merge-duplicates,return=minimal"}
    if not key.startswith("sb_"):
        h["Authorization"] = f"Bearer {key}"
    r = requests.post(url.rstrip("/") + "/rest/v1/research_speetto_status", params={"on_conflict": "snap_date,game,edition"},
                      headers=h, data=json.dumps(rows, ensure_ascii=False).encode("utf-8"), timeout=60)
    if r.status_code not in (200, 201, 204):
        sys.exit(f"저장 실패 {r.status_code} {r.text[:300]} — research_v17_speetto_status.sql 실행 필요할 수 있음")
    print(f"저장 완료 {len(rows)}개 ({snap})")


if __name__ == "__main__":
    main()
