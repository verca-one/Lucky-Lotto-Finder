"""
스피또 판매 현황(출고율 · 남은 1·2등) 주소 확인 (1회용 · 서버 전용) — 사용자가 알려 준 /st/st10Intro 출발
  1차: /st/st10Intro → 내부 주소 /st/selectSellStInfo.do (srchStGmTypeCd = SP1000 등)
  2차: 첫 화면 + SP1000 · SP2000 · SP500 각 1번 — 요청 4번 · DB 무관
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


def note(*a):   # 로그 + 공개 주석 (단계당 10줄 제한 → 8줄 안으로)
    msg = " ".join(str(x) for x in a)
    print(msg)
    print("::notice title=speetto-status::" + msg.replace("%", "%25").replace(chr(13), "").replace(chr(10), " ")[:3500])


UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
html = {"User-Agent": UA, "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", "Accept-Language": "ko-KR,ko;q=0.9"}
ajax = {"User-Agent": UA, "Accept": "application/json, text/javascript, */*; q=0.01", "Accept-Language": "ko-KR,ko;q=0.9",
        "X-Requested-With": "XMLHttpRequest", "Referer": "https://www.dhlottery.co.kr/st/st10Intro",
        "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin"}
s = requests.Session()
s.get("https://www.dhlottery.co.kr/common.do?method=main", headers=html, timeout=30, verify=False)
for code in ("SP1000", "SP2000", "SP500"):
    time.sleep(random.uniform(3.0, 5.0))
    r = s.get("https://www.dhlottery.co.kr/st/selectSellStInfo.do", headers=ajax, timeout=60, verify=False,
              params={"srchStGmTypeCd": code})
    try:
        d = r.json().get("data") or {}
        lst, rd = d.get("list") or [], d.get("rnkDatelist") or []
        note(code, r.status_code, "| list", len(lst), "rnkDatelist", len(rd), "| list[0]:", json.dumps(lst[0] if lst else None, ensure_ascii=False)[:1600],
             "| rnkDatelist[0..1]:", json.dumps(rd[:2], ensure_ascii=False)[:1200])
    except ValueError:
        note(code, r.status_code, "JSON 아님:", re.sub(r"\s+", " ", r.text[:800]))
