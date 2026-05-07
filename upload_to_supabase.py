"""
Supabase에 크롤링한 로또 당첨지점 데이터 업로드
"""

import json
import os
from datetime import datetime
from supabase import create_client, Client

# Supabase 연결 정보 (환경변수에서 읽기)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ 에러: SUPABASE_URL, SUPABASE_KEY 환경변수를 설정하세요")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# 게임 타입별 파일
game_files = {
    "lotto": "base_big_lotto_stores.json",
    "pension": "base_big_pension_stores.json",
    "speedlotto_2000": "base_big_speedlotto_2000_stores.json",
    "speedlotto_1000": "base_big_speedlotto_1000_stores.json",
    "speedlotto_500": "base_big_speedlotto_500_stores.json"
}

def upload_game_data(game_type: str, filename: str):
    """게임별 데이터 업로드"""
    if not os.path.exists(filename):
        print(f"⚠️  파일 없음: {filename}")
        return 0

    print(f"\n📤 {game_type} 업로드 시작...")

    try:
        with open(filename, 'r', encoding='utf-8') as f:
            data = json.load(f)

        stores = data.get("stores", [])
        print(f"  총 {len(stores)}개 지점 발견")

        uploaded = 0
        for idx, store in enumerate(stores, 1):
            try:
                # Supabase에 insert
                response = supabase.table('lottery_stores').insert({
                    "dhlottery_code": store.get("dhlottery_code"),
                    "store_name": store.get("store_name"),
                    "address": store.get("address"),
                    "region": store.get("region"),
                    "lottery_type": game_type,
                    "first_wins": store.get("first_wins", []),
                    "second_wins": store.get("second_wins", []),
                    "first_count": store.get("first_count", 0),
                    "second_count": store.get("second_count", 0),
                    "total_count": store.get("total_count", 0),
                    "crawled_at": datetime.now().isoformat()
                }).execute()

                uploaded += 1

                if idx % 100 == 0:
                    print(f"  {idx}/{len(stores)} 업로드 완료...")

            except Exception as e:
                print(f"  ⚠️  {store.get('dhlottery_code')} 업로드 실패: {e}")
                continue

        print(f"✅ {game_type}: {uploaded}/{len(stores)} 업로드 완료")
        return uploaded

    except Exception as e:
        print(f"❌ {game_type} 파일 처리 실패: {e}")
        return 0


def main():
    print("=" * 70)
    print("🚀 Supabase 데이터 업로드 시작")
    print("=" * 70)

    total_uploaded = 0

    for game_type, filename in game_files.items():
        count = upload_game_data(game_type, filename)
        total_uploaded += count

    print("\n" + "=" * 70)
    print(f"✅ 업로드 완료! 총 {total_uploaded}개 지점")
    print("=" * 70)


if __name__ == "__main__":
    main()
