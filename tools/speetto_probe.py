"""
동행복권 응답 형식 확인 (1회용 · 서버 전용) — 기존 크롤러가 쓰는 같은 주소·헤더로 최소 요청만 한다.
  2026-10-23 1차: 스피또 당첨지점 형식 확인 (완료 — 회차 = ltEpsd)
  2026-10-24 2차: 연금 당첨판매점 응답엔 당첨번호 없음 · 예전 win720 주소는 오류 페이지 (완료)
  2026-10-24 3차: 새 사이트의 연금 결과 주소 찾기 — 요청 3~4번
    1~2) 세션 워밍업 (기존 크롤러와 같음) — 첫 화면 HTML 에서 720·연금 관련 링크 추출 (추가 요청 없음)
    3) 찾은 연금 결과 페이지 1번 — 안의 .do 주소 · 스크립트 주소 · 6자리 숫자 위치
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
import re
pages = {}
for u in ("https://www.dhlottery.co.kr/common.do?method=main", "https://www.dhlottery.co.kr/wnprchsplcsrch/selectWnPrchsPlcList.do"):
    r = s.get(u, headers=html, timeout=30, verify=False)
    pages[u] = r.text
    print("warm-up", u, r.status_code, "final", r.url, "len", len(r.text))
    time.sleep(random.uniform(2.0, 3.5))

# 첫 화면 · 판매점 페이지 안의 링크 중 연금(720) 관련
links = set()
for t in pages.values():
    for m in re.finditer(r"""(?:href|src|action|url)\s*[:=]\s*["']([^"']+)["']""", t):
        links.add(m.group(1))
cand = sorted(x for x in links if re.search(r"720|pt7|pension|win720|wnNo|drwNo|Rslt|rslt|result|Result", x))
print("연금 후보 링크:", cand[:60])
menu = sorted({m.group(0) for t in pages.values() for m in re.finditer(r"/[A-Za-z0-9_/]+\.do[^\"' <>]*", t)})
print("모든 .do 주소:", menu[:150])

# 후보 중 결과 페이지로 보이는 것 1개만 연다
pick = next((x for x in cand if re.search(r"720", x) and (".do" in x or x.startswith("/"))), None)
if pick:
    url = pick if pick.startswith("http") else "https://www.dhlottery.co.kr" + pick
    time.sleep(random.uniform(3.0, 5.0))
    r = s.get(url, headers=html, timeout=60, verify=False)
    t = r.text
    print("연금 결과 페이지", url, r.status_code, "final", r.url, "len", len(t))
    print("페이지 안 .do 주소:", sorted({m.group(0) for m in re.finditer(r"/[A-Za-z0-9_/]+\.do", t)})[:80])
    print("페이지 안 스크립트:", sorted({m.group(1) for m in re.finditer(r"""<script[^>]+src=["']([^"']+)["']""", t)})[:40])
    for kw in ("조", "ltEpsd", "wnBnd", "drwNo", "Epsd", "720"):
        i = t.find(kw)
        print(f"결과 페이지 '{kw}' 위치 {i}:", re.sub(r"\s+", " ", t[max(0, i - 150): i + 350]) if i >= 0 else "-")
else:
    print("연금 결과 후보 링크 없음 — 페이지는 열지 않음")
