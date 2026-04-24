"""
로또 데이터를 Firestore에 추가
"""

import json
import firebase_admin
from firebase_admin import credentials, firestore

def init_firestore(service_account_path: str):
    cred = credentials.Certificate(service_account_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    return firestore.client()

def add_lotto_records(db):
    """로또 데이터를 Firestore에 추가"""

    # 회차별 로또 데이터
    records = [
        {"round": 1, "date": "2024-01-06", "numbers": [10, 23, 29, 33, 37, 40], "bonus": 16},
        {"round": 2, "date": "2024-01-13", "numbers": [9, 13, 21, 25, 32, 42], "bonus": 2},
        {"round": 3, "date": "2024-01-20", "numbers": [11, 16, 19, 21, 27, 31], "bonus": 30},
        {"round": 4, "date": "2024-01-27", "numbers": [14, 27, 30, 31, 40, 42], "bonus": 2},
        {"round": 5, "date": "2024-02-03", "numbers": [16, 24, 29, 40, 41, 42], "bonus": 3},
        {"round": 6, "date": "2024-02-10", "numbers": [14, 15, 26, 27, 40, 42], "bonus": 34},
        {"round": 7, "date": "2024-02-17", "numbers": [2, 9, 16, 25, 26, 40], "bonus": 42},
        {"round": 8, "date": "2024-02-24", "numbers": [8, 19, 25, 34, 37, 39], "bonus": 9},
        {"round": 9, "date": "2024-03-02", "numbers": [2, 4, 16, 17, 36, 39], "bonus": 14},
        {"round": 10, "date": "2024-03-09", "numbers": [9, 25, 30, 33, 41, 44], "bonus": 6},
    ]

    db_ref = db.collection("lotto_records")
    count = 0

    for record in records:
        try:
            db_ref.add({
                "lottery_type": "lotto",
                "round": record["round"],
                "date": record["date"],
                "numbers": record["numbers"],
                "bonus": record["bonus"],
                "createdAt": firestore.SERVER_TIMESTAMP,
            })
            count += 1
            print(f"✅ 로또 {record['round']:2d}회 저장: {record['numbers']} + {record['bonus']}")
        except Exception as e:
            print(f"❌ 로또 {record['round']}회 저장 실패: {e}")

    print(f"\n{'='*60}")
    print(f"총 {count}개의 로또 기록이 Firestore에 저장되었습니다!")
    print(f"{'='*60}")

if __name__ == "__main__":
    SERVICE_ACCOUNT = "serviceAccountKey.json"

    print(f"📝 {SERVICE_ACCOUNT}에서 Firebase 인증 정보 로드 중...")

    try:
        db = init_firestore(SERVICE_ACCOUNT)
        print("✅ Firebase 연결 성공!\n")
        add_lotto_records(db)
    except Exception as e:
        print(f"❌ 오류 발생: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
