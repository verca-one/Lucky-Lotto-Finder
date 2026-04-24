"""
CSV 파일의 모든 로또 데이터를 Firestore에 업로드 (회차 1-1220)
"""

import csv
import firebase_admin
from firebase_admin import credentials, firestore

def init_firestore(service_account_path: str):
    cred = credentials.Certificate(service_account_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    return firestore.client()

def import_csv_to_firestore(db, csv_file_path: str):
    """CSV 파일에서 로또 데이터를 읽어 Firestore에 저장"""

    db_ref = db.collection("lotto_records")
    count = 0
    errors = []

    try:
        with open(csv_file_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')

            # Firestore batch 작업 (최대 500개씩)
            batch = db.batch()
            batch_count = 0

            for row in reader:
                try:
                    # CSV 데이터 파싱
                    round_num = int(row['회차'])
                    numbers = [
                        int(row['번호1']),
                        int(row['번호2']),
                        int(row['번호3']),
                        int(row['번호4']),
                        int(row['번호5']),
                        int(row['번호6']),
                    ]
                    bonus = int(row['보너스'])

                    # Firestore 문서 레퍼런스
                    doc_ref = db_ref.document(f"round_{round_num}")

                    # Batch에 쓰기 작업 추가
                    batch.set(doc_ref, {
                        "lottery_type": "lotto",
                        "round": round_num,
                        "numbers": numbers,
                        "bonus": bonus,
                        "createdAt": firestore.SERVER_TIMESTAMP,
                    })

                    batch_count += 1
                    count += 1
                    print(f"✅ 로또 {round_num:4d}회 준비: {numbers} + {bonus}")

                    # 500개마다 배치 커밋
                    if batch_count >= 500:
                        batch.commit()
                        print(f"\n📦 {batch_count}개 배치 커밋 완료!")
                        batch = db.batch()
                        batch_count = 0

                except Exception as e:
                    errors.append(f"로또 {row.get('회차', '?')}회: {str(e)}")
                    print(f"❌ 로또 {row.get('회차', '?')}회 준비 실패: {e}")

            # 남은 데이터 커밋
            if batch_count > 0:
                batch.commit()
                print(f"\n📦 마지막 {batch_count}개 배치 커밋 완료!")

        print(f"\n{'='*70}")
        print(f"✅ 총 {count}개의 로또 기록이 Firestore에 저장되었습니다!")
        print(f"{'='*70}")

        if errors:
            print(f"\n⚠️  오류 발생 ({len(errors)}개):")
            for error in errors:
                print(f"  - {error}")

    except FileNotFoundError:
        print(f"❌ CSV 파일을 찾을 수 없습니다: {csv_file_path}")
    except Exception as e:
        print(f"❌ CSV 파일 읽기 오류: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    SERVICE_ACCOUNT = "serviceAccountKey.json"
    CSV_FILE = "lotto_1_1220.csv"

    print(f"📝 {SERVICE_ACCOUNT}에서 Firebase 인증 정보 로드 중...")
    print(f"📋 {CSV_FILE}에서 데이터 읽기 준비 중...\n")

    try:
        db = init_firestore(SERVICE_ACCOUNT)
        print("✅ Firebase 연결 성공!\n")
        import_csv_to_firestore(db, CSV_FILE)
    except Exception as e:
        print(f"❌ 오류 발생: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
