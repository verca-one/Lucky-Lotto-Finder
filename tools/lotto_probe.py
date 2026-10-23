"""
로또 6/45 당첨번호 목록 주소 확인 (1회용 · 서버 전용) — 연금(/pt720/result → selectPstPt720WnList.do)과 같은 방식
  1차: /lt645/result 안 주소 = checkWnNo.do · selectPstLt645InfoNew.do
  2차: 첫 화면 → 결과 화면(호출 코드·파라미터) → selectPstLt645InfoNew.do 1번 — 요청 3번 · DB 무관
"""
import json
import os
import random
import re
import sys
import time

import requests
import urllib3

urllib3.disable_warnings()
if os.environ.get("GITHUB_ACTIONS") != "true":
    sys.exit("서버(GitHub Actions)에서만 실행합니다 — PC 에서 동행복권 접속 금지")


def note(*a):   # 로그 + 공개 주석 (단계당 10줄 제한 → 짧게)
    msg = " ".join(str(x) for x in a)
    print(msg)
    print("::notice title=lotto-probe::" + msg.replace("%", "%25").replace(chr(13), "").replace(chr(10), " ")[:3500])


UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
html = {"User-Agent": UA, "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", "Accept-Language": "ko-KR,ko;q=0.9"}
ajax = {"User-Agent": UA, "Accept": "application/json, text/javascript, */*; q=0.01", "Accept-Language": "ko-KR,ko;q=0.9",
        "X-Requested-With": "XMLHttpRequest", "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin"}
s = requests.Session()
r = s.get("https://www.dhlottery.co.kr/common.do?method=main", headers=html, timeout=30, verify=False)
time.sleep(random.uniform(2.5, 4.0))
r = s.get("https://www.dhlottery.co.kr/lt645/result", headers=html, timeout=60, verify=False)
t = r.text
calls = [re.sub(r"\s+", " ", t[max(0, m.start() - 450): m.start() + 250]) for m in re.finditer(r"selectPstLt645InfoNew", t)]
note("1 result", r.status_code, "| 호출", len(calls), "곳:", " || ".join(calls)[:3300])
params = sorted({m.group(1) for c in calls for m in re.finditer(r"([A-Za-z]+)\s*:", c) if m.group(1).startswith("srch")})
note("2 srch 파라미터:", params)
time.sleep(random.uniform(3.0, 5.0))
r = s.get("https://www.dhlottery.co.kr/lt645/selectPstLt645InfoNew.do", timeout=60, verify=False,
          headers=dict(ajax, Referer="https://www.dhlottery.co.kr/lt645/result"))
note("3 InfoNew(파라미터 없이)", r.status_code, r.headers.get("Content-Type"), "len", len(r.text))
try:
    d = r.json()
    data = d.get("data")
    note("4 keys", list(d.keys()), "| data:", type(data).__name__, list(data.keys()) if isinstance(data, dict) else "")
    lst = None
    if isinstance(data, dict):
        lst = next((v for v in data.values() if isinstance(v, list) and v), None)
    elif isinstance(data, list):
        lst = data
    if lst:
        note("5 개수", len(lst), "| 첫 행:", json.dumps(lst[0], ensure_ascii=False)[:1500])
        note("6 끝 행:", json.dumps(lst[-1], ensure_ascii=False)[:1500])
    else:
        note("5 응답:", json.dumps(d, ensure_ascii=False)[:3000])
except ValueError:
    note("4 JSON 아님:", re.sub(r"\s+", " ", r.text[:1200]))
