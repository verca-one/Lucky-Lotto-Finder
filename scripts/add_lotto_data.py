"""
사진에서 추출한 로또 데이터를 Firestore에 추가
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
    """사진의 로또 데이터를 Firestore에 추가"""

    records = [
        {"round": 1, "date": "2024-01-01", "numbers": [10, 23, 29, 33, 37, 40], "bonus": 16, "lottery_type": "lotto"},
        {"round": 2, "date": "2024-01-08", "numbers": [9, 13, 21, 25, 32, 42], "bonus": 2, "lottery_type": "lotto"},
        {"round": 3, "date": "2024-01-15", "numbers": [11, 16, 19, 21, 27, 31], "bonus": 30, "lottery_type": "lotto"},
        {"round": 4, "date": "2024-01-22", "numbers": [14, 27, 30, 31, 40, 42], "bonus": 2, "lottery_type": "lotto"},
        {"round": 5, "date": "2024-01-29", "numbers": [16, 24, 29, 40, 41, 42], "bonus": 3, "lottery_type": "lotto"},
        {"round": 6, "date": "2024-02-05", "numbers": [14, 15, 26, 27, 40, 42], "bonus": 34, "lottery_type": "lotto"},
        {"round": 7, "date": "2024-02-12", "numbers": [2, 9, 16, 25, 26, 40], "bonus": 42, "lottery_type": "lotto"},
        {"round": 8, "date": "2024-02-19", "numbers": [8, 19, 25, 34, 37, 39], "bonus": 9, "lottery_type": "lotto"},
        {"round": 9, "date": "2024-02-26", "numbers": [2, 4, 16, 17, 36, 39], "bonus": 14, "lottery_type": "lotto"},
        {"round": 10, "date": "2024-03-04", "numbers": [9, 25, 30, 33, 41, 44], "bonus": 6, "lottery_type": "lotto"},
    ]

    db_ref = db.collection("lotto_records")
    count = 0

    for record in records:
        try:
            db_ref.add({
                "lottery_type": record["lottery_type"],
                "round": record["round"],
                "date": record["date"],
                "numbers": record["numbers"],
                "bonus": record["bonus"],
                "createdAt": firestore.SERVER_TIMESTAMP,
            })
            count += 1
            print(f"✅ 로또 {record['round']}회 저장 완료")
        except Exception as e:
            print(f"❌ 로또 {record['round']}회 저장 실패: {e}")

    print(f"\n총 {count}개의 로또 기록이 저장되었습니다.")

if __name__ == "__main__":
    SERVICE_ACCOUNT = "serviceAccountKey.json"

    db = init_firestore(SERVICE_ACCOUNT)
    add_lotto_records(db)
