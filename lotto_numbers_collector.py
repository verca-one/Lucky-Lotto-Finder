"""
로또 6/45 당첨번호 수집기 (새 파일 · 2026-10-24) — 기존 판매점 크롤러와 완전히 별개

  동행복권 로또 결과 화면(/lt645/result)이 쓰는 주소로 최신 회차 당첨번호를 받는다.
    /lt645/selectPstLt645InfoNew.do?srchDir=center&srchLtEpsd=N → data.list = N회 포함 최근 10회
      [{ltEpsd(회차), tm1WnNo~tm6WnNo(당첨번호), bnsWnNo(보너스), ltRflYmd(추첨일 YYYYMMDD), ...}]
  요청은 실행당 3번: 첫 화면(쿠키) → 로또 결과 화면(Referer) → 목록 1번. 요청 사이 2~5초 쉰다 (차단 방지).
  저장 = 자동 발행: lotto_winning_numbers 에 없는 회차만 추가한다 (일반 화면은 이 표에 들어온 회차를 바로 보여 준다).
    이미 있는 회차는 덮어쓰지 않고, 값이 다르면 경고만 남긴다.
  기존 크롤러 · 워크플로 · 다른 테이블은 건드리지 않는다. 서버(GitHub Actions)에서만 실행 (PC 에서 동행복권 접속 금지).

사용: python lotto_numbers_collector.py [--dry-run]
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
        "X-Requested-With": "XMLHttpRequest", "Referer": "https://www.dhlottery.co.kr/lt645/result",
        "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin"}
INFO_URL = "https://www.dhlottery.co.kr/lt645/selectPstLt645InfoNew.do"


def fetch(target):
    s = requests.Session()
    s.get("https://www.dhlottery.co.kr/common.do?method=main", headers=HTML, timeout=30, verify=False)
    time.sleep(random.uniform(2.0, 3.5))
    s.get("https://www.dhlottery.co.kr/lt645/result", headers=HTML, timeout=60, verify=False)
    time.sleep(random.uniform(3.0, 5.0))
    r = s.get(INFO_URL, headers=AJAX, timeout=60, verify=False, params={"srchDir": "center", "srchLtEpsd": str(target)})
    if r.status_code != 200 or "json" not in (r.headers.get("Content-Type") or ""):
        raise RuntimeError(f"응답 이상: HTTP {r.status_code} {r.headers.get('Content-Type')}")
    return ((r.json().get("data") or {}).get("list")) or []


def parse(rows):
    out, bad = {}, 0
    for x in rows:
        try:
            rnd = int(x.get("ltEpsd"))
            nums = sorted(int(x.get(f"tm{i}WnNo")) for i in range(1, 7))
            bonus = int(x.get("bnsWnNo"))
            d = str(x.get("ltRflYmd") or "").strip()
        except (TypeError, ValueError):
            bad += 1
            continue
        if len(set(nums)) != 6 or not all(1 <= n <= 45 for n in nums + [bonus]) or bonus in nums \
                or not re.fullmatch(r"\d{8}", d):
            bad += 1
            continue
        out[rnd] = {"round": rnd, **{f"num{i + 1}": n for i, n in enumerate(nums)}, "bonus": bonus,
                    "draw_date": f"{d[:4]}-{d[4:6]}-{d[6:]}"}
    return out, bad


class Db:
    def __init__(self, url, key):
        self.base = url.rstrip("/") + "/rest/v1/"
        self.h = {"apikey": key, "Content-Type": "application/json"}
        if not key.startswith("sb_"):
            self.h["Authorization"] = f"Bearer {key}"

    def get(self, params):
        r = requests.get(self.base + "lotto_winning_numbers", params=params, headers=self.h, timeout=60)
        r.raise_for_status()
        return r.json()

    def insert_missing(self, rows):
        r = requests.post(self.base + "lotto_winning_numbers", params={"on_conflict": "round"}, timeout=120,
                          headers=dict(self.h, Prefer="resolution=ignore-duplicates,return=minimal"),
                          data=json.dumps(rows, ensure_ascii=False).encode("utf-8"))
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
    latest = db.get({"select": "round,draw_date", "order": "round.desc", "limit": "1"})
    last_draw = str(latest[0].get("draw_date") or "")[:10] if latest else ""
    latest = int(latest[0]["round"]) if latest else 0
    target = latest + 1
    # 다음 회차 추첨(토 20:35 KST) 결과가 올라올 때(20:45)까지는 동행복권에 접속하지 않고 끝낸다
    # (GitHub 예약 실행이 밀려도 놓치지 않게 토요일 밤에 자주 돌리므로, 받을 게 없는 실행은 요청 없이 바로 끝)
    if last_draw:
        kst = timezone(timedelta(hours=9))
        d = date.fromisoformat(last_draw) + timedelta(days=7)
        ready = datetime(d.year, d.month, d.day, 20, 45, tzinfo=kst)
        if datetime.now(kst) < ready:
            print(f"{target}회 추첨 결과 전 ({ready:%m/%d %H:%M} KST 이후 수집) — 접속하지 않음")
            return
    got, bad = parse(fetch(target))
    if not got:
        print(f"{target}회 아직 없음 (동행복권에 결과가 올라오기 전) — 저장 안 함")
        return
    lo = min(got)
    have = {int(x["round"]): x for x in db.get({"select": "round,num1,num2,num3,num4,num5,num6,bonus",
                                                  "round": f"gte.{lo}", "order": "round"})}
    new = [got[r] for r in sorted(got) if r not in have]
    diff = [r for r in sorted(got) if r in have and any(int(have[r][k]) != got[r][k] for k in
                                                       ("num1", "num2", "num3", "num4", "num5", "num6", "bonus"))]
    print(f"받은 회차 {sorted(got)} (형식 오류 {bad}) · DB 최신 {latest}회 · 새로 추가 {[x['round'] for x in new]} · 값 다름 {diff}")
    for r in diff:
        h, g = have[r], got[r]
        print(f"::warning title=로또 당첨번호 불일치::{r}회 DB {[h[f'num{i}'] for i in range(1, 7)]}+{h['bonus']} ↔ "
              f"동행복권 {[g[f'num{i}'] for i in range(1, 7)]}+{g['bonus']} (덮어쓰지 않음)")
    if a.dry_run:
        print("드라이런 — 저장 안 함")
        return
    if new:
        db.insert_missing(new)
        for x in new:
            print(f"::notice title=로또 당첨번호 발행::{x['round']}회 {[x[f'num{i}'] for i in range(1, 7)]} + {x['bonus']} ({x['draw_date']})")
        print(f"저장(발행) 완료 {len(new)}개")


if __name__ == "__main__":
    main()
