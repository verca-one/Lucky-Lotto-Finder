"""
로또 당첨지점 크롤링 (최신 회차만)
최신 회차를 감지해서 그 회차만 수집
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
LOTTO_INFO_URL = "https://www.dhlottery.co.kr/tt645/result"

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

def get_latest_round():
    """최신 로또 회차 감지"""
    try:
        response = requests.get(LOTTO_INFO_URL, timeout=10)
        response.encoding = 'utf-8'
        soup = BeautifulSoup(response.content, 'html.parser')

        # HTML에서 회차 번호 찾기
        text = soup.get_text()

        # "1220회" 형식으로 찾기
        import re
        matches = re.findall(r'(\d{4})회', text)

        if matches:
            latest_round = max(int(m) for m in matches)
            print(f"🔍 최신 회차 감지: {latest_round}회")
            return latest_round

    except Exception as e:
        print(f"❌ 최신 회차 감지 실패: {e}")

    return None

def get_stored_latest_round(db):
    """Firestore에서 저장된 최신 회차 조회"""
    try:
        if not db:
            return None

        stores_ref = db.collection('stores')
        query = stores_ref.where('lottery_type', '==', 'lotto').order_by('round', direction=firestore.Query.DESCENDING).limit(1)
        docs = list(query.stream())

        if docs:
            latest = docs[0].get('round')
            print(f"💾 저장된 최신 회차: {latest}회")
            return latest

    except Exception as e:
        print(f"⚠️ Firestore 조회 실패: {e}")

    return None

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

def fetch_lotto_stores(round_num):
    """로또 당첨지점 크롤링"""
    try:
        url = f"{BASE_URL}?method=viewResult&drwNo={round_num}&gameName=LO"
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

def save_to_firebase(db, round_num, stores):
    """Firestore에 데이터 저장 (새 회차 추가)"""
    if not db:
        return

    try:
        batch = db.batch()

        # 새 데이터만 추가 (기존 데이터는 보존)
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
        print(f"✅ Firebase 저장: {round_num}회 {len(stores)}개 지점 (누적 저장)")

    except Exception as e:
        print(f"❌ Firebase 저장 실패: {e}")

def main():
    """메인 크롤링 함수"""
    print("🎰 로또 당첨지점 크롤링 (최신 회차만)")
    print("=" * 70)

    db = init_firebase()

    # 최신 회차 감지
    latest_round = get_latest_round()
    if not latest_round:
        print("❌ 최신 회차를 감지할 수 없습니다")
        return

    # 저장된 최신 회차 확인
    stored_round = get_stored_latest_round(db)

    # 새 회차가 있는지 확인
    if stored_round and latest_round <= stored_round:
        print(f"ℹ️  이미 {stored_round}회까지 저장되었습니다")
        print(f"   새로운 회차가 없으므로 스킵합니다")
        return

    # 최신 회차만 크롤링
    print(f"\n📊 {latest_round}회 당첨지점 크롤링 중...")
    stores = fetch_lotto_stores(latest_round)

    if stores:
        print(f"✅ {len(stores)}개 지점 발견")
        save_to_firebase(db, latest_round, stores)

        # JSON 파일로도 저장
        output_file = "lotto_stores_latest.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump([{
                "lottery_type": "lotto",
                "round": latest_round,
                "rank": s['rank'],
                "store_name": s['store_name'],
                "address": s['address'],
                "method": s['method'],
                "region": extract_region(s['address']),
                "crawled_at": datetime.now().isoformat()
            } for s in stores], f, ensure_ascii=False, indent=2)

        print(f"✅ 크롤링 완료!")
    else:
        print(f"⚠️  {latest_round}회 데이터를 찾을 수 없습니다")

if __name__ == "__main__":
    main()
