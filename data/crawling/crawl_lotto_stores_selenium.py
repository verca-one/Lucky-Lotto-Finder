"""
로또 당첨지점 크롤링 (Selenium - JavaScript 렌더링)
"""

import json
from bs4 import BeautifulSoup
import time
from datetime import datetime
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
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

def fetch_lotto_stores_selenium(driver, round_num):
    """Selenium으로 로또 당첨지점 크롤링"""
    try:
        url = f"{BASE_URL}?method=viewResult&drwNo={round_num}&gameName=LO"
        driver.get(url)

        # JavaScript 렌더링 대기 (최대 10초)
        time.sleep(2)

        # 페이지 소스 가져오기
        soup = BeautifulSoup(driver.page_source, 'html.parser')
        stores = []

        # 당첨지점 데이터 찾기 (새로운 구조)
        # tr 태그에서 td 찾기
        rows = soup.find_all('tr')

        if not rows:
            return None

        for row in rows:
            cols = row.find_all('td')
            if len(cols) >= 3:
                store_name = cols[0].text.strip()
                address = cols[1].text.strip() if len(cols) > 1 else ""
                method = cols[2].text.strip() if len(cols) > 2 else ""

                # 빈 값 제외
                if not store_name or not address:
                    continue

                region = extract_region(address)
                store_id = f"lotto_{region}_{store_name}_{address.split()[0] if address.split() else 'unknown'}"

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

        return stores if stores else None

    except Exception as e:
        print(f"❌ 로또 {round_num}회 크롤링 실패: {e}")
        return None

def save_to_firebase(db, round_num, stores):
    """Firestore에 데이터 저장"""
    if not db:
        return

    try:
        batch = db.batch()

        for store in stores:
            doc_id = f"lotto_{round_num}_{store['store_name']}"
            doc_ref = db.collection('stores').document(doc_id)
            batch.set(doc_ref, {
                "lottery_type": "lotto",
                "round": round_num,
                "rank": store['rank'],
                "store_name": store['store_name'],
                "address": store['address'],
                "method": store['method'],
                "region": extract_region(store['address']),
                "lat": None,
                "lng": None,
                "crawled_at": datetime.now().isoformat()
            }, merge=True)

        batch.commit()
        print(f"✅ Firebase 저장: {round_num}회 {len(stores)}개 지점")

    except Exception as e:
        print(f"❌ Firebase 저장 실패: {e}")

def main():
    """메인 크롤링 함수 (Selenium)"""
    print("🎰 로또 당첨지점 크롤링 (Selenium - JavaScript 렌더링)")
    print("=" * 70)

    db = init_firebase()

    # Chrome 옵션
    chrome_options = webdriver.ChromeOptions()
    chrome_options.add_argument('--disable-blink-features=AutomationControlled')
    chrome_options.add_argument('--disable-gpu')
    chrome_options.add_argument('--no-sandbox')

    # 헤드리스 모드 (화면 안 보임)
    chrome_options.add_argument('--headless')

    # WebDriver 초기화
    driver = webdriver.Chrome(
        options=chrome_options
    )

    try:
        START_ROUND = 1
        END_ROUND = 1221

        print(f"\n📋 {START_ROUND}회 ~ {END_ROUND}회 수집 시작\n")

        all_stores = []
        success_count = 0
        fail_count = 0

        # 최신부터 역순 크롤링
        for round_num in range(END_ROUND, START_ROUND - 1, -1):
            print(f"📊 [{END_ROUND - round_num + 1}/{END_ROUND}] 로또 {round_num}회 크롤링 중...", end=" ")

            stores = fetch_lotto_stores_selenium(driver, round_num)

            if stores:
                print(f"✅ {len(stores)}개 지점")
                save_to_firebase(db, round_num, stores)
                all_stores.extend([{
                    "lottery_type": "lotto",
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

        # 최종 JSON 저장
        if all_stores:
            output_file = "base_lotto_stores_latest.json"
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(all_stores, f, ensure_ascii=False, indent=2)

        print("\n" + "=" * 70)
        print(f"✅ 크롤링 완료!")
        print(f"   성공: {success_count}회차 / 실패: {fail_count}회차")
        print(f"   총 {len(all_stores)}개 지점 수집")

    finally:
        driver.quit()

if __name__ == "__main__":
    main()
