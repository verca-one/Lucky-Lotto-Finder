"""
연금복권 당첨지점 크롤링 (최근 10회차)
지정된 날짜에 자동으로 당첨지점만 수집
"""

import requests
import json
from bs4 import BeautifulSoup
import time
from datetime import datetime

BASE_URL = "https://www.dhlottery.co.kr/gameResult.do"

def normalize_method(method_text):
    """판매 방법 정규화"""
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

def fetch_pension_stores(round_num):
    """연금복권 당첨지점 크롤링"""
    try:
        url = f"{BASE_URL}?method=viewResult&drwNo={round_num}&gameName=PEN"

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

def main():
    """메인 크롤링 함수"""
    print("💰 연금복권 당첨지점 크롤링 (최근 10회차)")
    print("=" * 70)

    all_stores = []

    # 최근 10개 회차 크롤링 (312회가 최신이라고 가정)
    for round_num in range(312, 302, -1):
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
                    "lat": None,
                    "lng": None,
                    "crawled_at": datetime.now().isoformat()
                })

            print(f"✅ 연금복권 {round_num}회: {len(stores)}개 지점")
        else:
            print(f"⏭️  연금복권 {round_num}회: 데이터 없음")

        time.sleep(0.5)  # 서버 부담 방지

    # 최종 JSON 파일로 저장
    output_file = "pension_stores_recent.json"
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(all_stores, f, ensure_ascii=False, indent=2)

    print("\n" + "=" * 70)
    print(f"✅ 크롤링 완료!")
    print(f"   총 {len(all_stores)}개 지점")
    print(f"   저장: {output_file}")

if __name__ == "__main__":
    main()
