"""
크롤링한 데이터를 Firebase Firestore에 업로드
"""

import json
import os
from datetime import datetime
import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

def init_firebase():
    """Firebase 초기화"""
    # 환경변수에서 Firebase 자격증명 가져오기
    creds_json = os.getenv('FIREBASE_CREDENTIALS')
    project_id = os.getenv('FIREBASE_PROJECT_ID')

    if not creds_json or not project_id:
        print("❌ Firebase 환경변수 미설정")
        return None

    # JSON 문자열을 파일로 저장 후 로드
    creds_file = '/tmp/firebase_creds.json'
    with open(creds_file, 'w') as f:
        f.write(creds_json)

    cred = credentials.Certificate(creds_file)
    firebase_admin.initialize_app(cred, {
        'projectId': project_id
    })

    return firestore.client()

def upload_lotto_numbers(db):
    """로또 당첨번호 업로드"""
    try:
        with open('lotto_numbers_crawled.json', 'r', encoding='utf-8') as f:
            numbers_data = json.load(f)

        if not numbers_data:
            print("⚠️  로또번호 데이터 없음")
            return

        for data in numbers_data:
            round_num = data['round']
            doc_ref = db.collection('lotto_records').document(f'round_{round_num}')
            doc_ref.set({
                'round': round_num,
                'numbers': data['numbers'],
                'bonus': data['bonus'],
                'lottery_type': 'lotto',
                'crawled_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat()
            }, merge=True)

            print(f"✅ 로또 {round_num}회 업로드 완료")

    except FileNotFoundError:
        print("⚠️  로또번호 파일 없음")
    except Exception as e:
        print(f"❌ 로또번호 업로드 실패: {e}")

def upload_stores(db):
    """당첨지점 업로드"""
    try:
        with open('crawled_stores.json', 'r', encoding='utf-8') as f:
            stores_data = json.load(f)

        if not stores_data:
            print("⚠️  당첨지점 데이터 없음")
            return

        batch = db.batch()
        count = 0

        for store in stores_data:
            lottery_type = store.get('lottery_type', 'lotto')
            round_num = store.get('round', 0)
            doc_id = f"{lottery_type}_{round_num}_{store['store_name']}"

            doc_ref = db.collection('stores').document(doc_id)
            batch.set(doc_ref, {
                'lottery_type': lottery_type,
                'round': round_num,
                'rank': store.get('rank'),
                'store_name': store.get('store_name'),
                'address': store.get('address'),
                'method': store.get('method'),
                'region': store.get('region'),
                'lat': store.get('lat'),
                'lng': store.get('lng'),
                'crawled_at': datetime.now().isoformat()
            }, merge=True)

            count += 1
            if count % 100 == 0:
                batch.commit()
                batch = db.batch()

        # 남은 데이터 커밋
        if count % 100 != 0:
            batch.commit()

        print(f"✅ 당첨지점 {count}개 업로드 완료")

    except FileNotFoundError:
        print("⚠️  당첨지점 파일 없음")
    except Exception as e:
        print(f"❌ 당첨지점 업로드 실패: {e}")

def main():
    """메인 업로드 함수"""
    print("🔄 Firebase 데이터 업로드 시작")
    print("=" * 70)

    db = init_firebase()
    if not db:
        print("❌ Firebase 초기화 실패")
        return

    upload_lotto_numbers(db)
    upload_stores(db)

    print("\n" + "=" * 70)
    print("✅ Firebase 업로드 완료!")

if __name__ == "__main__":
    main()
