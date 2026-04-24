"""
연금복권 데이터를 Firestore에 업로드 (회차 1-247)
"""

import csv
import firebase_admin
from firebase_admin import credentials, firestore

def init_firestore(service_account_path: str):
    cred = credentials.Certificate(service_account_path)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    return firestore.client()

def import_pension_csv_to_firestore(db, csv_file_path: str):
    """CSV 파일에서 연금복권 데이터를 읽어 Firestore에 저장"""

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
                    date_str = row['추첨일']
                    # 날짜 형식 변환: 20250123 -> 2025.01.23
                    formatted_date = f"{date_str[:4]}.{date_str[4:6]}.{date_str[6:8]}"

                    winners = {
                        "1등": row['1등'],
                        "2등": row['2등'],
                        "3등": row['3등'],
                        "4등": row['4등'],
                        "5등": row['5등'],
                        "6등": row['6등'],
                        "7등": row['7등'],
                    }
                    bonus = row['보너스']

                    # Firestore 문서 레퍼런스
                    doc_ref = db_ref.document(f"pension_round_{round_num}")

                    # Batch에 쓰기 작업 추가
                    batch.set(doc_ref, {
                        "lottery_type": "pension",
                        "round": round_num,
                        "date": formatted_date,
                        "winners": winners,
                        "bonus": bonus,
                        "createdAt": firestore.SERVER_TIMESTAMP,
                    })

                    batch_count += 1
                    count += 1
                    print(f"✅ 연금복권 {round_num:3d}회 준비: {formatted_date}")

                    # 500개마다 배치 커밋
                    if batch_count >= 500:
                        batch.commit()
                        print(f"\n📦 {batch_count}개 배치 커밋 완료!")
                        batch = db.batch()
                        batch_count = 0

                except Exception as e:
                    errors.append(f"연금복권 {row.get('회차', '?')}회: {str(e)}")
                    print(f"❌ 연금복권 {row.get('회차', '?')}회 준비 실패: {e}")

            # 남은 데이터 커밋
            if batch_count > 0:
                batch.commit()
                print(f"\n📦 마지막 {batch_count}개 배치 커밋 완료!")

        print(f"\n{'='*70}")
        print(f"✅ 총 {count}개의 연금복권 기록이 Firestore에 저장되었습니다!")
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
    CSV_FILE = "pension_lottery_247.csv"

    print(f"📝 {SERVICE_ACCOUNT}에서 Firebase 인증 정보 로드 중...")
    print(f"📋 {CSV_FILE}에서 데이터 읽기 준비 중...\n")

    try:
        db = init_firestore(SERVICE_ACCOUNT)
        print("✅ Firebase 연결 성공!\n")
        import_pension_csv_to_firestore(db, CSV_FILE)
    except Exception as e:
        print(f"❌ 오류 발생: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
