"""
연금복권720+ 당첨번호 수집기 (새 파일 · 2026-10-24) — 기존 판매점 크롤러와 완전히 별개

  동행복권 연금 결과 화면(/pt720/result)이 쓰는 목록 주소 한 번으로 1회~최신 회차 당첨번호를 모두 받는다.
    /pt720/selectPstPt720WnList.do → data.result = [{psltEpsd(회차), psltRflYmd(추첨일), wnBndNo(1등 조),
                                                    wnRnkVl(1등 6자리), bnsRnkVl(보너스 6자리)}, ...]
  요청은 실행당 3번: 첫 화면(쿠키) → 연금 결과 화면(Referer) → 목록 1번. 요청 사이 2~5초 쉰다 (차단 방지).
  저장: pension_winning_numbers — 없는 회차만 추가한다. 이미 있는 회차는 덮어쓰지 않고, 값이 다르면 로그에만 남긴다.
  기존 크롤러 · 워크플로 · 다른 테이블은 건드리지 않는다. 서버(GitHub Actions)에서만 실행 (PC 에서 동행복권 접속 금지).

사용: python pension_numbers_collector.py [--dry-run]
"""

import argparse
import json
import os
import random
import re
import sys
import time
from datetime import date, datetime, timedelta, timezone

import requests
import urllib3

urllib3.disable_warnings()

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
HTML = {"User-Agent": UA, "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7"}
AJAX = {"User-Agent": UA, "Accept": "application/json, text/javascript, */*; q=0.01", "Accept-Language": "ko-KR,ko;q=0.9",
        "X-Requested-With": "XMLHttpRequest", "Referer": "https://www.dhlottery.co.kr/pt720/result",
        "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin"}
LIST_URL = "https://www.dhlottery.co.kr/pt720/selectPstPt720WnList.do"


def fetch():
    s = requests.Session()
    s.get("https://www.dhlottery.co.kr/common.do?method=main", headers=HTML, timeout=30, verify=False)
    time.sleep(random.uniform(2.0, 3.5))
    s.get("https://www.dhlottery.co.kr/pt720/result", headers=HTML, timeout=60, verify=False)
    time.sleep(random.uniform(3.0, 5.0))
    r = s.get(LIST_URL, headers=AJAX, timeout=60, verify=False)
    if r.status_code != 200 or "json" not in (r.headers.get("Content-Type") or ""):
        raise RuntimeError(f"목록 응답 이상: HTTP {r.status_code} {r.headers.get('Content-Type')}")
    return (r.json().get("data") or {}).get("result") or []


def parse(rows):
    """검증된 행만 → {round: {...}}"""
    out, bad = {}, 0
    for x in rows:
        try:
            rnd = int(x.get("psltEpsd"))
            g = int(str(x.get("wnBndNo")).strip())
            n = str(x.get("wnRnkVl") or "").strip()
            b = str(x.get("bnsRnkVl") or "").strip()
            d = str(x.get("psltRflYmd") or "").strip()
        except (TypeError, ValueError):
            bad += 1
            continue
        if not (1 <= g <= 5 and re.fullmatch(r"\d{6}", n) and re.fullmatch(r"\d{6}", b) and re.fullmatch(r"\d{8}", d)):
            bad += 1
            continue
        out[rnd] = {"round": rnd, "winning_group": g, "winning_number": n, "bonus_number": b,
                    "draw_date": f"{d[:4]}-{d[4:6]}-{d[6:]}"}
    return out, bad


class Db:
    def __init__(self, url, key):
        self.base = url.rstrip("/") + "/rest/v1/"
        self.h = {"apikey": key, "Content-Type": "application/json"}
        if not key.startswith("sb_"):
            self.h["Authorization"] = f"Bearer {key}"

    def latest(self):
        r = requests.get(self.base + "pension_winning_numbers", params={"select": "round,draw_date", "order": "round.desc", "limit": "1"},
                         headers=self.h, timeout=60)
        r.raise_for_status()
        return (r.json() or [None])[0]

    def existing(self):
        out, off = {}, 0
        while True:
            r = requests.get(self.base + "pension_winning_numbers", timeout=60,
                             params={"select": "round,winning_group,winning_number,bonus_number", "order": "round"},
                             headers=dict(self.h, **{"Range-Unit": "items", "Range": f"{off}-{off + 999}"}))
            r.raise_for_status()
            rows = r.json()
            for x in rows:
                out[int(x["round"])] = x
            if len(rows) < 1000:
                return out
            off += 1000

    def insert_missing(self, rows):
        """없는 회차만 추가 (이미 있으면 무시 — 덮어쓰기 없음)"""
        for i in range(0, len(rows), 100):
            r = requests.post(self.base + "pension_winning_numbers", params={"on_conflict": "round"}, timeout=120,
                              headers=dict(self.h, Prefer="resolution=ignore-duplicates,return=minimal"),
                              data=json.dumps(rows[i:i + 100], ensure_ascii=False).encode("utf-8"))
            if r.status_code not in (200, 201, 204):
                raise RuntimeError(f"저장 실패 {r.status_code} {r.text[:300]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("서버(GitHub Actions)에서만 실행합니다 — PC 에서 동행복권 접속 금지")
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다")
    db = Db(url, key)
    # 다음 회차 추첨(목 19:05 KST) 결과가 올라올 때(19:15)까지는 동행복권에 접속하지 않고 끝낸다
    # (GitHub 예약 실행이 밀려도 놓치지 않게 목요일 밤에 20분마다 돌리므로, 받을 게 없는 실행은 요청 없이 바로 끝)
    last = db.latest()
    if last and last.get("draw_date"):
        kst = timezone(timedelta(hours=9))
        d = date.fromisoformat(str(last["draw_date"])[:10]) + timedelta(days=7)
        ready = datetime(d.year, d.month, d.day, 19, 15, tzinfo=kst)
        if datetime.now(kst) < ready:
            print(f"{last['round'] + 1}회 추첨 결과 전 ({ready:%m/%d %H:%M} KST 이후 수집) — 접속하지 않음")
            return
    got, bad = parse(fetch())
    if not got:
        sys.exit("받은 당첨번호가 없습니다 — 응답 형식 변경 가능성, 저장하지 않음")
    have = db.existing()
    new = [got[r] for r in sorted(got) if r not in have]
    diff = [(r, have[r], got[r]) for r in sorted(got) if r in have and (
        int(have[r].get("winning_group") or 0) != got[r]["winning_group"]
        or str(have[r].get("winning_number")) != got[r]["winning_number"]
        or str(have[r].get("bonus_number")) != got[r]["bonus_number"])]
    print(f"받은 회차 {len(got)}개 ({min(got)}~{max(got)}회, 형식 오류 {bad}) · DB 기존 {len(have)}개 · 새로 추가 {len(new)}개 · 값 다름 {len(diff)}개")
    for r, h, g in diff:
        print(f"::warning title=연금 당첨번호 불일치::{r}회 DB {h.get('winning_group')}조 {h.get('winning_number')} 보너스 {h.get('bonus_number')}"
              f" ↔ 동행복권 {g['winning_group']}조 {g['winning_number']} 보너스 {g['bonus_number']} (덮어쓰지 않음)")
    if new:
        print(f"추가: {new[0]['round']}~{new[-1]['round']}회 · 최신 {new[-1]['round']}회 {new[-1]['winning_group']}조 {new[-1]['winning_number']}")
    if a.dry_run:
        print("드라이런 — 저장 안 함")
        return
    if new:
        db.insert_missing(new)
        print(f"저장 완료 {len(new)}개")


if __name__ == "__main__":
    main()
