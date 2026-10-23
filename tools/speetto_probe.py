"""
동행복권 응답 형식 확인 (1회용 · 서버 전용) — 기존 크롤러가 쓰는 같은 주소·헤더로 최소 요청만 한다.
  2026-10-23 1차: 스피또 당첨지점 형식 확인 (완료 — 회차 = ltEpsd)
  2026-10-24 2차: 연금복권 당첨번호를 어디서 받을 수 있는지 — 요청 4번
    1~2) 세션 워밍업 (기존 크롤러와 같음)  3) 연금 당첨판매점 337회 응답 1건 (당첨번호 칸이 있는지)
    4) 연금 당첨결과 페이지 337회 (HTML 안 조·6자리 위치)
DB 읽기·쓰기 없음. 결과는 로그에만 (판매점 이름·코드 · 필드 이름).
"""
import json
import os
import random
import sys
import time

import requests
import urllib3

urllib3.disable_warnings()
_print = print


def print(*a):   # 로그 + 공개 주석(annotation) 으로도 남긴다 (로그는 관리자 권한 필요)
    msg = " ".join(str(x) for x in a)
    _print(msg)
    _print("::notice title=speetto-probe::" + msg.replace("%", "%25").replace(chr(13), "").replace(chr(10), " ")[:3500])


if os.environ.get("GITHUB_ACTIONS") != "true":
    sys.exit("서버(GitHub Actions)에서만 실행합니다 — PC 에서 동행복권 접속 금지")

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
html = {"User-Agent": UA, "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7"}
ajax = {"User-Agent": UA, "Accept": "application/json, text/javascript, */*; q=0.01", "Accept-Language": "ko-KR,ko;q=0.9",
        "X-Requested-With": "XMLHttpRequest", "Referer": "https://www.dhlottery.co.kr/wnprchsplcsrch/selectWnPrchsPlcList.do",
        "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin"}
s = requests.Session()
for u in ("https://www.dhlottery.co.kr/common.do?method=main", "https://www.dhlottery.co.kr/wnprchsplcsrch/selectWnPrchsPlcList.do"):
    r = s.get(u, headers=html, timeout=30, verify=False)
    print("warm-up", u, r.status_code)
    time.sleep(random.uniform(2.0, 3.5))
# 3) 연금 당첨판매점 API (기존 크롤러 crawl_pension_stores 와 같은 주소)
r = s.get("https://www.dhlottery.co.kr/wnprchsplcsrch/selectPtWnShp.do", timeout=60, verify=False,
          headers=dict(ajax, Referer="https://www.dhlottery.co.kr/wnprchsplcsrch/wnprchsplcsrch.do"),
          params={"srchWnShpRnk": "all", "srchLtEpsd": 337, "srchShpLctn": ""})
print("pension-store", r.status_code, r.headers.get("Content-Type"))
try:
    d = r.json()
    data = d.get("data") or {}
    print("pension-store keys:", list(d.keys()), list(data.keys()) if isinstance(data, dict) else type(data).__name__)
    lst = data.get("list") if isinstance(data, dict) else None
    if lst:
        print("pension-store record0:", json.dumps(lst[0], ensure_ascii=False)[:1500])
    print("pension-store 다른 칸:", json.dumps({k: v for k, v in data.items() if k != "list"}, ensure_ascii=False)[:1500] if isinstance(data, dict) else "")
except ValueError:
    print("pension-store JSON 아님:", r.text[:500])
time.sleep(random.uniform(3.0, 5.0))

# 4) 연금 당첨결과 페이지 (HTML) — 조·번호가 들어 있는 부분만 잘라 본다
import re
r = s.get("https://www.dhlottery.co.kr/gameResult.do", headers=html, timeout=60, verify=False,
          params={"method": "win720", "Round": 337})
print("win720", r.status_code, r.headers.get("Content-Type"), "len", len(r.text), "final", r.url)
t = r.text
for kw in ("win720", "조", "num", "drwNo", "337"):
    i = t.find(kw)
    print(f"win720 '{kw}' 위치 {i}:", re.sub(r"\s+", " ", t[max(0, i - 200): i + 400]) if i >= 0 else "-")
