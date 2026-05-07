"""
스피또A 당첨지점 크롤링 (전 회차)
"""

import requests
import json
from bs4 import BeautifulSoup
import time
from datetime import datetime
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import os

BASE_URL = "https://www.dhlottery.co.kr/gameResult.do"

def init_firebase():
    """Firebase 초기화"""
    creds_json = os.getenv('FIREBASE_CREDENTIALS')
    project_id = os.getenv('FIREBASE_PROJECT_ID')

    if not creds_json or not project_id:
        print("⚠️ Firebase 환경변수 없음 - 로컬 테스트 모드")
        return None

    try:
        creds_file = '/tmp/firebase_creds.json'
        with open(creds_file, 'w') as f:
            f.write(creds_json)

        cred = credentials.Certificate(creds_file)
        firebase_admin.initialize_app(cred, {'projectId': project_id})
        return firestore.client()
    except Exception as e:
        print(f"⚠️ Firebase 초기화 실패: {e}")
        return None

def normalize_method(method_text):
    """판매 방법 정규화"""
    if not method_text:
        return "없음"

    method_text = method_text.strip().lower()

    if "자동" in method_text and "반" not in method_text:
        return "자동"
    elif "반" in method_text and "자동" in method_text:
        return "반자동"
    elif "수동" in method_text:
        return "수동"
    else:
        return "없음"

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

def fetch_speeto_a_stores(round_num):
    """스피또A 당첨지점 크롤링"""
    try:
        url = f"{BASE_URL}?method=viewResult&drwNo={round_num}&gameName=SPTA"
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
                        region = extract_region(address)
                        store_id = f"speeto_a_{region}_{store_name}_{address.split()[0]}"

                        stores.append({
                            'rank': 1,
                            'store_id': store_id,
                            'store_name': store_name,
                            'address': address,
                            'method': normalize_method(method),
                            'region': region,
                            'naver_map_url': f"https://map.naver.com/v5/search/{store_name}",
                            'kakao_map_url': f"https://map.kakao.com/link/search/{store_name}"
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
                        region = extract_region(address)
                        store_id = f"speeto_a_{region}_{store_name}_{address.split()[0]}"

                        stores.append({
                            'rank': 2,
                            'store_id': store_id,
                            'store_name': store_name,
                            'address': address,
                            'method': normalize_method(method),
                            'region': region,
                            'naver_map_url': f"https://map.naver.com/v5/search/{store_name}",
                            'kakao_map_url': f"https://map.kakao.com/link/search/{store_name}"
                        })

        return stores if stores else None

    except Exception as e:
        print(f"❌ 스피또A {round_num}회 크롤링 실패: {e}")
        return None

def save_to_firebase(db, round_num, stores):
    """Firestore에 데이터 저장"""
    if not db:
        return

    try:
        batch = db.batch()

        for store in stores:
            doc_id = f"speeto_a_{round_num}_{store['store_name']}"
            doc_ref = db.collection('stores').document(doc_id)
            batch.set(doc_ref, {
                "lottery_type": "speeto_a",
                "round": round_num,
                "rank": store['rank'],
                "store_id": store['store_id'],
                "store_name": store['store_name'],
                "address": store['address'],
                "method": store['method'],
                "region": store['region'],
                "naver_map_url": store['naver_map_url'],
                "kakao_map_url": store['kakao_map_url'],
                "lat": None,
                "lng": None,
                "crawled_at": datetime.now().isoformat()
            }, merge=True)

        batch.commit()
        print(f"✅ Firebase 저장: {round_num}회 {len(stores)}개 지점")

    except Exception as e:
        print(f"❌ Firebase 저장 실패: {e}")

def main():
    """메인 크롤링 함수 (전 회차 수집)"""
    print("✨ 스피또A 당첨지점 크롤링 (전 회차 베이스 자료 구축)")
    print("=" * 70)

    db = init_firebase()

    START_ROUND = 1
    END_ROUND = 67

    print(f"\n📋 {START_ROUND}회 ~ {END_ROUND}회 수집 시작\n")

    all_stores = []
    success_count = 0
    fail_count = 0

    for round_num in range(END_ROUND, START_ROUND - 1, -1):
        print(f"📊 [{END_ROUND - round_num + 1}/{END_ROUND}] 스피또A {round_num}회 크롤링 중...", end=" ")

        stores = fetch_speeto_a_stores(round_num)

        if stores:
            print(f"✅ {len(stores)}개 지점")
            save_to_firebase(db, round_num, stores)
            all_stores.extend([{
                "lottery_type": "speeto_a",
                "round": round_num,
                "rank": s['rank'],
                "store_id": s['store_id'],
                "store_name": s['store_name'],
                "address": s['address'],
                "method": s['method'],
                "region": s['region'],
                "naver_map_url": s['naver_map_url'],
                "kakao_map_url": s['kakao_map_url'],
                "crawled_at": datetime.now().isoformat()
            } for s in stores])
            success_count += 1
        else:
            print(f"⚠️  데이터 없음")
            fail_count += 1

        time.sleep(0.5)

    if all_stores:
        output_file = "base_speeto_a_stores_latest.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(all_stores, f, ensure_ascii=False, indent=2)

    print("\n" + "=" * 70)
    print(f"✅ 크롤링 완료!")
    print(f"   성공: {success_count}회차 / 실패: {fail_count}회차")
    print(f"   총 {len(all_stores)}개 지점 수집")

if __name__ == "__main__":
    main()
