"""
store_badges 재계산 스크립트
크롤링 후 실행하여 배지 캐시 테이블을 갱신합니다.

사용법:
  python recalculate_badges.py              # 전체 재계산
  python recalculate_badges.py lotto        # 로또만
  python recalculate_badges.py pension      # 연금만
"""

import os
import sys
import math
from datetime import datetime
from collections import defaultdict
from supabase import create_client, Client

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ SUPABASE_URL, SUPABASE_KEY 환경변수를 설정하세요")
    sys.exit(1)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


def fetch_all_paginated(table, select="*", filters=None, order_col=None, page_size=1000):
    """Supabase 1000행 제한 우회 페이지네이션 조회"""
    all_rows = []
    offset = 0
    while True:
        query = supabase.table(table).select(select)
        if filters:
            for col, val in filters.items():
                query = query.eq(col, val)
        if order_col:
            query = query.order(order_col)
        query = query.range(offset, offset + page_size - 1)
        resp = query.execute()
        rows = resp.data or []
        all_rows.extend(rows)
        if len(rows) < page_size:
            break
        offset += page_size
    return all_rows


def get_latest_round(lottery_type):
    """최신 회차 조회"""
    resp = (supabase.table("winning_history")
            .select("round")
            .eq("lottery_type", lottery_type)
            .order("round", desc=True)
            .limit(1)
            .execute())
    if resp.data:
        return resp.data[0]["round"]
    return 0


def get_winning_rounds_for_codes(codes, lottery_type):
    """판매점별 당첨 회차 목록 (winning_history)"""
    if not codes:
        return {}

    result = defaultdict(list)
    # in 필터는 한번에 너무 많으면 안 됨 → 500개씩 분할
    chunk_size = 500
    for i in range(0, len(codes), chunk_size):
        chunk = codes[i:i+chunk_size]
        resp = (supabase.table("winning_history")
                .select("dhlottery_code, round")
                .eq("lottery_type", lottery_type)
                .in_("dhlottery_code", chunk)
                .order("round")
                .limit(10000)
                .execute())
        for row in (resp.data or []):
            result[row["dhlottery_code"]].append(row["round"])
    return dict(result)


def lottery_label(lottery_type):
    labels = {
        "lotto": "로또",
        "pension": "연금",
        "speedlotto_2000": "스피또2000",
        "speedlotto_1000": "스피또1000",
        "speedlotto_500": "스피또500",
    }
    return labels.get(lottery_type, lottery_type)


def calculate_badges(stores, lottery_type):
    """
    배지 계산 → [{dhlottery_code, lottery_type, badge_type, badge_label, priority}]
    """
    badges = []
    type_label = lottery_label(lottery_type)
    current_round = get_latest_round(lottery_type)

    # 판매점 딕셔너리 (code → store)
    store_map = {}
    for s in stores:
        code = s["dhlottery_code"]
        # 같은 코드가 여러 번 나올 수 있으므로 first_count 등이 큰 것 유지
        if code not in store_map or (s.get("total_count") or 0) > (store_map[code].get("total_count") or 0):
            store_map[code] = s

    unique_stores = list(store_map.values())

    # ── 1) 1등/2등 횟수 배지 ──
    for s in unique_stores:
        code = s["dhlottery_code"]
        fc = s.get("first_count") or 0
        sc = s.get("second_count") or 0
        if fc > 0:
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "first",
                "badge_label": f"{type_label} 1등 {fc}회",
                "priority": 10,
            })
        if sc > 0:
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "second",
                "badge_label": f"{type_label} 2등 {sc}회",
                "priority": 20,
            })

    # ── 2) 주기 분석 (5회 이상 당첨점) ──
    codes_5plus = [s["dhlottery_code"] for s in unique_stores if (s.get("total_count") or 0) >= 5]
    winning_rounds = get_winning_rounds_for_codes(codes_5plus, lottery_type)

    for code, rounds in winning_rounds.items():
        if len(rounds) < 5 or current_round <= 0:
            continue
        rounds_sorted = sorted(rounds)
        intervals = [rounds_sorted[i] - rounds_sorted[i-1] for i in range(1, len(rounds_sorted))]
        avg_interval = sum(intervals) / len(intervals)
        elapsed = current_round - rounds_sorted[-1]

        # 평균 간격 배지
        avg_weeks = round(avg_interval)
        months = round(avg_interval / 4.3)
        if months >= 1:
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "pattern",
                "badge_label": f"평균 {months}개월 주기",
                "priority": 40,
            })

        # "이번주 유력" (평균 간격 ±3 이내)
        if elapsed >= (avg_interval - 3) and elapsed <= (avg_interval + 3):
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "hot",
                "badge_label": f"{months}개월 주기 (이번주 유력!)",
                "priority": 1,
            })

        # "최근 핫" - 최근 10회차 내 2회 이상
        recent_wins = [r for r in rounds_sorted if (current_round - r) <= 10]
        if len(recent_wins) >= 2:
            weeks_span = current_round - recent_wins[0]
            months_span = math.ceil(weeks_span / 4.3)
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "streak",
                "badge_label": f"최근 핫 ({months_span}개월내 {len(recent_wins)}회)",
                "priority": 5,
            })

    # ── 3) 지역 최다 당첨 배지 ──
    # 시/구 단위 1등 최다
    sigu_first = {}  # sigu → (code, first_count, store)
    sigu_total = {}  # sigu → (code, total_count, store)

    for s in unique_stores:
        address = (s.get("address") or "").strip()
        parts = address.split()
        sigu = parts[1] if len(parts) >= 2 else s.get("region", "")
        fc = s.get("first_count") or 0
        tc = s.get("total_count") or 0
        code = s["dhlottery_code"]

        if fc > 0:
            if sigu not in sigu_first or fc > sigu_first[sigu][1]:
                sigu_first[sigu] = (code, fc, s)
        if tc > 0:
            if sigu not in sigu_total or tc > sigu_total[sigu][1]:
                sigu_total[sigu] = (code, tc, s)

    regional_codes = set()
    for sigu, (code, fc, s) in sigu_first.items():
        if fc >= 2:
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "regional",
                "badge_label": f"{sigu} {type_label} 최다1등 당첨",
                "priority": 15,
            })
            regional_codes.add(code)

    for sigu, (code, tc, s) in sigu_total.items():
        if tc >= 3 and code not in regional_codes:
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "regional",
                "badge_label": f"{sigu} {type_label} 최다당첨",
                "priority": 16,
            })

    # ── 4) 지역 등수 (시/구 내 총 당첨 1~3등) ──
    sigu_stores = defaultdict(list)
    for s in unique_stores:
        tc = s.get("total_count") or 0
        if tc <= 0:
            continue
        address = (s.get("address") or "").strip()
        parts = address.split()
        sigu = parts[1] if len(parts) >= 2 else s.get("region", "")
        sigu_stores[sigu].append(s)

    for sigu, ss in sigu_stores.items():
        sorted_ss = sorted(ss, key=lambda x: -(x.get("total_count") or 0))
        for rank_idx, s in enumerate(sorted_ss[:3]):
            rank = rank_idx + 1
            code = s["dhlottery_code"]
            tc = s.get("total_count") or 0
            if tc >= 2:  # 최소 2회 이상만
                badges.append({
                    "dhlottery_code": code,
                    "lottery_type": lottery_type,
                    "badge_type": "rank",
                    "badge_label": f"{sigu} {type_label} {rank}위 ({tc}회)",
                    "priority": 30 + rank,
                })

    return badges


def recalculate(lottery_type=None):
    types_to_process = [lottery_type] if lottery_type else ["lotto", "pension"]

    for lt in types_to_process:
        print(f"\n{'='*50}")
        print(f"📊 {lottery_label(lt)} 배지 재계산 시작...")
        print(f"{'='*50}")

        # 1. 기존 배지 삭제
        print(f"🗑️  기존 {lt} 배지 삭제...")
        supabase.table("store_badges").delete().eq("lottery_type", lt).execute()

        # 2. 판매점 데이터 로드
        print(f"📥 판매점 데이터 로드 중...")
        stores = fetch_all_paginated(
            "lottery_stores",
            select="dhlottery_code, store_name, address, region, first_count, second_count, total_count",
            filters={"lottery_type": lt},
            order_col="dhlottery_code",
        )
        print(f"   → {len(stores)}개 판매점 로드")

        # 3. 배지 계산
        print(f"🔄 배지 계산 중...")
        badges = calculate_badges(stores, lt)
        print(f"   → {len(badges)}개 배지 생성")

        # 4. 배지 저장 (100개씩 배치)
        if badges:
            print(f"💾 배지 저장 중...")
            now = datetime.utcnow().isoformat()
            for b in badges:
                b["calculated_at"] = now

            batch_size = 100
            for i in range(0, len(badges), batch_size):
                batch = badges[i:i+batch_size]
                supabase.table("store_badges").upsert(batch).execute()
                print(f"   → {min(i+batch_size, len(badges))}/{len(badges)} 저장완료")

        # 5. 통계 출력
        by_type = defaultdict(int)
        for b in badges:
            by_type[b["badge_type"]] += 1

        print(f"\n📈 {lottery_label(lt)} 배지 통계:")
        for bt, cnt in sorted(by_type.items()):
            print(f"   {bt}: {cnt}개")

    print(f"\n✅ 배지 재계산 완료!")


if __name__ == "__main__":
    lt = sys.argv[1] if len(sys.argv) > 1 else None
    if lt and lt not in ("lotto", "pension", "speedlotto_2000", "speedlotto_1000", "speedlotto_500"):
        print(f"❌ 알 수 없는 복권 타입: {lt}")
        print("사용 가능: lotto, pension")
        sys.exit(1)
    recalculate(lt)
