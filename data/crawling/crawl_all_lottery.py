"""
로또 + 연금복권 통합 크롤링 스크립트
로또: 1220회 (1등, 2등)
연금복권: 1~312회 (1등, 2등)
"""

import requests
import json
from bs4 import BeautifulSoup
import time
from datetime import datetime

# 연금복권 공식사이트 API
PENSION_BASE_URL = "https://www.dhlottery.co.kr/gameResult.do"
LOTTO_BASE_URL = "https://www.dhlottery.co.kr/gameResult.do"

def normalize_method(method_text):
    """판매 방법 정규화 (자동, 수동, 반자동)"""
    if not method_text:
        return "미정"

    method_text = method_text.strip().lower()

    if "자동" in method_text and "반" not in method_text:
        return "자동"
    elif "반" in method_text and "자동" in method_text:
        return "반자동"
    elif "수동" in method_text:
        return "수동"
    else:
        return method_text

def extract_region(address):
    """주소에서 지역 추출"""
    if not address:
        return ""

    regions = ['서울', '부산', '대구', '인천', '광주', '대전', '울산',
               '경기', '강원', '충북', '충남', '전북', '전남', '경북', '경남', '제주']

    for region in regions:
        if region in address:
            return region

    return address.split()[0] if address else ""

def fetch_lotto_stores(round_num):
    """로또 당첨지점 크롤링"""
    try:
        url = f"{LOTTO_BASE_URL}?method=viewResult&drwNo={round_num}&gameName=LO"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }

        response = requests.get(url, headers=headers, timeout=10)
        response.encoding = 'utf-8'

        if response.status_code != 200:
            return None

        soup = BeautifulSoup(response.content, 'html.parser')
        stores = []

        # 1등 당첨지점
        rank1_section = soup.find('div', {'class': 'box_2nd'})
        if rank1_section:
            rows = rank1_section.find_all('tr')
            for row in rows[1:]:
                cols = row.find_all('td')
                if len(cols) >= 3:
                    store_name = cols[0].text.strip()
                    address = cols[1].text.strip()
                    method = cols[2].text.strip()

                    if store_name:
                        stores.append({
                            'rank': 1,
                            'store_name': store_name,
                            'address': address,
                            'method': normalize_method(method)
                        })

        # 2등 당첨지점
        rank2_section = soup.find('div', {'class': 'box_3rd'})
        if rank2_section:
            rows = rank2_section.find_all('tr')
            for row in rows[1:]:
                cols = row.find_all('td')
                if len(cols) >= 3:
                    store_name = cols[0].text.strip()
                    address = cols[1].text.strip()
                    method = cols[2].text.strip()

                    if store_name:
                        stores.append({
                            'rank': 2,
                            'store_name': store_name,
                            'address': address,
                            'method': normalize_method(method)
                        })

        return stores if stores else None

    except Exception as e:
        print(f"❌ 로또 {round_num}회 크롤링 실패: {e}")
        return None

def fetch_pension_stores(round_num):
    """연금복권 당첨지점 크롤링"""
    try:
        url = f"{PENSION_BASE_URL}?method=viewResult&drwNo={round_num}&gameName=PEN"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }

        response = requests.get(url, headers=headers, timeout=10)
        response.encoding = 'utf-8'

        if response.status_code != 200:
            return None

        soup = BeautifulSoup(response.content, 'html.parser')
        stores = []

        # 1등 당첨지점
        rank1_section = soup.find('div', {'class': 'box_2nd'})
        if rank1_section:
            rows = rank1_section.find_all('tr')
            for row in rows[1:]:
                cols = row.find_all('td')
                if len(cols) >= 3:
                    store_name = cols[0].text.strip()
                    address = cols[1].text.strip()
                    method = cols[2].text.strip()

                    if store_name:
                        stores.append({
                            'rank': 1,
                            'store_name': store_name,
                            'address': address,
                            'method': normalize_method(method)
                        })

        # 2등 당첨지점
        rank2_section = soup.find('div', {'class': 'box_3rd'})
        if rank2_section:
            rows = rank2_section.find_all('tr')
            for row in rows[1:]:
                cols = row.find_all('td')
                if len(cols) >= 3:
                    store_name = cols[0].text.strip()
                    address = cols[1].text.strip()
                    method = cols[2].text.strip()

                    if store_name:
                        stores.append({
                            'rank': 2,
                            'store_name': store_name,
                            'address': address,
                            'method': normalize_method(method)
                        })

        return stores if stores else None

    except Exception as e:
        print(f"❌ 연금복권 {round_num}회 크롤링 실패: {e}")
        return None

def save_progress(all_stores, last_type, last_round):
    """중간 진행 상황 저장"""
    progress_file = "crawl_progress.json"
    with open(progress_file, 'w', encoding='utf-8') as f:
        json.dump({
            "last_lottery_type": last_type,
            "last_round": last_round,
            "total_stores": len(all_stores),
            "data": all_stores,
            "saved_at": datetime.now().isoformat()
        }, f, ensure_ascii=False, indent=2)

def load_progress():
    """이전 진행 상황 불러오기"""
    progress_file = "crawl_progress.json"
    try:
        with open(progress_file, 'r', encoding='utf-8') as f:
            progress = json.load(f)
            return progress.get("data", []), progress.get("last_lottery_type"), progress.get("last_round", 0)
    except FileNotFoundError:
        return [], None, 0

def main():
    """메인 크롤링 함수"""
    # 이전 진행 상황 불러오기
    all_stores, last_type, last_round = load_progress()

    if last_type and last_round > 0:
        print(f"📂 이전 진행 상황 복원")
        print(f"   마지막: {last_type} {last_round}회")
        print(f"   수집된 지점: {len(all_stores)}개")

        if last_type == "lotto":
            start_lotto = last_round + 1
            start_pension = 1
        else:  # pension
            start_lotto = 1220
            start_pension = last_round + 1
    else:
        print("🔄 새로운 크롤링 시작")
        start_lotto = 1220
        start_pension = 1

    print("\n" + "=" * 70)
    print("🎰 로또 크롤링")
    print("=" * 70)

    # 로또 크롤링 (1220회만)
    for round_num in range(start_lotto, 1221):
        stores = fetch_lotto_stores(round_num)

        if stores:
            for store in stores:
                all_stores.append({
                    "lottery_type": "lotto",
                    "round": round_num,
                    "rank": store['rank'],
                    "numbers": [],
                    "store_name": store['store_name'],
                    "address": store['address'],
                    "method": store['method'],
                    "region": extract_region(store['address']),
                    "lat": None,
                    "lng": None,
                    "crawled_at": datetime.now().isoformat()
                })

            print(f"✅ 로또 {round_num}회: {len(stores)}개 지점")
        else:
            print(f"⏭️  로또 {round_num}회: 데이터 없음")

        # 매 10회차마다 중간 저장
        if round_num % 10 == 0:
            save_progress(all_stores, "lotto", round_num)
            print(f"   💾 중간 저장 ({len(all_stores)}개)")

        time.sleep(0.5)

    print("\n" + "=" * 70)
    print("💰 연금복권 크롤링")
    print("=" * 70)

    # 연금복권 크롤링 (1~312회)
    for round_num in range(start_pension, 313):
        stores = fetch_pension_stores(round_num)

        if stores:
            for store in stores:
                all_stores.append({
                    "lottery_type": "pension",
                    "round": round_num,
                    "rank": store['rank'],
                    "numbers": [],
                    "store_name": store['store_name'],
                    "address": store['address'],
                    "method": store['method'],
                    "region": extract_region(store['address']),
                    "lat": None,
                    "lng": None,
                    "crawled_at": datetime.now().isoformat()
                })

            print(f"✅ 연금복권 {round_num}회: {len(stores)}개 지점")
        else:
            print(f"⏭️  연금복권 {round_num}회: 데이터 없음")

        # 매 20회차마다 중간 저장
        if round_num % 20 == 0:
            save_progress(all_stores, "pension", round_num)
            print(f"   💾 중간 저장 ({len(all_stores)}개)")

        time.sleep(0.5)

    # 최종 JSON 파일로 저장
    output_file = "crawled_stores.json"
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(all_stores, f, ensure_ascii=False, indent=2)

    print("\n" + "=" * 70)
    print("✅ 크롤링 완료!")
    print("=" * 70)
    print(f"📊 총 {len(all_stores)}개 지점")

    # 통계
    lotto_count = len([s for s in all_stores if s['lottery_type'] == 'lotto'])
    pension_count = len([s for s in all_stores if s['lottery_type'] == 'pension'])

    rank1_count = len([s for s in all_stores if s['rank'] == 1])
    rank2_count = len([s for s in all_stores if s['rank'] == 2])

    auto_count = len([s for s in all_stores if s['method'] == '자동'])
    semi_auto_count = len([s for s in all_stores if s['method'] == '반자동'])
    manual_count = len([s for s in all_stores if s['method'] == '수동'])

    print(f"\n🎰 로또/💰 연금복권:")
    print(f"   - 로또: {lotto_count}개")
    print(f"   - 연금복권: {pension_count}개")

    print(f"\n🏅 등급별:")
    print(f"   - 1등: {rank1_count}개")
    print(f"   - 2등: {rank2_count}개")

    print(f"\n🔧 판매 방법별:")
    print(f"   - 자동: {auto_count}개")
    print(f"   - 반자동: {semi_auto_count}개")
    print(f"   - 수동: {manual_count}개")

    print(f"\n📁 저장 위치: {output_file}")

    # 진행 파일 삭제 (완료)
    try:
        import os
        os.remove("crawl_progress.json")
        print("🗑️  진행 파일 삭제 완료")
    except:
        pass

if __name__ == "__main__":
    main()
