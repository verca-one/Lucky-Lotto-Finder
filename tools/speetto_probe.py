"""
동행복권 응답 형식 확인 (1회용 · 서버 전용) — 기존 크롤러가 쓰는 같은 주소·헤더로 최소 요청만 한다.
  2026-10-23 1차: 스피또 당첨지점 형식 확인 (완료 — 회차 = ltEpsd)
  2026-10-24 2차: 연금 당첨판매점 응답엔 당첨번호 없음 · 예전 win720 주소는 오류 페이지 (완료)
  2026-10-24 4차: 결과 화면에서 내부 주소 발견 (selectPstPt720WnList.do 등) → 목록 1번 직접 확인
  2026-10-24 3차: 새 사이트의 연금 결과 주소 찾기 — 요청 3~4번
    1~2) 세션 워밍업 (기존 크롤러와 같음) — 첫 화면 HTML 에서 720·연금 관련 링크 추출 (추가 요청 없음)
    3) 연금 결과 화면 /pt720/result (사용자 제공) 1번  4) 그 화면 전용 스크립트 1번 — 당첨번호를 부르는 내부 주소
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
# 1) 첫 화면 (쿠키)  2) 연금 결과 화면 (Referer)  3) 당첨 목록 내부 주소 1번 — 주석은 단계당 10줄 제한이라 8줄 안으로
r = s.get("https://www.dhlottery.co.kr/common.do?method=main", headers=html, timeout=30, verify=False)
time.sleep(random.uniform(2.0, 3.5))
r2 = s.get("https://www.dhlottery.co.kr/pt720/result", headers=html, timeout=60, verify=False)
t = r2.text
calls = sorted({re.sub(r"\s+", " ", t[max(0, m.start() - 160): m.start() + 120]) for m in re.finditer(r"selectPstPt720WnList|selectPstPt720WnInfo", t)})
print("1 main", r.status_code, "result", r2.status_code, "| 호출 코드:", " || ".join(calls)[:3000])
time.sleep(random.uniform(3.0, 5.0))
r3 = s.get("https://www.dhlottery.co.kr/pt720/selectPstPt720WnList.do", timeout=60, verify=False,
           headers=dict(ajax, Referer="https://www.dhlottery.co.kr/pt720/result"))
print("2 WnList", r3.status_code, r3.headers.get("Content-Type"), "len", len(r3.text))
try:
    d = r3.json()
    data = d.get("data")
    print("3 keys", list(d.keys()), "| data:", type(data).__name__, list(data.keys()) if isinstance(data, dict) else (len(data) if isinstance(data, list) else ""))
    lst = data.get("list") if isinstance(data, dict) else data
    if isinstance(lst, list) and lst:
        print("4 개수", len(lst), "| 첫 행:", json.dumps(lst[0], ensure_ascii=False)[:1500])
        print("5 끝 행:", json.dumps(lst[-1], ensure_ascii=False)[:1500])
    else:
        print("4 응답:", json.dumps(d, ensure_ascii=False)[:2500])
except ValueError:
    print("3 JSON 아님:", re.sub(r"\s+", " ", r3.text[:1500]))
