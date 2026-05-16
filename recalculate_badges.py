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
    """판매점별 당첨 회차 목록 (winning_history) — prize_tier 구분 없이 전체"""
    if not codes:
        return {}

    result = defaultdict(list)
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


def get_winning_rounds_by_tier(codes, lottery_type):
    """판매점별 등수별 당첨 회차 목록 (winning_history)
    반환: {dhlottery_code: {"first": [rounds], "second": [rounds]}}
    """
    if not codes:
        return {}

    result = defaultdict(lambda: defaultdict(list))
    chunk_size = 500
    for i in range(0, len(codes), chunk_size):
        chunk = codes[i:i+chunk_size]
        resp = (supabase.table("winning_history")
                .select("dhlottery_code, round, prize_tier")
                .eq("lottery_type", lottery_type)
                .in_("dhlottery_code", chunk)
                .order("round")
                .limit(10000)
                .execute())
        for row in (resp.data or []):
            code = row["dhlottery_code"]
            tier = row.get("prize_tier", "first")
            result[code][tier].append(row["round"])
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

    # ── 1.5) 맛집 배지 (상위 10% 기준) ──
    if lottery_type in ("lotto", "pension", "speedlotto_2000", "speedlotto_1000", "speedlotto_500"):
        # 1등 맛집: 1등 횟수 상위 10%
        first_counts = sorted([s.get("first_count") or 0 for s in unique_stores if (s.get("first_count") or 0) > 0], reverse=True)
        if first_counts:
            cutoff_idx = max(1, len(first_counts) // 10)
            first_threshold = first_counts[min(cutoff_idx - 1, len(first_counts) - 1)]
            for s in unique_stores:
                fc = s.get("first_count") or 0
                if fc >= first_threshold and fc > 0:
                    badges.append({
                        "dhlottery_code": s["dhlottery_code"],
                        "lottery_type": lottery_type,
                        "badge_type": "matjip",
                        "badge_label": f"{type_label} 1등 맛집",
                        "priority": 5,
                    })

        # 2등 맛집: 2등 횟수 상위 10% (로또만)
        if lottery_type == "lotto":
            second_counts = sorted([s.get("second_count") or 0 for s in unique_stores if (s.get("second_count") or 0) > 0], reverse=True)
            if second_counts:
                cutoff_idx = max(1, len(second_counts) // 10)
                second_threshold = second_counts[min(cutoff_idx - 1, len(second_counts) - 1)]
                for s in unique_stores:
                    sc = s.get("second_count") or 0
                    if sc >= second_threshold and sc > 0:
                        badges.append({
                            "dhlottery_code": s["dhlottery_code"],
                            "lottery_type": lottery_type,
                            "badge_type": "matjip",
                            "badge_label": f"{type_label} 2등 맛집",
                            "priority": 6,
                        })

            # 3등 맛집 (로또): 총 당첨 횟수 상위 10%
            total_counts = sorted([s.get("total_count") or 0 for s in unique_stores if (s.get("total_count") or 0) > 0], reverse=True)
            if total_counts:
                cutoff_idx = max(1, len(total_counts) // 10)
                total_threshold = total_counts[min(cutoff_idx - 1, len(total_counts) - 1)]
                for s in unique_stores:
                    tc = s.get("total_count") or 0
                    if tc >= total_threshold and tc > 0:
                        badges.append({
                            "dhlottery_code": s["dhlottery_code"],
                            "lottery_type": lottery_type,
                            "badge_type": "matjip",
                            "badge_label": f"{type_label} 3등 맛집",
                            "priority": 7,
                        })

        # 연금복권/스피또 맛집: 총 당첨 횟수 상위 10%
        if lottery_type in ("pension", "speedlotto_2000", "speedlotto_1000", "speedlotto_500"):
            total_counts = sorted([s.get("total_count") or 0 for s in unique_stores if (s.get("total_count") or 0) > 0], reverse=True)
            if total_counts:
                cutoff_idx = max(1, len(total_counts) // 10)
                total_threshold = total_counts[min(cutoff_idx - 1, len(total_counts) - 1)]
                for s in unique_stores:
                    tc = s.get("total_count") or 0
                    if tc >= total_threshold and tc > 0:
                        badges.append({
                            "dhlottery_code": s["dhlottery_code"],
                            "lottery_type": lottery_type,
                            "badge_type": "matjip",
                            "badge_label": "연금복권 맛집" if lottery_type == "pension" else f"{type_label} 맛집",
                            "priority": 5,
                        })

    # ── 2) 당첨 회차 데이터 로드 (2회 이상 당첨점) ── 등수별 분리
    codes_2plus = [s["dhlottery_code"] for s in unique_stores if (s.get("total_count") or 0) >= 2]
    winning_rounds = get_winning_rounds_for_codes(codes_2plus, lottery_type)
    winning_rounds_by_tier = get_winning_rounds_by_tier(codes_2plus, lottery_type)

    # ── 3) 등수별 당첨주기 배지 (1등/2등 각각) ──
    tier_labels = {"first": "1등", "second": "2등"}
    for code, tiers in winning_rounds_by_tier.items():
        if current_round <= 0:
            continue
        for tier, rounds in tiers.items():
            tier_name = tier_labels.get(tier, tier)
            if len(rounds) < 3:
                continue
            rounds_sorted = sorted(rounds)
            intervals = [rounds_sorted[i] - rounds_sorted[i-1] for i in range(1, len(rounds_sorted))]
            avg_interval = sum(intervals) / len(intervals)
            elapsed = current_round - rounds_sorted[-1]

            months = round(avg_interval / 4.3)
            is_due = elapsed >= (avg_interval - 1) and elapsed <= (avg_interval + 1)

            if months >= 1:
                if is_due:
                    pattern_label = f"{type_label} {tier_name} {months}개월 당첨주기 (이번주 예상)"
                else:
                    pattern_label = f"{type_label} {tier_name} {months}개월 당첨주기"
                badges.append({
                    "dhlottery_code": code,
                    "lottery_type": lottery_type,
                    "badge_type": "pattern",
                    "badge_label": pattern_label,
                    "priority": 40 if tier == "first" else 41,
                })

            # "이번주 유력" (1등 주기가 맞을 때만)
            if is_due and tier == "first":
                badges.append({
                    "dhlottery_code": code,
                    "lottery_type": lottery_type,
                    "badge_type": "hot",
                    "badge_label": f"{type_label} {tier_name} {months}개월 주기 (이번주 예상)",
                    "priority": 1,
                })

    # ── 3-2) 크로스 복권 당첨주기 (로또 지점의 연금 주기 / 연금 지점의 로또 주기) ──
    cross_type = "pension" if lottery_type == "lotto" else "lotto"
    cross_label = lottery_label(cross_type)
    cross_round = get_latest_round(cross_type)
    cross_rounds_by_tier = get_winning_rounds_by_tier(codes_2plus, cross_type)

    for code, tiers in cross_rounds_by_tier.items():
        if cross_round <= 0:
            continue
        for tier, rounds in tiers.items():
            tier_name = tier_labels.get(tier, tier)
            if len(rounds) < 3:
                continue
            rounds_sorted = sorted(rounds)
            intervals = [rounds_sorted[i] - rounds_sorted[i-1] for i in range(1, len(rounds_sorted))]
            avg_interval = sum(intervals) / len(intervals)
            elapsed = cross_round - rounds_sorted[-1]

            months = round(avg_interval / 4.3)
            is_due = elapsed >= (avg_interval - 1) and elapsed <= (avg_interval + 1)

            if months >= 1:
                if is_due:
                    pattern_label = f"{cross_label} {tier_name} {months}개월 당첨주기 (이번주 예상)"
                else:
                    pattern_label = f"{cross_label} {tier_name} {months}개월 당첨주기"
                badges.append({
                    "dhlottery_code": code,
                    "lottery_type": lottery_type,
                    "badge_type": "pattern",
                    "badge_label": pattern_label,
                    "priority": 42,
                })

    # ── 4) 이번 달 N회 당첨 ──
    # 최근 4회차(약 1개월) 내 2회 이상 당첨
    for code, rounds in winning_rounds.items():
        if current_round <= 0:
            continue
        rounds_sorted = sorted(rounds)
        this_month_wins = [r for r in rounds_sorted if (current_round - r) <= 4]
        if len(this_month_wins) >= 2:
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "streak",
                "badge_label": f"이번 달 {len(this_month_wins)}회 당첨",
                "priority": 3,
            })

    # ── 5) 최근 연속 당첨 (연속 회차 당첨) ──
    for code, rounds in winning_rounds.items():
        if current_round <= 0:
            continue
        rounds_sorted = sorted(rounds, reverse=True)
        # 최근 회차부터 연속 체크
        consecutive = 1
        for i in range(1, len(rounds_sorted)):
            if rounds_sorted[i-1] - rounds_sorted[i] == 1:
                consecutive += 1
            else:
                break
        # 최근 연속 2회차 이상 + 가장 최근 당첨이 5회차 이내
        if consecutive >= 2 and (current_round - rounds_sorted[0]) <= 5:
            badges.append({
                "dhlottery_code": code,
                "lottery_type": lottery_type,
                "badge_type": "streak",
                "badge_label": f"최근 연속 {consecutive}회차 당첨",
                "priority": 2,
            })

    # ── 주소 파싱 헬퍼 ──
    def _parse_address(address):
        """주소에서 시, 구, 동 추출"""
        parts = (address or "").strip().split()
        si = parts[0] if len(parts) >= 1 else ""    # 서울특별시, 경기도 등
        gu = parts[1] if len(parts) >= 2 else ""     # 강남구, 수원시 등
        dong = parts[2] if len(parts) >= 3 else ""   # 역삼동, 팔달구 등
        return si, gu, dong

    # ── 6) 동 1위 판매점 ──
    dong_stores = defaultdict(list)
    for s in unique_stores:
        tc = s.get("total_count") or 0
        if tc <= 0:
            continue
        si, gu, dong = _parse_address(s.get("address"))
        if dong:
            dong_key = f"{gu} {dong}" if gu else dong
            dong_stores[dong_key].append(s)

    for dong_key, ss in dong_stores.items():
        if len(ss) < 2:
            continue  # 동에 판매점이 2개 이상일 때만
        sorted_ss = sorted(ss, key=lambda x: -(x.get("total_count") or 0))
        top = sorted_ss[0]
        tc = top.get("total_count") or 0
        if tc >= 2:
            badges.append({
                "dhlottery_code": top["dhlottery_code"],
                "lottery_type": lottery_type,
                "badge_type": "rank",
                "badge_label": f"{dong_key} 1위 판매점",
                "priority": 25,
            })

    # ── 7) 시 TOP3 ──
    si_stores = defaultdict(list)
    for s in unique_stores:
        tc = s.get("total_count") or 0
        if tc <= 0:
            continue
        si, gu, dong = _parse_address(s.get("address"))
        if si:
            si_stores[si].append(s)

    for si, ss in si_stores.items():
        sorted_ss = sorted(ss, key=lambda x: -(x.get("total_count") or 0))
        for rank_idx, s in enumerate(sorted_ss[:3]):
            rank = rank_idx + 1
            code = s["dhlottery_code"]
            tc = s.get("total_count") or 0
            if tc >= 3:
                badges.append({
                    "dhlottery_code": code,
                    "lottery_type": lottery_type,
                    "badge_type": "rank",
                    "badge_label": f"{si} TOP{rank} ({tc}회)",
                    "priority": 26 + rank,
                })

    # ── 8) 지역 최다당첨 배지 ──
    sigu_first = {}  # sigu → (code, first_count, store)
    sigu_total = {}  # sigu → (code, total_count, store)

    for s in unique_stores:
        si, gu, dong = _parse_address(s.get("address"))
        sigu = gu if gu else s.get("region", "")
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
                "badge_label": f"{sigu} 지역 최다당첨 ({tc}회)",
                "priority": 16,
            })

    # ── 9) 구 내 등수 (기존) ──
    gu_stores = defaultdict(list)
    for s in unique_stores:
        tc = s.get("total_count") or 0
        if tc <= 0:
            continue
        si, gu, dong = _parse_address(s.get("address"))
        sigu = gu if gu else s.get("region", "")
        gu_stores[sigu].append(s)

    for sigu, ss in gu_stores.items():
        sorted_ss = sorted(ss, key=lambda x: -(x.get("total_count") or 0))
        for rank_idx, s in enumerate(sorted_ss[:3]):
            rank = rank_idx + 1
            code = s["dhlottery_code"]
            tc = s.get("total_count") or 0
            if tc >= 2:
                badges.append({
                    "dhlottery_code": code,
                    "lottery_type": lottery_type,
                    "badge_type": "rank",
                    "badge_label": f"{sigu} {type_label} {rank}위 ({tc}회)",
                    "priority": 30 + rank,
                })

    return badges


def recalculate(lottery_type=None):
    types_to_process = [lottery_type] if lottery_type else ["lotto", "pension", "speedlotto_2000", "speedlotto_1000", "speedlotto_500"]

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

    # ── 복권명당 TOP 5 배지 (홈 랭킹 기준, 전체 재계산 시에만) ──
    if lottery_type is None:
        print(f"\n{'='*50}")
        print(f"🏆 복권명당 TOP 5 배지 계산...")
        print(f"{'='*50}")

        # 기존 복권명당 배지 삭제
        supabase.table("store_badges").delete().eq("badge_type", "myeongdang").execute()

        # 홈 랭킹과 동일 기준: 로또 first_count DESC, total_count DESC 상위 30 중 TOP 5
        top_stores = (supabase.table("lottery_stores")
                      .select("dhlottery_code, store_name, first_count, total_count")
                      .eq("lottery_type", "lotto")
                      .gt("first_count", 0)
                      .order("first_count", desc=True)
                      .order("total_count", desc=True)
                      .limit(5)
                      .execute())

        now = datetime.utcnow().isoformat()
        md_badges = []
        for rank_idx, s in enumerate(top_stores.data or []):
            rank = rank_idx + 1
            md_badges.append({
                "dhlottery_code": s["dhlottery_code"],
                "lottery_type": "lotto",
                "badge_type": "myeongdang",
                "badge_label": f"복권명당 TOP {rank}위",
                "priority": 0,
                "calculated_at": now,
            })

        if md_badges:
            supabase.table("store_badges").upsert(md_badges).execute()
            for b in md_badges:
                print(f"   🏅 {b['badge_label']}: {b['dhlottery_code']}")

        print(f"   → {len(md_badges)}개 복권명당 배지 생성")

    print(f"\n✅ 배지 재계산 완료!")


if __name__ == "__main__":
    lt = sys.argv[1] if len(sys.argv) > 1 else None
    if lt and lt not in ("lotto", "pension", "speedlotto_2000", "speedlotto_1000", "speedlotto_500"):
        print(f"❌ 알 수 없는 복권 타입: {lt}")
        print("사용 가능: lotto, pension")
        sys.exit(1)
    recalculate(lt)
