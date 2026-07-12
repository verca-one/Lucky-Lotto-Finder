"""
winning_history 테이블 기준으로 lottery_stores의 카운트 재집계

크롤러는 최신 N회차만 크롤링하기 때문에 upsert 시 first_count 등이
최근 N회차 기준으로 덮어씌워지는 문제를 방지합니다.
이 스크립트를 lotto_verca_uploader.py 실행 후, recalculate_badges.py 실행 전에 실행하세요.

사용법:
  python recalculate_store_counts.py              # 전체
  python recalculate_store_counts.py lotto        # 로또만
  python recalculate_store_counts.py pension      # 연금복권만
"""

import os
import sys
from collections import defaultdict
from supabase import create_client, Client

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ SUPABASE_URL, SUPABASE_KEY 환경변수를 설정하세요")
    sys.exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

LOTTERY_TYPES = ["lotto", "pension", "speedlotto_2000", "speedlotto_1000", "speedlotto_500"]


def fetch_all_paginated(table, select="*", filters=None, page_size=1000):
    """Supabase는 최대 1000개/요청 반환 → page_size=1000 고정, 0개 반환 시 종료"""
    all_rows = []
    offset = 0
    while True:
        query = supabase.table(table).select(select)
        if filters:
            for col, val in filters.items():
                query = query.eq(col, val)
        query = query.range(offset, offset + page_size - 1)
        resp = query.execute()
        rows = resp.data or []
        all_rows.extend(rows)
        if len(rows) < page_size:
            break
        offset += page_size
    return all_rows


def recalculate_counts(lottery_type: str):
    print(f"\n{'='*50}")
    print(f"📊 [{lottery_type}] 판매점 카운트 재집계 시작...")
    print(f"{'='*50}")

    # winning_history 전체 로드
    print(f"  📥 {lottery_type} 당첨 이력 로드 중...")
    histories = fetch_all_paginated(
        "winning_history",
        select="dhlottery_code, prize_tier, round",
        filters={"lottery_type": lottery_type},
        page_size=1000,
    )
    print(f"  → {len(histories)}개 이력 로드")

    if not histories:
        print(f"  ⚠️ 이력 없음, 스킵")
        return

    # 집계
    counts = defaultdict(lambda: {"first": [], "second": []})
    for h in histories:
        code = h["dhlottery_code"]
        tier = h.get("prize_tier", "first")
        rnd = h["round"]
        if tier == "first":
            counts[code]["first"].append(rnd)
        elif tier == "second":
            counts[code]["second"].append(rnd)

    print(f"  → {len(counts)}개 판매점 집계 완료")

    # lottery_stores 업데이트 (100개씩 배치)
    updates = []
    for code, data in counts.items():
        first_rounds = sorted(data["first"], reverse=True)
        second_rounds = sorted(data["second"], reverse=True)
        first_count = len(first_rounds)
        second_count = len(second_rounds)
        total_count = first_count + second_count
        updates.append({
            "dhlottery_code": code,
            "lottery_type": lottery_type,
            "first_count": first_count,
            "second_count": second_count,
            "total_count": total_count,
            "latest_first_win": first_rounds[0] if first_rounds else None,
            "latest_second_win": second_rounds[0] if second_rounds else None,
        })

    print(f"  💾 {len(updates)}개 판매점 카운트 업데이트 중...")
    batch_size = 100
    for i in range(0, len(updates), batch_size):
        batch = updates[i:i + batch_size]
        supabase.table("lottery_stores").upsert(
            batch,
            on_conflict="dhlottery_code,lottery_type"
        ).execute()
        done = min(i + batch_size, len(updates))
        print(f"  ✅ {done}/{len(updates)} 완료")

    # ── 검증: winning_history 집계 vs lottery_stores 저장값 비교 ──
    verify_codes = ["11100773", "12600054"]  # 스파, 부일카서비스
    print(f"\n🔍 핵심 판매점 검증...")
    verify_resp = supabase.table("lottery_stores") \
        .select("dhlottery_code, store_name, first_count, second_count, total_count") \
        .eq("lottery_type", lottery_type) \
        .in_("dhlottery_code", verify_codes) \
        .execute()
    for row in (verify_resp.data or []):
        code = row["dhlottery_code"]
        expected = counts.get(code, {"first": [], "second": []})
        exp_first = len(expected["first"])
        exp_second = len(expected["second"])
        ok_first = row["first_count"] == exp_first
        ok_second = row["second_count"] == exp_second
        status = "✅" if (ok_first and ok_second) else "❌"
        print(f"  {status} {row['store_name']}({code}): 1등={row['first_count']}(예상:{exp_first}) 2등={row['second_count']}(예상:{exp_second})")

    # 전체 통계 출력
    total_first = sum(len(v["first"]) for v in counts.values())
    total_second = sum(len(v["second"]) for v in counts.values())
    print(f"\n📊 [{lottery_type}] 전체 통계:")
    print(f"   업데이트 대상: {len(updates)}개 판매점")
    print(f"   winning_history 집계: 1등 {total_first}건, 2등 {total_second}건")
    print(f"✅ [{lottery_type}] 카운트 재집계 완료!")


def main():
    lt = sys.argv[1] if len(sys.argv) > 1 else None

    if lt and lt not in LOTTERY_TYPES:
        print(f"❌ 알 수 없는 복권 타입: {lt}")
        print(f"사용 가능: {', '.join(LOTTERY_TYPES)}")
        sys.exit(1)

    types = [lt] if lt else LOTTERY_TYPES
    for lottery_type in types:
        recalculate_counts(lottery_type)

    print(f"\n✅ 전체 카운트 재집계 완료!")


if __name__ == "__main__":
    main()
