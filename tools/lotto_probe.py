"""
로또 6/45 당첨번호 목록 주소 확인 (1회용 · 서버 전용) — 연금(/pt720/result → selectPstPt720WnList.do)과 같은 방식
  1) 첫 화면 (쿠키 · 로또 결과 링크 찾기)  2) 로또 결과 화면  3) 그 화면이 쓰는 당첨 목록 주소 1번 — 요청 3~4번 · DB 무관
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
main = r.text
links = sorted({m.group(1) for m in re.finditer(r"""["'](/lt645/[A-Za-z0-9_/]*)["']""", main)})
note("1 main", r.status_code, "| /lt645 링크:", links[:30])
page = next((x for x in links if re.search(r"result", x, re.I)), "/lt645/result")
time.sleep(random.uniform(2.5, 4.0))
r = s.get("https://www.dhlottery.co.kr" + page, headers=html, timeout=60, verify=False)
t = r.text
eps = sorted({m.group(0) for m in re.finditer(r"/lt645/[A-Za-z0-9_]+\.do", t)})
note("2 result", page, r.status_code, "final", r.url, "len", len(t), "| 주소:", eps)
calls = sorted({re.sub(r"\s+", " ", t[max(0, m.start() - 150): m.start() + 120]) for m in re.finditer(r"WnList|WnInfo|WnResult", t)})
note("3 호출 코드:", " || ".join(calls)[:3000])
pick = next((x for x in eps if re.search(r"WnList", x)), None) or next((x for x in eps if re.search(r"List", x)), None)
if pick:
    time.sleep(random.uniform(3.0, 5.0))
    r = s.get("https://www.dhlottery.co.kr" + pick, headers=dict(ajax, Referer=r.url), timeout=60, verify=False)
    note("4", pick, r.status_code, r.headers.get("Content-Type"), "len", len(r.text))
    try:
        d = r.json()
        data = d.get("data")
        lst = (data.get("result") or data.get("list")) if isinstance(data, dict) else data
        if isinstance(lst, list) and lst:
            note("5 개수", len(lst), "| 첫 행:", json.dumps(lst[0], ensure_ascii=False)[:1500])
            note("6 끝 행:", json.dumps(lst[-1], ensure_ascii=False)[:1500])
        else:
            note("5 응답:", json.dumps(d, ensure_ascii=False)[:2500])
    except ValueError:
        note("5 JSON 아님:", re.sub(r"\s+", " ", r.text[:1200]))
else:
    note("4 목록 주소 못 찾음 — 더 요청하지 않음")
