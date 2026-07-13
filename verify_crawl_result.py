"""
크롤링 완료 후 DB 검증 스크립트
A. 회차 검증: round_crawl_status 최대 회차 vs 공식 최신 회차
B. 판매점 검증: stores_status=success 여부 (실패해도 전체 실패 처리 안 함)
"""
import sys
import os
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

from supabase import create_client

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "")

if not SUPABASE_URL or not SUPABASE_KEY:
    logger.error("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
    sys.exit(1)

sb = create_client(SUPABASE_URL, SUPABASE_KEY)


def get_db_latest_round(game_type: str) -> int:
    """round_crawl_status에서 가장 최근 확인된 회차 (판매점 유무 무관)"""
    try:
        result = sb.table("round_crawl_status") \
            .select("round") \
            .eq("lottery_type", game_type) \
            .order("round", desc=True) \
            .limit(1) \
            .execute()
        if result.data:
            return result.data[0]["round"]
    except Exception:
        pass
    # fallback: round_crawl_status 없으면 winning_history
    try:
        result = sb.table("winning_history") \
            .select("round") \
            .eq("lottery_type", game_type) \
            .eq("prize_tier", "first") \
            .order("round", desc=True) \
            .limit(1) \
            .execute()
        return result.data[0]["round"] if result.data else 0
    except Exception:
        return 0


def get_store_status_summary(game_type: str, latest_round: int, lookback: int = 10) -> dict:
    """최근 lookback개 회차의 판매점 저장 상태 요약"""
    from_round = max(1, latest_round - lookback + 1)
    try:
        result = sb.table("round_crawl_status") \
            .select("round,stores_status") \
            .eq("lottery_type", game_type) \
            .gte("round", from_round) \
            .lte("round", latest_round) \
            .order("round", desc=True) \
            .execute()
        rows = result.data or []
    except Exception:
        rows = []

    success = [r["round"] for r in rows if r["stores_status"] == "success"]
    pending = [r["round"] for r in rows if r["stores_status"] in ("pending", "empty", "failed")]
    return {"success": sorted(success), "pending": sorted(pending)}


def get_official_latest_lotto() -> int:
    """selectLtWnShp.do 판매점 API로 최신 회차 탐색 (common.do는 GitHub Actions에서 차단됨)"""
    import requests
    from datetime import date, timedelta
    import urllib3
    urllib3.disable_warnings()

    today = date.today()
    base_date = date(2002, 12, 7)
    days_since_saturday = (today.weekday() + 2) % 7
    last_saturday = today - timedelta(days=days_since_saturday)
    estimated = (last_saturday - base_date).days // 7 + 1

    session = requests.Session()
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': 'https://www.dhlottery.co.kr/wnprchsplcsrch/selectWnPrchsPlcList.do',
        'Cache-Control': 'no-cache',
    }

    for try_round in range(estimated + 5, max(estimated - 10, 1), -1):
        try:
            url = "https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
            params = {"srchWnShpRnk": "all", "srchLtEpsd": try_round, "srchShpLctn": ""}
            resp = session.get(url, params=params, headers=headers, timeout=30, verify=False)
            data = resp.json()
            if data.get("data") and data["data"].get("list") and len(data["data"]["list"]) > 0:
                return try_round
        except Exception:
            pass
    return 0


def get_official_latest_pension() -> int:
    import requests
    from datetime import date, timedelta
    import urllib3
    urllib3.disable_warnings()

    today = date.today()
    base_date = date(2020, 4, 2)
    days_since_thursday = (today.weekday() - 3) % 7
    last_thursday = today - timedelta(days=days_since_thursday)
    estimated = (last_thursday - base_date).days // 7 + 1

    session = requests.Session()
    headers = {'User-Agent': 'Mozilla/5.0', 'Cache-Control': 'no-cache'}

    for try_round in range(estimated + 5, max(estimated - 10, 1), -1):
        try:
            url = "https://www.dhlottery.co.kr/wnprchsplcsrch/selectPtWnShp.do"
            params = {"srchWnShpRnk": "all", "srchLtEpsd": try_round, "srchShpLctn": ""}
            resp = session.get(url, params=params, headers=headers, timeout=30, verify=False)
            data = resp.json()
            if data.get("data") and data["data"].get("list") and len(data["data"]["list"]) > 0:
                return try_round
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    game_type = sys.argv[1] if len(sys.argv) > 1 else "lotto"

    logger.info(f"[{game_type}] 크롤링 결과 DB 검증 시작...")

    # ── A. 회차 검증 ──────────────────────────────────────────────
    db_latest = get_db_latest_round(game_type)
    logger.info(f"[{game_type}] DB 최신 회차: {db_latest}회")

    if game_type == "lotto":
        official_latest = get_official_latest_lotto()
    elif game_type == "pension":
        official_latest = get_official_latest_pension()
    else:
        logger.info(f"[{game_type}] 스피또 검증 생략")
        sys.exit(0)

    logger.info(f"[{game_type}] 공식 최신 회차: {official_latest}회")

    if official_latest == 0:
        logger.warning(f"[{game_type}] 공식 최신 회차 조회 실패 - 검증 생략")
        if db_latest > 0:
            print(f"CRAWL_ROUND_{game_type.upper()}={db_latest}")
        sys.exit(0)

    round_ok = db_latest >= official_latest

    if round_ok:
        logger.info(f"[{game_type}] ✅ A. 회차 검증 성공: DB({db_latest}회) >= 공식({official_latest}회)")
        print(f"CRAWL_ROUND_{game_type.upper()}={official_latest}")
    else:
        missing = list(range(db_latest + 1, official_latest + 1))
        logger.error(f"[{game_type}] ❌ A. 회차 검증 실패: DB({db_latest}회) < 공식({official_latest}회)")
        logger.error(f"[{game_type}] 누락 회차: {missing}")

    # ── B. 판매점 검증 (실패해도 exit code에 영향 없음) ──────────
    store_summary = get_store_status_summary(game_type, official_latest, lookback=10)
    if store_summary["success"]:
        logger.info(f"[{game_type}] ✅ B. 판매점 저장 완료: {store_summary['success']}")
    if store_summary["pending"]:
        logger.warning(f"[{game_type}] ⏳ B. 판매점 재수집 대기: {store_summary['pending']}")
        logger.warning(f"[{game_type}]    재수집 명령: python lotto_verca_crawler.py {game_type}-stores")
    if not store_summary["success"] and not store_summary["pending"]:
        logger.info(f"[{game_type}] B. 판매점 상태 정보 없음 (round_crawl_status 미사용 이전 버전)")

    # 판매점 미완료는 부분 완료 - 회차 검증 결과만 exit code에 반영
    sys.exit(0 if round_ok else 1)
