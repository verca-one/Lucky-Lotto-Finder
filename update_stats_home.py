"""
홈 화면용 요약 통계 갱신 스크립트
크롤링 + 배지 재계산 완료 후 실행

필요 테이블 (최초 1회 Supabase SQL Editor에서 실행):
  CREATE TABLE IF NOT EXISTS home_stats (
    id TEXT PRIMARY KEY DEFAULT 'home',
    lotto_latest_round INT,
    pension_latest_round INT,
    total_store_count INT,
    lotto_winning_store_count INT,
    pension_winning_store_count INT,
    lotto_total_wins INT,
    pension_total_wins INT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
"""
import os
import sys
from datetime import datetime, timezone
from supabase import create_client

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ SUPABASE_URL, SUPABASE_KEY 환경변수를 설정하세요")
    sys.exit(1)

sb = create_client(SUPABASE_URL, SUPABASE_KEY)


def get_latest_round(lottery_type: str) -> int:
    resp = sb.table("winning_history") \
        .select("round") \
        .eq("lottery_type", lottery_type) \
        .order("round", desc=True) \
        .limit(1) \
        .execute()
    return resp.data[0]["round"] if resp.data else 0


def get_store_stats(lottery_type: str) -> dict:
    """lottery_stores에서 총 판매점 수 및 당첨 판매점 수 집계"""
    # 전체 판매점 수
    resp_total = sb.table("lottery_stores") \
        .select("dhlottery_code", count="exact") \
        .eq("lottery_type", lottery_type) \
        .execute()
    total = resp_total.count or 0

    # 1등 당첨 판매점 수
    resp_winning = sb.table("lottery_stores") \
        .select("dhlottery_code", count="exact") \
        .eq("lottery_type", lottery_type) \
        .gt("first_count", 0) \
        .execute()
    winning = resp_winning.count or 0

    # 누적 당첨 횟수 합계
    resp_wins = sb.table("lottery_stores") \
        .select("total_count") \
        .eq("lottery_type", lottery_type) \
        .execute()
    total_wins = sum(r.get("total_count") or 0 for r in (resp_wins.data or []))

    return {"total": total, "winning": winning, "total_wins": total_wins}


def main():
    print("=" * 50)
    print("📊 홈 요약 통계 갱신 시작...")
    print("=" * 50)

    lotto_round = get_latest_round("lotto")
    pension_round = get_latest_round("pension")
    print(f"  로또 최신 회차: {lotto_round}")
    print(f"  연금 최신 회차: {pension_round}")

    lotto_stats = get_store_stats("lotto")
    pension_stats = get_store_stats("pension")
    print(f"  로또 전체 판매점: {lotto_stats['total']}개 (1등 당첨: {lotto_stats['winning']}개)")
    print(f"  연금 전체 판매점: {pension_stats['total']}개 (1등 당첨: {pension_stats['winning']}개)")
    print(f"  로또 누적 당첨: {lotto_stats['total_wins']}건")
    print(f"  연금 누적 당첨: {pension_stats['total_wins']}건")

    data = {
        "id": "home",
        "lotto_latest_round": lotto_round,
        "pension_latest_round": pension_round,
        "total_store_count": lotto_stats["total"],
        "lotto_winning_store_count": lotto_stats["winning"],
        "pension_winning_store_count": pension_stats["winning"],
        "lotto_total_wins": lotto_stats["total_wins"],
        "pension_total_wins": pension_stats["total_wins"],
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        sb.table("home_stats").upsert(data, on_conflict="id").execute()
        print("✅ home_stats 저장 완료!")
        print(f"   CRAWL_ROUND_LOTTO={lotto_round}")
        print(f"   CRAWL_ROUND_PENSION={pension_round}")
    except Exception as e:
        print(f"⚠️  home_stats 저장 실패 (테이블 없을 수 있음): {e}")
        print("   Supabase SQL Editor에서 아래 SQL 실행 후 재시도하세요:")
        print("""
CREATE TABLE IF NOT EXISTS home_stats (
  id TEXT PRIMARY KEY DEFAULT 'home',
  lotto_latest_round INT,
  pension_latest_round INT,
  total_store_count INT,
  lotto_winning_store_count INT,
  pension_winning_store_count INT,
  lotto_total_wins INT,
  pension_total_wins INT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
""")


if __name__ == "__main__":
    main()
