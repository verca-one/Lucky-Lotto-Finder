"""
스피또 당첨지점 응답 형식 확인 (1회용 · 서버 전용) — 기존 크롤러가 쓰는 같은 주소·헤더로 딱 3번만 요청한다.
  1~2) 세션 워밍업 페이지 2개 (기존 크롤러와 같음)  3) 스피또1000 당첨지점 목록 1페이지 5건
목적: 회차(차수) 값이 응답의 어느 칸에 있는지 확인 → 기존 스피또 크롤러가 회차를 구분하도록 고친다.
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
r = s.get("https://www.dhlottery.co.kr/st/selectWnDsctn.do", headers=ajax, timeout=60, verify=False,
          params={"stGmTypeNm": "스피또1000", "srchOption": 1, "srchValue": "", "pageNum": 1, "recordCountPerPage": 5})
print("speetto", r.status_code, r.headers.get("Content-Type"))
try:
    d = r.json()
except ValueError:
    print("JSON 아님:", r.text[:800])
    sys.exit(0)
print("top keys:", list(d.keys()))
data = d.get("data")
if isinstance(data, dict):
    print("data keys:", list(data.keys()), "total:", data.get("total"))
    lst = data.get("list") or []
    for i, rec in enumerate(lst[:5]):
        print(f"record {i}:", json.dumps(rec, ensure_ascii=False))
    print("다른 칸:", json.dumps({k: v for k, v in data.items() if k != "list"}, ensure_ascii=False)[:1500])
else:
    print(json.dumps(d, ensure_ascii=False)[:2000])
