"""
로또 6/45 당첨번호 목록 주소 확인 (1회용 · 서버 전용) — 연금(/pt720/result → selectPstPt720WnList.do)과 같은 방식
  1차: /lt645/result 안 주소 = checkWnNo.do · selectPstLt645InfoNew.do
  3차: center + srchLtEpsd=1246 1번 — 응답 칸 확인 (요청 3번)
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
time.sleep(random.uniform(3.0, 5.0))
r = s.get("https://www.dhlottery.co.kr/lt645/selectPstLt645InfoNew.do", timeout=60, verify=False,
          params={"srchDir": "center", "srchLtEpsd": "1246"},
          headers=dict(ajax, Referer="https://www.dhlottery.co.kr/lt645/result"))
note("1 center 1246", r.status_code, r.headers.get("Content-Type"), "len", len(r.text))
try:
    lst = ((r.json().get("data") or {}).get("list")) or []
    note("2 개수", len(lst), "| 회차들:", [x.get("ltEpsd") for x in lst][:30])
    for i, x in enumerate(lst[:3]):
        note(f"3 행{i}:", json.dumps(x, ensure_ascii=False)[:2500])
except ValueError:
    note("2 JSON 아님:", re.sub(r"\s+", " ", r.text[:1200]))
