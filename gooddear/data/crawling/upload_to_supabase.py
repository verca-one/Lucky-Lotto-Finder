import os
import json
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, firestore
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()

# Firebase 초기화
try:
    firebase_admin.get_app()
except ValueError:
    firebase_cred = credentials.Certificate('firebase-adminsdk.json')
    firebase_admin.initialize_app(firebase_cred)

db = firestore.client()

# Supabase 초기화
SUPABASE_URL = "https://unmkjwdfthanhatyudwg.supabase.co"
SUPABASE_SECRET_KEY = os.getenv('SUPABASE_SECRET_KEY')

if not SUPABASE_SECRET_KEY:
    raise ValueError("SUPABASE_SECRET_KEY 환경변수가 설정되지 않았습니다")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SECRET_KEY)

# Firebase 컬렉션별 매핑
FIREBASE_COLLECTIONS = {
    'lotto': 'zero_plus_firebase_lotto',
    'pension': 'zero_plus_firebase_pension',
    'speedlotto_2000': 'zero_plus_firebase_speedlotto_2000',
    'speedlotto_1000': 'zero_plus_firebase_speedlotto_1000',
    'speedlotto_500': 'zero_plus_firebase_speedlotto_500',
}

def transform_firebase_data(firebase_doc):
    """Firebase 문서를 Supabase 테이블 형식으로 변환"""
    data = firebase_doc.to_dict() if hasattr(firebase_doc, 'to_dict') else firebase_doc

    # Firebase에서 읽은 데이터를 그대로 사용 (이미 올바른 형식임)
    return {
        'game_store_id': data.get('game_store_id', ''),
        'dhlottery_code': data.get('dhlottery_code', ''),
        'store_name': data.get('store_name', ''),
        'address': data.get('address', ''),
        'region': data.get('region', ''),
        'method': data.get('method', ''),
        'latitude': data.get('latitude'),
        'longitude': data.get('longitude'),
        'lottery_type': data.get('lottery_type', ''),
        'round': data.get('round', 0),
        'prize_tier': data.get('prize_tier', ''),
        'store_rank': data.get('store_rank', 0),
        'winning_amount': data.get('winning_amount'),
        'created_at': data.get('created_at', datetime.now().isoformat()),
        'crawled_at': data.get('crawled_at', datetime.now().isoformat()),
        'winning_count': data.get('winning_count', 1),
    }

def migrate_from_firebase():
    """Firebase에서 Supabase로 데이터 마이그레이션"""
    print("=" * 60)
    print("Firebase → Supabase 데이터 마이그레이션 시작")
    print("=" * 60)

    total_migrated = 0

    for game_type, collection_name in FIREBASE_COLLECTIONS.items():
        print(f"\n📊 처리 중: {game_type} ({collection_name})")

        try:
            # Firebase에서 데이터 읽기
            docs = list(db.collection(collection_name).stream())

            if not docs:
                print(f"   ⚠️  데이터 없음")
                continue

            print(f"   총 {len(docs)}개 문서 발견")

            # 데이터 변환
            stores_data = []
            for doc in docs:
                transformed = transform_firebase_data(doc)
                stores_data.append(transformed)

            # 배치 업로드 (500개씩)
            batch_size = 500
            for i in range(0, len(stores_data), batch_size):
                batch = stores_data[i:i + batch_size]
                batch_num = i // batch_size + 1

                try:
                    # 기존 데이터가 있으면 upsert (game_store_id로 중복 체크)
                    response = supabase.table('lottery_stores').upsert(
                        batch,
                        ignore_duplicates=False
                    ).execute()

                    print(f"   ✅ 배치 {batch_num}: {len(batch)}개 업로드 완료")
                    total_migrated += len(batch)

                except Exception as e:
                    print(f"   ❌ 배치 {batch_num} 오류: {str(e)}")

        except Exception as e:
            print(f"   ❌ {game_type} 마이그레이션 오류: {str(e)}")

    print("\n" + "=" * 60)
    print(f"✅ 마이그레이션 완료: 총 {total_migrated}개 레코드 업로드됨")
    print("=" * 60)

def upload_latest(game_type: str, stores_data: list):
    """최신 크롤링 데이터를 Supabase에 업로드 (GitHub Actions용)"""
    print(f"\n📤 Supabase 업로드: {game_type}")

    try:
        if not stores_data:
            print("   ⚠️  업로드할 데이터 없음")
            return

        # 배치 업로드 (500개씩)
        batch_size = 500
        total_uploaded = 0

        for i in range(0, len(stores_data), batch_size):
            batch = stores_data[i:i + batch_size]

            try:
                response = supabase.table('lottery_stores').upsert(batch).execute()
                total_uploaded += len(batch)
                print(f"   ✅ {len(batch)}개 업로드 완료")
            except Exception as e:
                print(f"   ❌ 업로드 오류: {str(e)}")
                return False

        print(f"   ✅ {game_type}: 총 {total_uploaded}개 업로드 완료")
        return True

    except Exception as e:
        print(f"   ❌ {game_type} 업로드 실패: {str(e)}")
        return False

def migrate_from_json_files():
    """로컬 zero_base_*.json 파일에서 Supabase로 마이그레이션"""
    print("=" * 60)
    print("JSON 파일 → Supabase 데이터 마이그레이션 시작")
    print("=" * 60)

    base_path = "S:\\next leval\\Lucky Lotto Finder\\flutter_app\\assets"
    json_files = {
        'lotto': f'{base_path}\\zero_base_lotto_stores_latest.json',
        'pension': f'{base_path}\\zero_base_pension_stores_latest.json',
        'speedlotto_2000': f'{base_path}\\zero_base_speedlotto_2000_stores_latest.json',
        'speedlotto_1000': f'{base_path}\\zero_base_speedlotto_1000_stores_latest.json',
        'speedlotto_500': f'{base_path}\\zero_base_speedlotto_500_stores_latest.json',
    }

    def clean_store_data(store):
        """null 값 정제"""
        if not store.get('store_name'):
            store['store_name'] = '미지정'
        if not store.get('method'):
            store['method'] = '불명'
        return store

    total_migrated = 0

    for game_type, json_path in json_files.items():
        print(f"\n📊 처리 중: {game_type}")

        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                stores_data = data.get('stores', [])
                # null 값 정제
                stores_data = [clean_store_data(store) for store in stores_data]

            if not stores_data:
                print(f"   ⚠️  데이터 없음")
                continue

            print(f"   총 {len(stores_data)}개 문서 발견")

            # 배치 업로드 (500개씩)
            batch_size = 500
            for i in range(0, len(stores_data), batch_size):
                batch = stores_data[i:i + batch_size]
                batch_num = i // batch_size + 1

                try:
                    response = supabase.table('lottery_stores').upsert(
                        batch,
                        ignore_duplicates=False
                    ).execute()

                    print(f"   ✅ 배치 {batch_num}: {len(batch)}개 업로드 완료")
                    total_migrated += len(batch)

                except Exception as e:
                    print(f"   ❌ 배치 {batch_num} 오류: {str(e)}")

        except FileNotFoundError:
            print(f"   ⚠️  파일 없음: {json_path}")
        except Exception as e:
            print(f"   ❌ {game_type} 마이그레이션 오류: {str(e)}")

    print("\n" + "=" * 60)
    print(f"✅ 마이그레이션 완료: 총 {total_migrated}개 레코드 업로드됨")
    print("=" * 60)

if __name__ == '__main__':
    import sys

    # GitHub Actions에서 호출: python upload_to_supabase.py latest <game_type> <json_file>
    # 로컬에서 호출: python upload_to_supabase.py migrate

    if len(sys.argv) > 1 and sys.argv[1] == 'migrate':
        migrate_from_json_files()
    elif len(sys.argv) > 1 and sys.argv[1] == 'latest':
        game_type = sys.argv[2] if len(sys.argv) > 2 else 'lotto'
        json_file = sys.argv[3] if len(sys.argv) > 3 else 'stores.json'

        try:
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                stores_data = data.get('stores', [])
                upload_latest(game_type, stores_data)
        except FileNotFoundError:
            print(f"❌ 파일 없음: {json_file}")
    else:
        print("사용법:")
        print("  로컬 마이그레이션: python upload_to_supabase.py migrate")
        print("  최신 업로드: python upload_to_supabase.py latest <game_type> <json_file>")
