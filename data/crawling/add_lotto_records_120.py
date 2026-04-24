"""
로또 데이터를 Firestore에 추가 (회차 1-120)
"""

import firebase_admin
from firebase_admin import credentials, firestore

def init_firestore(service_account_path: str):
    cred = credentials.Certificate(service_account_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    return firestore.client()

def add_lotto_records(db):
    """로또 데이터를 Firestore에 추가"""

    # 회차별 로또 데이터 (회차 1-120)
    records = [
        # 회차 1-60은 이전 스크립트와 동일
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
        {"round": 11, "date": "2024-03-16", "numbers": [1, 7, 36, 37, 41, 42], "bonus": 14},
        {"round": 12, "date": "2024-03-23", "numbers": [2, 11, 21, 25, 39, 45], "bonus": 44},
        {"round": 13, "date": "2024-03-30", "numbers": [22, 23, 25, 37, 38, 42], "bonus": 26},
        {"round": 14, "date": "2024-04-06", "numbers": [2, 6, 12, 31, 33, 40], "bonus": 15},
        {"round": 15, "date": "2024-04-13", "numbers": [3, 4, 16, 30, 31, 37], "bonus": 13},
        {"round": 16, "date": "2024-04-20", "numbers": [6, 7, 24, 37, 38, 40], "bonus": 33},
        {"round": 17, "date": "2024-04-27", "numbers": [3, 4, 9, 17, 32, 37], "bonus": 1},
        {"round": 18, "date": "2024-05-04", "numbers": [3, 12, 13, 19, 32, 35], "bonus": 29},
        {"round": 19, "date": "2024-05-11", "numbers": [6, 30, 38, 39, 40, 43], "bonus": 26},
        {"round": 20, "date": "2024-05-18", "numbers": [10, 14, 18, 20, 23, 30], "bonus": 41},
        {"round": 21, "date": "2024-05-25", "numbers": [6, 12, 17, 18, 31, 32], "bonus": 21},
        {"round": 22, "date": "2024-06-01", "numbers": [4, 5, 6, 8, 17, 39], "bonus": 25},
        {"round": 23, "date": "2024-06-08", "numbers": [5, 13, 17, 18, 33, 42], "bonus": 44},
        {"round": 24, "date": "2024-06-15", "numbers": [7, 8, 27, 29, 36, 43], "bonus": 6},
        {"round": 25, "date": "2024-06-22", "numbers": [2, 4, 21, 26, 43, 44], "bonus": 16},
        {"round": 26, "date": "2024-06-29", "numbers": [4, 5, 7, 18, 20, 25], "bonus": 31},
        {"round": 27, "date": "2024-07-06", "numbers": [1, 20, 26, 28, 37, 43], "bonus": 27},
        {"round": 28, "date": "2024-07-13", "numbers": [9, 18, 23, 25, 35, 37], "bonus": 1},
        {"round": 29, "date": "2024-07-20", "numbers": [1, 5, 13, 34, 39, 40], "bonus": 11},
        {"round": 30, "date": "2024-07-27", "numbers": [8, 17, 20, 35, 36, 44], "bonus": 4},
        {"round": 31, "date": "2024-08-03", "numbers": [7, 9, 18, 23, 28, 35], "bonus": 32},
        {"round": 32, "date": "2024-08-10", "numbers": [6, 14, 19, 25, 34, 44], "bonus": 11},
        {"round": 33, "date": "2024-08-17", "numbers": [4, 7, 32, 33, 40, 41], "bonus": 9},
        {"round": 34, "date": "2024-08-24", "numbers": [9, 26, 35, 37, 40, 42], "bonus": 2},
        {"round": 35, "date": "2024-08-31", "numbers": [2, 3, 11, 26, 37, 43], "bonus": 39},
        {"round": 36, "date": "2024-09-07", "numbers": [1, 10, 23, 26, 28, 40], "bonus": 31},
        {"round": 37, "date": "2024-09-14", "numbers": [7, 27, 30, 33, 35, 37], "bonus": 42},
        {"round": 38, "date": "2024-09-21", "numbers": [16, 17, 22, 30, 37, 43], "bonus": 36},
        {"round": 39, "date": "2024-09-28", "numbers": [6, 7, 13, 15, 21, 43], "bonus": 8},
        {"round": 40, "date": "2024-10-05", "numbers": [7, 13, 18, 19, 25, 26], "bonus": 6},
        {"round": 41, "date": "2024-10-12", "numbers": [13, 20, 23, 35, 38, 43], "bonus": 34},
        {"round": 42, "date": "2024-10-19", "numbers": [17, 18, 19, 21, 23, 32], "bonus": 1},
        {"round": 43, "date": "2024-10-26", "numbers": [6, 31, 35, 38, 39, 44], "bonus": 1},
        {"round": 44, "date": "2024-11-02", "numbers": [3, 11, 21, 30, 38, 45], "bonus": 39},
        {"round": 45, "date": "2024-11-09", "numbers": [1, 10, 20, 27, 33, 35], "bonus": 17},
        {"round": 46, "date": "2024-11-16", "numbers": [8, 13, 15, 23, 31, 38], "bonus": 39},
        {"round": 47, "date": "2024-11-23", "numbers": [14, 17, 26, 31, 36, 45], "bonus": 27},
        {"round": 48, "date": "2024-11-30", "numbers": [6, 10, 18, 26, 37, 38], "bonus": 3},
        {"round": 49, "date": "2024-12-07", "numbers": [4, 7, 16, 19, 33, 40], "bonus": 30},
        {"round": 50, "date": "2024-12-14", "numbers": [2, 10, 12, 15, 22, 44], "bonus": 1},
        {"round": 51, "date": "2024-12-21", "numbers": [2, 3, 11, 16, 26, 44], "bonus": 35},
        {"round": 52, "date": "2024-12-28", "numbers": [2, 4, 15, 16, 20, 29], "bonus": 1},
        {"round": 53, "date": "2025-01-04", "numbers": [7, 8, 14, 32, 33, 39], "bonus": 42},
        {"round": 54, "date": "2025-01-11", "numbers": [1, 8, 21, 27, 36, 39], "bonus": 37},
        {"round": 55, "date": "2025-01-18", "numbers": [17, 21, 31, 37, 40, 44], "bonus": 7},
        {"round": 56, "date": "2025-01-25", "numbers": [10, 14, 30, 31, 33, 37], "bonus": 19},
        {"round": 57, "date": "2025-02-01", "numbers": [7, 10, 16, 25, 29, 44], "bonus": 6},
        {"round": 58, "date": "2025-02-08", "numbers": [10, 24, 25, 33, 40, 44], "bonus": 1},
        {"round": 59, "date": "2025-02-15", "numbers": [6, 29, 36, 39, 41, 45], "bonus": 13},
        {"round": 60, "date": "2025-02-22", "numbers": [2, 8, 25, 36, 39, 42], "bonus": 11},

        # 회차 61-120 (새로운 데이터)
        {"round": 61, "date": "2025-03-01", "numbers": [14, 15, 19, 30, 38, 43], "bonus": 8},
        {"round": 62, "date": "2025-03-08", "numbers": [3, 8, 15, 27, 29, 35], "bonus": 21},
        {"round": 63, "date": "2025-03-15", "numbers": [3, 20, 23, 36, 38, 40], "bonus": 5},
        {"round": 64, "date": "2025-03-22", "numbers": [14, 15, 18, 21, 26, 36], "bonus": 39},
        {"round": 65, "date": "2025-03-29", "numbers": [4, 25, 33, 36, 40, 43], "bonus": 39},
        {"round": 66, "date": "2025-04-05", "numbers": [2, 3, 7, 17, 22, 24], "bonus": 45},
        {"round": 67, "date": "2025-04-12", "numbers": [3, 7, 10, 15, 36, 38], "bonus": 33},
        {"round": 68, "date": "2025-04-19", "numbers": [10, 12, 15, 16, 26, 39], "bonus": 38},
        {"round": 69, "date": "2025-04-26", "numbers": [5, 8, 14, 15, 19, 39], "bonus": 35},
        {"round": 70, "date": "2025-05-03", "numbers": [5, 19, 22, 25, 28, 43], "bonus": 26},
        {"round": 71, "date": "2025-05-10", "numbers": [5, 9, 12, 16, 29, 41], "bonus": 21},
        {"round": 72, "date": "2025-05-17", "numbers": [2, 4, 11, 17, 26, 27], "bonus": 1},
        {"round": 73, "date": "2025-05-24", "numbers": [3, 12, 18, 32, 40, 43], "bonus": 38},
        {"round": 74, "date": "2025-05-31", "numbers": [6, 15, 17, 18, 35, 40], "bonus": 23},
        {"round": 75, "date": "2025-06-07", "numbers": [2, 5, 24, 32, 34, 44], "bonus": 28},
        {"round": 76, "date": "2025-06-14", "numbers": [1, 3, 15, 22, 25, 37], "bonus": 43},
        {"round": 77, "date": "2025-06-21", "numbers": [2, 18, 29, 32, 43, 44], "bonus": 37},
        {"round": 78, "date": "2025-06-28", "numbers": [10, 13, 25, 29, 33, 35], "bonus": 38},
        {"round": 79, "date": "2025-07-05", "numbers": [3, 12, 24, 27, 30, 32], "bonus": 14},
        {"round": 80, "date": "2025-07-12", "numbers": [17, 18, 24, 25, 26, 30], "bonus": 1},
        {"round": 81, "date": "2025-07-19", "numbers": [5, 7, 11, 13, 20, 33], "bonus": 6},
        {"round": 82, "date": "2025-07-26", "numbers": [1, 2, 3, 14, 27, 42], "bonus": 39},
        {"round": 83, "date": "2025-08-02", "numbers": [6, 10, 15, 17, 19, 34], "bonus": 14},
        {"round": 84, "date": "2025-08-09", "numbers": [16, 23, 27, 34, 42, 45], "bonus": 11},
        {"round": 85, "date": "2025-08-16", "numbers": [6, 8, 13, 23, 31, 36], "bonus": 21},
        {"round": 86, "date": "2025-08-23", "numbers": [2, 12, 37, 39, 41, 45], "bonus": 33},
        {"round": 87, "date": "2025-08-30", "numbers": [4, 12, 16, 23, 34, 43], "bonus": 26},
        {"round": 88, "date": "2025-09-06", "numbers": [1, 17, 20, 24, 30, 41], "bonus": 27},
        {"round": 89, "date": "2025-09-13", "numbers": [4, 26, 28, 29, 33, 40], "bonus": 37},
        {"round": 90, "date": "2025-09-20", "numbers": [17, 20, 29, 35, 38, 44], "bonus": 10},
        {"round": 91, "date": "2025-09-27", "numbers": [1, 21, 24, 26, 29, 42], "bonus": 27},
        {"round": 92, "date": "2025-10-04", "numbers": [3, 14, 24, 33, 35, 36], "bonus": 17},
        {"round": 93, "date": "2025-10-11", "numbers": [6, 22, 24, 36, 38, 44], "bonus": 19},
        {"round": 94, "date": "2025-10-18", "numbers": [5, 32, 34, 40, 41, 45], "bonus": 6},
        {"round": 95, "date": "2025-10-25", "numbers": [8, 17, 27, 31, 34, 43], "bonus": 14},
        {"round": 96, "date": "2025-11-01", "numbers": [1, 3, 8, 21, 22, 31], "bonus": 20},
        {"round": 97, "date": "2025-11-08", "numbers": [6, 7, 14, 15, 20, 36], "bonus": 3},
        {"round": 98, "date": "2025-11-15", "numbers": [6, 9, 16, 23, 24, 32], "bonus": 43},
        {"round": 99, "date": "2025-11-22", "numbers": [1, 3, 10, 27, 29, 37], "bonus": 11},
        {"round": 100, "date": "2025-11-29", "numbers": [1, 7, 11, 23, 37, 42], "bonus": 6},
        {"round": 101, "date": "2025-12-06", "numbers": [1, 3, 17, 32, 35, 45], "bonus": 8},
        {"round": 102, "date": "2025-12-13", "numbers": [17, 22, 24, 26, 40, 42], "bonus": 보기어려움},
        {"round": 103, "date": "2025-12-20", "numbers": [5, 14, 15, 27, 30, 45], "bonus": 10},
        {"round": 104, "date": "2025-12-27", "numbers": [17, 32, 33, 34, 42, 44], "bonus": 35},
        {"round": 105, "date": "2026-01-03", "numbers": [8, 10, 20, 34, 41, 45], "bonus": 28},
        {"round": 106, "date": "2026-01-10", "numbers": [4, 10, 12, 22, 24, 33], "bonus": 29},
        {"round": 107, "date": "2026-01-17", "numbers": [1, 4, 5, 6, 9, 31], "bonus": 17},
        {"round": 108, "date": "2026-01-24", "numbers": [7, 18, 22, 23, 29, 44], "bonus": 12},
        {"round": 109, "date": "2026-01-31", "numbers": [1, 5, 34, 36, 42, 44], "bonus": 33},
        {"round": 110, "date": "2026-02-07", "numbers": [7, 20, 22, 23, 29, 43], "bonus": 1},
        {"round": 111, "date": "2026-02-14", "numbers": [7, 18, 31, 33, 36, 40], "bonus": 27},
        {"round": 112, "date": "2026-02-21", "numbers": [26, 29, 30, 32, 41, 42], "bonus": 43},
        {"round": 113, "date": "2026-02-28", "numbers": [4, 9, 28, 33, 36, 45], "bonus": 26},
        {"round": 114, "date": "2026-03-07", "numbers": [11, 14, 19, 26, 28, 41], "bonus": 2},
        {"round": 115, "date": "2026-03-14", "numbers": [1, 2, 6, 9, 25, 28], "bonus": 31},
        {"round": 116, "date": "2026-03-21", "numbers": [2, 4, 25, 31, 34, 37], "bonus": 17},
        {"round": 117, "date": "2026-03-28", "numbers": [5, 10, 22, 34, 36, 44], "bonus": 35},
        {"round": 118, "date": "2026-04-04", "numbers": [3, 4, 10, 17, 19, 22], "bonus": 38},
        {"round": 119, "date": "2026-04-11", "numbers": [3, 11, 13, 14, 17, 21], "bonus": 38},
        {"round": 120, "date": "2026-04-18", "numbers": [4, 6, 10, 11, 32, 37], "bonus": 30},
    ]

    db_ref = db.collection("lotto_records")
    count = 0
    errors = []

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
            print(f"✅ 로또 {record['round']:3d}회 저장: {record['numbers']} + {record['bonus']}")
        except Exception as e:
            errors.append(f"로또 {record['round']}회: {str(e)}")
            print(f"❌ 로또 {record['round']}회 저장 실패: {e}")

    print(f"\n{'='*70}")
    print(f"✅ 총 {count}개의 로또 기록이 Firestore에 저장되었습니다!")
    print(f"{'='*70}")

    if errors:
        print(f"\n⚠️  오류 발생 ({len(errors)}개):")
        for error in errors:
            print(f"  - {error}")

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
