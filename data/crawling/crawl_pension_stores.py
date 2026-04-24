"""
연금복권 공식사이트에서 당첨지점 크롤링 (1등, 2등)
회차 1~312
"""

import requests
import json
from bs4 import BeautifulSoup
import time

# 연금복권 공식사이트 API
BASE_URL = "https://www.dhlottery.co.kr/gameResult.do"

def fetch_pension_stores(round_num):
    """특정 회차의 연금복권 당첨지점 크롤링"""
    try:
        # 연금복권 당첨지점 조회
        url = f"{BASE_URL}?method=viewResult&drwNo={round_num}&gameName=PEN"

        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }

        response = requests.get(url, headers=headers, timeout=10)
        response.encoding = 'utf-8'

        if response.status_code != 200:
            return None

        soup = BeautifulSoup(response.content, 'html.parser')

        # 당첨지점 테이블 찾기
        stores = []

        # 1등 당첨지점
        rank1_section = soup.find('div', {'class': 'box_2nd'})
        if rank1_section:
            rows = rank1_section.find_all('tr')
            for row in rows[1:]:  # 헤더 제외
                cols = row.find_all('td')
                if len(cols) >= 3:
                    store_name = cols[0].text.strip()
                    address = cols[1].text.strip()
                    method = cols[2].text.strip()

                    if store_name:
                        # 방법 정규화 (자동, 수동, 반자동)
                        method = normalize_method(method)

                        stores.append({
                            'rank': 1,
                            'store_name': store_name,
                            'address': address,
                            'method': method
                        })

        # 2등 당첨지점
        rank2_section = soup.find('div', {'class': 'box_3rd'})
        if rank2_section:
            rows = rank2_section.find_all('tr')
            for row in rows[1:]:  # 헤더 제외
                cols = row.find_all('td')
                if len(cols) >= 3:
                    store_name = cols[0].text.strip()
                    address = cols[1].text.strip()
                    method = cols[2].text.strip()

                    if store_name:
                        # 방법 정규화
                        method = normalize_method(method)

                        stores.append({
                            'rank': 2,
                            'store_name': store_name,
                            'address': address,
                            'method': method
                        })

        return stores if stores else None

    except Exception as e:
        print(f"❌ {round_num}회 크롤링 실패: {e}")
        return None

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

def save_progress(all_stores, round_num):
    """중간 진행 상황 저장"""
    progress_file = "pension_stores_progress.json"
    with open(progress_file, 'w', encoding='utf-8') as f:
        json.dump({
            "last_round": round_num,
            "total_stores": len(all_stores),
            "data": all_stores,
            "saved_at": time.strftime('%Y-%m-%dT%H:%M:%S')
        }, f, ensure_ascii=False, indent=2)

def load_progress():
    """이전 진행 상황 불러오기"""
    progress_file = "pension_stores_progress.json"
    try:
        with open(progress_file, 'r', encoding='utf-8') as f:
            progress = json.load(f)
            return progress.get("data", []), progress.get("last_round", 0)
    except FileNotFoundError:
        return [], 0

def main():
    """메인 크롤링 함수"""
    # 이전 진행 상황 불러오기
    all_stores, last_round = load_progress()

    if last_round > 0:
        print(f"📂 이전 진행 상황 복원 (마지막: {last_round}회, {len(all_stores)}개)")
        start_round = last_round + 1
    else:
        print("🔄 새로운 크롤링 시작")
        start_round = 1

    print("🔄 연금복권 당첨지점 크롤링 시작 ({0}~312회)".format(start_round))
    print("=" * 70)

    for round_num in range(start_round, 313):
        stores = fetch_pension_stores(round_num)

        if stores:
            for store in stores:
                all_stores.append({
                    "lottery_type": "pension",
                    "round": round_num,
                    "rank": store['rank'],
                    "store_name": store['store_name'],
                    "address": store['address'],
                    "method": store['method'],
                    "region": extract_region(store['address']),
                    "lat": None,  # 주소로부터 좌표 추출 필요
                    "lng": None,
                    "crawled_at": time.strftime('%Y-%m-%dT%H:%M:%S')
                })

            print(f"✅ {round_num}회: {len(stores)}개 지점")
        else:
            print(f"⏭️  {round_num}회: 데이터 없음")

        # 매 10회차마다 중간 저장
        if round_num % 10 == 0:
            save_progress(all_stores, round_num)
            print(f"   💾 중간 저장 ({round_num}회까지 {len(all_stores)}개)")

        time.sleep(0.5)  # 요청 간격

    # 최종 JSON 파일로 저장
    output_file = "pension_stores_crawled.json"
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(all_stores, f, ensure_ascii=False, indent=2)

    print("\n" + "=" * 70)
    print(f"✅ 크롤링 완료!")
    print(f"   총 {len(all_stores)}개 지점")
    print(f"   저장 위치: {output_file}")

    # 통계
    rank1_count = len([s for s in all_stores if s['rank'] == 1])
    rank2_count = len([s for s in all_stores if s['rank'] == 2])
    auto_count = len([s for s in all_stores if s['method'] == '자동'])
    semi_auto_count = len([s for s in all_stores if s['method'] == '반자동'])
    manual_count = len([s for s in all_stores if s['method'] == '수동'])

    print(f"   - 1등: {rank1_count}개")
    print(f"   - 2등: {rank2_count}개")
    print(f"\n   판매 방법:")
    print(f"   - 자동: {auto_count}개")
    print(f"   - 반자동: {semi_auto_count}개")
    print(f"   - 수동: {manual_count}개")

    # 진행 파일 삭제 (완료)
    try:
        import os
        os.remove("pension_stores_progress.json")
    except:
        pass

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

if __name__ == "__main__":
    main()
