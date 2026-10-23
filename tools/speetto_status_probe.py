"""
스피또 판매 현황(출고율 · 남은 1·2등) 주소 확인 (1회용 · 서버 전용) — 사용자가 알려 준 /st/st10Intro 출발
  1) 첫 화면(쿠키)  2) /st/st10Intro  3) 그 안의 판매 현황 내부 주소 1번 — 요청 3~4번 · DB 무관
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
time.sleep(random.uniform(2.5, 4.0))
r = s.get("https://www.dhlottery.co.kr/st/st10Intro", headers=html, timeout=60, verify=False)
t = r.text
eps = sorted({m.group(0) for m in re.finditer(r"/st/[A-Za-z0-9_]+(?:\.do)?", t)})
note("1 st10Intro", r.status_code, "final", r.url, "len", len(t), "| /st 주소:", eps[:60])
ctx = []
for kw in ("출고", "잔여", "남은"):
    i = t.find(kw)
    if i >= 0:
        ctx.append(f"[{kw}] " + re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", t[max(0, i - 300): i + 300])))
note("2 출고·잔여 주변:", " || ".join(ctx)[:3300] or "-")
calls = sorted({re.sub(r"\s+", " ", t[max(0, m.start() - 250): m.start() + 150]) for m in re.finditer(r"sendHttpJson\(", t)})
note("3 내부 호출:", " || ".join(calls)[:3300] or "-")
cand = [e for e in eps if e.endswith(".do") and re.search(r"Prgs|prgs|Sls|sls|Rmn|rmn|Rmnd|Stts|stts|Gm|Info|List", e)]
note("4 후보:", cand)
pick = next((e for e in cand if re.search(r"Prgs|Sls|Rmn|Stts", e)), None) or (cand[0] if cand else None)
if pick:
    time.sleep(random.uniform(3.0, 5.0))
    r = s.get("https://www.dhlottery.co.kr" + pick, headers=ajax, timeout=60, verify=False)
    note("5", pick, r.status_code, r.headers.get("Content-Type"), "len", len(r.text))
    try:
        note("6 응답:", json.dumps(r.json(), ensure_ascii=False)[:3300])
    except ValueError:
        note("6 JSON 아님:", re.sub(r"\s+", " ", r.text[:1500]))
else:
    note("5 후보 없음 — 더 요청하지 않음")
