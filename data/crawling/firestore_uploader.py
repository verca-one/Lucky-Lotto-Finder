"""
크롤링한 데이터를 Firestore에 업로드
- 로또, 연금복권, 스피또 모두 처리
- store_id = 주소 기반 해시
"""

import json
import hashlib
import time
import firebase_admin
from firebase_admin import credentials, firestore

def init_firestore(service_account_path: str):
    cred = credentials.Certificate(service_account_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    return firestore.client()

def make_store_id(store_name: str, address: str) -> str:
    raw = f"{store_name}_{address}"
    return hashlib.md5(raw.encode()).hexdigest()[:12]

def upload_to_firestore(db, stores: list[dict]):
    WIN_FIELD = {
        "lotto": "lotto_wins",
        "pension": "pension_wins",
        "speeto2000": "speeto2000_wins",
        "speeto1000": "speeto1000_wins",
        "speeto500": "speeto500_wins",
    }

    batch = db.batch()
    count = 0

    for s in stores:
        store_id = make_store_id(s["store_name"], s["address"])
        lottery_type = s.get("lottery_type", "lotto")
        rank = s.get("rank", 1)

        # rank별로 다른 필드에 저장
        if rank == 1:
            win_field = f"{lottery_type}_wins"
        elif rank == 2:
            win_field = f"{lottery_type}_2nd_wins"
        elif rank == 3:
            win_field = f"{lottery_type}_3rd_wins"
        else:
            win_field = f"{lottery_type}_wins"

        store_ref = db.collection("stores").document(store_id)
        history_ref = db.collection("win_history").document(
            f"{store_id}_{lottery_type}_{s['round']}"
        )

        store_data = {
            "store_id": store_id,
            "store_name": s["store_name"],
            "address": s["address"],
            "region": s.get("region", ""),
            "lat": s.get("lat"),
            "lng": s.get("lng"),
            "method": s.get("method", ""),
            "updated_at": firestore.SERVER_TIMESTAMP,
            win_field: firestore.ArrayUnion([s["round"]]),
            "last_win_round": s["round"],
        }
        batch.set(store_ref, store_data, merge=True)

        history_data = {
            "store_id": store_id,
            "lottery_type": lottery_type,
            "round": s["round"],
            "rank": s.get("rank", 1),
            "method": s["method"],
            "crawled_at": s["crawled_at"],
        }
        batch.set(history_ref, history_data)

        count += 1
        if count % 200 == 0:
            batch.commit()
            batch = db.batch()
            print(f"  {count}건 업로드 중...")
            time.sleep(2)

    batch.commit()
    print(f"업로드 완료: 총 {count}건")

if __name__ == "__main__":
    SERVICE_ACCOUNT = "serviceAccountKey.json"
    DATA_FILE = "winner_stores.json"

    db = init_firestore(SERVICE_ACCOUNT)

    with open(DATA_FILE, encoding="utf-8") as f:
        stores = json.load(f)

    print(f"{len(stores)}건 Firestore 업로드 시작...")
    upload_to_firestore(db, stores)