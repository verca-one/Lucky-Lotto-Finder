"""
Supabase에 크롤링한 로또 당첨지점 데이터 업로드
초고속 배치 업로드 + 중복 방지 upsert 버전
"""
import json
import os
import time
from datetime import datetime
from supabase import create_client, Client

# =========================
# Supabase 연결 정보
# =========================
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ 에러: SUPABASE_URL, SUPABASE_KEY 환경변수를 설정하세요")
    exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# =========================
# 설정값
# =========================
game_types = ["lotto", "pension", "speedlotto_2000", "speedlotto_1000", "speedlotto_500"]
BATCH_SIZE = 500
MAX_RETRY = 3

# 이미 많이 올렸고 이력정보만 이어서 하고 싶으면 숫자 변경
# 예: 34000부터 이어서 하려면 34000
# 전체 다시 돌릴 거면 0
HISTORY_START_INDEX = 0

# 지점정보도 이어서 하고 싶으면 사용
STORE_START_INDEX = 0

# =========================
# 공통 배치 실행 함수
# =========================
def execute_with_retry(table_name, rows, on_conflict, batch_label):
    for attempt in range(1, MAX_RETRY + 1):
        try:
            supabase.table(table_name).upsert(
                rows,
                on_conflict=on_conflict
            ).execute()
            return True
        except Exception as e:
            print(f"⚠️  {batch_label} 실패 {attempt}/{MAX_RETRY}")
            print(e)
            if attempt < MAX_RETRY:
                time.sleep(2)
            else:
                return False

# =========================
# 지점정보 업로드
# =========================
def upload_stores(game_type: str):
    filename = f"lost_verca_plus_{game_type}_stores.json"

    if not os.path.exists(filename):
        print(f"⚠️  파일 없음: {filename}")
        return 0

    print(f"\n📤 {game_type} 지점정보 업로드 시작...")

    try:
        with open(filename, 'r', encoding='utf-8') as f:
            data = json.load(f)

        stores = data.get("stores", [])
        print(f"  총 {len(stores):,}개 지점 발견")

        if STORE_START_INDEX > 0:
            stores = stores[STORE_START_INDEX:]
            print(f"  ⏭️  {STORE_START_INDEX:,}번 이후부터 지점정보 이어서 업로드")

        uploaded = 0
        failed_batches = []

        for i in range(0, len(stores), BATCH_SIZE):
            batch = stores[i:i + BATCH_SIZE]
            rows = []
            now = datetime.now().isoformat()

            for store in batch:
                rows.append({
                    "dhlottery_code": store.get("dhlottery_code"),
                    "store_name": store.get("store_name"),
                    "address": store.get("address"),
                    "region": store.get("region"),
                    "lottery_type": store.get("lottery_type") or game_type,
                    "purchase_method": store.get("purchase_method", ""),
                    "first_count": store.get("first_count", 0),
                    "second_count": store.get("second_count", 0),
                    "total_count": store.get("total_count", 0),
                    "latest_first_win": store.get("latest_first_win"),
                    "latest_second_win": store.get("latest_second_win"),
                    "crawled_at": now
                })

            real_start = STORE_START_INDEX + i
            real_end = STORE_START_INDEX + i + len(rows) - 1

            ok = execute_with_retry(
                table_name="lottery_stores",
                rows=rows,
                on_conflict="dhlottery_code,lottery_type",
                batch_label=f"{game_type} 지점정보 {real_start}~{real_end}"
            )

            if ok:
                uploaded += len(rows)
                print(f"  ✅ {uploaded:,}/{len(stores):,} 지점정보 업로드 완료")
            else:
                failed_batches.append((real_start, real_end))
                print(f"  ❌ 실패 구간: {real_start}~{real_end}")

        print(f"✅ {game_type} 지점정보: {uploaded:,}/{len(stores):,} 업로드 완료")
        if failed_batches:
            print("  실패한 지점정보 구간:")
            for start, end in failed_batches:
                print(f"  - {start} ~ {end}")

        return uploaded

    except Exception as e:
        print(f"❌ {game_type} 지점정보 파일 처리 실패: {e}")
        return 0

# =========================
# 이력정보 업로드
# =========================
def upload_histories(game_type: str):
    filename = f"lost_verca_plus_{game_type}_histories.json"

    if not os.path.exists(filename):
        print(f"⚠️  파일 없음: {filename}")
        return 0

    print(f"\n📤 {game_type} 이력정보 업로드 시작...")

    try:
        with open(filename, 'r', encoding='utf-8') as f:
            data = json.load(f)

        histories = data.get("histories", [])
        print(f"  총 {len(histories):,}개 이력 발견")

        if HISTORY_START_INDEX > 0:
            histories = histories[HISTORY_START_INDEX:]
            print(f"  ⏭️  {HISTORY_START_INDEX:,}번 이후부터 이력정보 이어서 업로드")

        uploaded = 0
        failed_batches = []

        for i in range(0, len(histories), BATCH_SIZE):
            batch = histories[i:i + BATCH_SIZE]
            rows = []
            now = datetime.now().isoformat()

            for history in batch:
                rows.append({
                    "dhlottery_code": history.get("dhlottery_code"),
                    "lottery_type": game_type,
                    "round": history.get("round"),
                    "prize_tier": history.get("prize_tier"),
                    "purchase_method": history.get("purchase_method", ""),
                    "created_at": now
                })

            real_start = HISTORY_START_INDEX + i
            real_end = HISTORY_START_INDEX + i + len(rows) - 1

            ok = execute_with_retry(
                table_name="winning_history",
                rows=rows,
                on_conflict="dhlottery_code,lottery_type,round,prize_tier",
                batch_label=f"{game_type} 이력정보 {real_start}~{real_end}"
            )

            if ok:
                uploaded += len(rows)
                print(f"  ✅ {uploaded:,}/{len(histories):,} 이력정보 업로드 완료")
            else:
                failed_batches.append((real_start, real_end))
                print(f"  ❌ 실패 구간: {real_start}~{real_end}")

        print(f"✅ {game_type} 이력정보: {uploaded:,}/{len(histories):,} 업로드 완료")
        if failed_batches:
            print("  실패한 이력정보 구간:")
            for start, end in failed_batches:
                print(f"  - {start} ~ {end}")

        return uploaded

    except Exception as e:
        print(f"❌ {game_type} 이력정보 파일 처리 실패: {e}")
        return 0

# =========================
# 실행
# =========================
def main():
    print("=" * 70)
    print("🚀 Supabase 데이터 초고속 업로드 시작")
    print("=" * 70)

    total_stores = 0
    total_histories = 0

    for game_type in game_types:
        stores_count = upload_stores(game_type)
        total_stores += stores_count

        histories_count = upload_histories(game_type)
        total_histories += histories_count

    print("\n" + "=" * 70)
    print("✅ 업로드 완료!")
    print(f"   지점정보: {total_stores:,}개")
    print(f"   이력정보: {total_histories:,}개")
    print("=" * 70)

if __name__ == "__main__":
    main()
