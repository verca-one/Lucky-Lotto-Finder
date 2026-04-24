"""
동행복권 당첨 판매점 크롤러
- 로또6/45, 연금복권720+
- 매주 최신 회차 당첨 판매점 정보 수집
- 중간 저장 기능 추가
"""

import requests
import json
import time
import random
import os
from datetime import datetime

SESSION = requests.Session()
SESSION.headers.update({
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Referer": "https://www.dhlottery.co.kr/wnprchsplcsrch/home",
    "Accept": "application/json, text/javascript, */*; q=0.01",
    "X-Requested-With": "XMLHttpRequest",
})

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Referer": "https://www.dhlottery.co.kr/wnprchsplcsrch/home",
    "Accept": "application/json, text/javascript, */*; q=0.01",
    "X-Requested-With": "XMLHttpRequest",
}

LOTTERY_TYPES = [
    {"type": "lotto", "param": "L645"},
    {"type": "pension", "param": "P720"},
    {"type": "speeto", "param": "S505"},  # 스피또 추가
]

SAVE_INTERVAL = 10  # 10회차마다 중간 저장 (더 자주 저장)
OUTPUT_FILE = "winner_stores.json"  # 최종 결과물
PROGRESS_FILE = "crawl_progress.json"  # 진행 상황 저장


def get_latest_round() -> int:
    import datetime as dt
    first_date = dt.date(2002, 12, 7)
    today = dt.date.today()
    weeks = (today - first_date).days // 7
    return weeks + 1


def load_progress() -> tuple[int, list]:
    """이전 진행 상황 불러오기"""
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, encoding="utf-8") as f:
            data = json.load(f)
            print(f"이전 진행 상황 발견: {data['last_round']}회차까지 완료")
            return data["last_round"], data["stores"]
    return 0, []


def get_lottery_numbers(round_no: int, lottery_type: str) -> list[int]:
    """동행복권에서 당첨번호 가져오기
    - lotto: 로또 6/45 당첨번호 (6개)
    - pension: 연금복권 당첨번호 (10개)
    - speeto: 스피또 당첨번호 (5개)
    """
    try:
        if lottery_type == "lotto":
            # 로또 당첨번호 API
            url = f"https://www.dhlottery.co.kr/common/statistic/getWinNumber.do?method=getTotalWinNumber&drwNo={round_no}"
            res = SESSION.get(url, timeout=10)
            data = res.json()

            if "returnValue" in data and data["returnValue"]:
                # drwtNo1~6: 당첨번호
                numbers = [
                    data.get("drwtNo1"),
                    data.get("drwtNo2"),
                    data.get("drwtNo3"),
                    data.get("drwtNo4"),
                    data.get("drwtNo5"),
                    data.get("drwtNo6"),
                ]
                return [n for n in numbers if n is not None]

        elif lottery_type == "pension":
            # 연금복권 당첨번호 API
            url = f"https://www.dhlottery.co.kr/common/statistic/getPensionWinNumber.do?drwNo={round_no}"
            res = SESSION.get(url, timeout=10)
            data = res.json()

            if "returnValue" in data and data["returnValue"]:
                # 연금복권은 선택번호 10개
                numbers = []
                for i in range(1, 11):
                    num = data.get(f"selcNum{i}")
                    if num is not None:
                        numbers.append(num)
                return numbers

        elif lottery_type == "speeto":
            # 스피또 당첨번호 API
            url = f"https://www.dhlottery.co.kr/common/statistic/getSpeetoWinNumber.do?drwNo={round_no}"
            res = SESSION.get(url, timeout=10)
            data = res.json()

            if "returnValue" in data and data["returnValue"]:
                # 스피또는 5개 번호
                numbers = [
                    data.get("num1"),
                    data.get("num2"),
                    data.get("num3"),
                    data.get("num4"),
                    data.get("num5"),
                ]
                return [n for n in numbers if n is not None]

    except Exception as e:
        print(f"    [경고] 당첨번호 조회 실패 ({lottery_type} {round_no}회): {e}")

    return []


def save_progress(last_round: int, stores: list):
    """진행 상황 저장"""
    with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
        json.dump({"last_round": last_round, "stores": stores}, f, ensure_ascii=False)


def crawl_winner_stores(round_no: int, lottery_type: str, lottery_param: str) -> list[dict]:
    url = (
        f"https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
        f"?srchWnShpRnk=all&srchLtEpsd={round_no}&srchShpLctn=&srchLtType={lottery_param}&_={int(time.time()*1000)}"
    )

    try:
        res = SESSION.get(url, timeout=10)
    except Exception as e:
        print(f"    요청 오류: {e}")
        return []

    print(f"    [DEBUG] status={res.status_code} type={res.headers.get('Content-Type', '')}")

    text_preview = res.text[:300].replace("\n", " ").replace("\r", " ")
    print(f"    [DEBUG] body={text_preview}")

    if res.status_code != 200:
        print(f"    비정상 응답 코드: {res.status_code}")
        return []

    if "서비스 접근 대기" in res.text or "서비스 접속이 차단" in res.text or "접속이 불가능합니다" in res.text:
        print("    차단/대기 페이지로 응답됨")
        return []

    try:
        data = res.json()
    except Exception as e:
        print(f"    JSON 파싱 오류: {e}")
        return []

    if isinstance(data, dict):
        print(f"    [DEBUG] json keys={list(data.keys())}")
    else:
        print(f"    [DEBUG] json type={type(data)}")

    candidates = []

    if isinstance(data, dict):
        if isinstance(data.get("data"), dict) and isinstance(data["data"].get("list"), list):
            candidates = data["data"]["list"]
        elif isinstance(data.get("list"), list):
            candidates = data["list"]
        elif isinstance(data.get("arr"), list):
            candidates = data["arr"]
        elif isinstance(data.get("rows"), list):
            candidates = data["rows"]

    print(f"    [DEBUG] candidate count={len(candidates)}")

    # 당첨번호 가져오기
    numbers = get_lottery_numbers(round_no, lottery_type)
    print(f"    [당첨번호] {lottery_type} {round_no}회: {numbers}")

    stores = []
    crawled_at = datetime.utcnow().isoformat()

    for item in candidates:
        if not isinstance(item, dict):
            continue

        rank = item.get("wnShpRnk")
        # 1등, 2등, 3등만 저장 (더 이상의 등수는 필요 없음)
        if rank is None or int(rank) > 3:
            continue

        store = {
            "lottery_type": lottery_type,
            "round": round_no,
            "rank": int(rank),  # ✅ 등수 저장 (1등, 2등, 3등 구분용)
            "numbers": numbers,  # ✅ 당첨번호 추가
            "store_name": item.get("shpNm", ""),
            "address": item.get("shpAddr", ""),
            "method": item.get("atmtPsvYnTxt", ""),
            "region": item.get("region", ""),
            "lat": item.get("shpLat"),
            "lng": item.get("shpLot"),
            "crawled_at": crawled_at,
        }
        stores.append(store)

    return stores


def crawl_multiple_rounds(start: int, end: int, existing_stores: list, reverse: bool = False) -> list[dict]:
    all_stores = existing_stores.copy()
    total_rounds = abs(end - start) + 1

    # 역순 또는 정순 결정
    if reverse:
        rounds = range(start, end - 1, -1)
        direction = "역순 (최신→과거)"
    else:
        rounds = range(start, end + 1)
        direction = "정순 (과거→최신)"

    print(f"\n{'='*60}")
    print(f"크롤링 시작: {start}~{end}회차 (총 {total_rounds}회차) [{direction}]")
    print(f"진행 상황은 {PROGRESS_FILE}에 자동 저장됩니다")
    print(f"{'='*60}\n")

    for idx, round_no in enumerate(rounds, 1):
        progress_pct = (idx / total_rounds) * 100
        print(f"[{idx}/{total_rounds}] {round_no}회차... ({progress_pct:.1f}%)")
        round_stores = []

        for lt in LOTTERY_TYPES:
            try:
                stores = crawl_winner_stores(round_no, lt["type"], lt["param"])
                round_stores.extend(stores)
            except Exception as e:
                print(f"  → {lt['type']} 오류: {e}")
            time.sleep(random.uniform(0.3, 0.7))

        all_stores.extend(round_stores)
        print(f"  ✓ {len(round_stores)}개 수집 (누적: {len(all_stores)}건)")

        # 10회차마다 중간 저장
        if round_no % SAVE_INTERVAL == 0 or round_no == end:
            save_progress(round_no, all_stores)
            with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
                json.dump(all_stores, f, ensure_ascii=False, indent=2)
            print(f"  💾 중간 저장: {round_no}회차까지 ({len(all_stores)}건)\n")

        time.sleep(random.uniform(1.0, 2.0))

    return all_stores


def save_to_json(data: list[dict], filepath: str):
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"저장 완료: {filepath} ({len(data)}건)")


if __name__ == "__main__":
    import sys

    # 커맨드라인 인자로 로또 종류 선택 (--type lotto, pension, speeto)
    lottery_type_filter = None
    if len(sys.argv) > 1 and sys.argv[1] == "--type" and len(sys.argv) > 2:
        lottery_type_filter = sys.argv[2].lower()

    print("\n🎰 동행복권 당첨점 크롤러 시작")
    print("=" * 60)

    if lottery_type_filter:
        print(f"📌 모드: {lottery_type_filter.upper()} 크롤링만 실행")

    latest = get_latest_round()
    print(f"📊 현재 최신 회차: {latest}회")

    # 이전 진행 상황 불러오기
    last_round, existing_stores = load_progress()

    if last_round > 0:
        print(f"📍 진행 상황: {last_round}회차까지 완료됨 ({len(existing_stores)}건)")
        print(f"▶️  {last_round}회차부터 역순으로 재시작합니다 (최신→과거).\n")
        stores = crawl_multiple_rounds(latest, last_round, existing_stores, reverse=True)
    else:
        print("▶️  최신 회차부터 역순으로 시작합니다 (최신→과거).\n")
        stores = crawl_multiple_rounds(latest, 1, existing_stores, reverse=True)

    # 선택된 로또 종류만 필터링
    if lottery_type_filter:
        stores = [s for s in stores if s.get("lottery_type") == lottery_type_filter]

    # 최종 저장
    save_to_json(stores, OUTPUT_FILE)

    print("=" * 60)
    print(f"✅ 크롤링 완료!")
    print(f"📁 저장 위치: {OUTPUT_FILE}")
    print(f"📊 총 수집 건수: {len(stores)}건")
    print(f"🎰 로또: {sum(1 for s in stores if s['lottery_type'] == 'lotto')}건")
    print(f"💎 연금: {sum(1 for s in stores if s['lottery_type'] == 'pension')}건")
    print(f"⭐ 스피또: {sum(1 for s in stores if s['lottery_type'] == 'speeto')}건")

    # 완료 시 progress 파일 삭제
    if os.path.exists(PROGRESS_FILE):
        os.remove(PROGRESS_FILE)
        print(f"🗑️  진행 상황 파일 삭제됨")

    print("=" * 60 + "\n")