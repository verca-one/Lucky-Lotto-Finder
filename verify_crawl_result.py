"""
크롤링 완료 후 DB 검증 스크립트
공식 최신 회차와 DB 최대 회차가 일치하는지 확인
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


def get_db_latest(game_type: str) -> int:
    result = sb.table("winning_history") \
        .select("round") \
        .eq("lottery_type", game_type) \
        .eq("prize_tier", "first") \
        .order("round", desc=True) \
        .limit(1) \
        .execute()
    return result.data[0]["round"] if result.data else 0


def get_official_latest_lotto() -> int:
    """로또 공식 최신 회차 조회"""
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
        'User-Agent': 'Mozilla/5.0',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
    }

    for try_round in range(estimated + 5, max(estimated - 5, 1), -1):
        try:
            url = f"https://www.dhlottery.co.kr/common.do?method=getLottoNumber&drwNo={try_round}"
            resp = session.get(url, headers=headers, timeout=30, verify=False)
            data = resp.json()
            if data.get("returnValue") == "success":
                return try_round
        except Exception:
            pass
    return 0


def get_official_latest_pension() -> int:
    """연금복권 공식 최신 회차 조회"""
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
    headers = {
        'User-Agent': 'Mozilla/5.0',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
    }

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

    db_latest = get_db_latest(game_type)
    logger.info(f"[{game_type}] DB 최대 회차: {db_latest}회")

    if game_type == "lotto":
        official_latest = get_official_latest_lotto()
    elif game_type == "pension":
        official_latest = get_official_latest_pension()
    else:
        # 스피또는 검증 생략
        logger.info(f"[{game_type}] 스피또 검증 생략")
        sys.exit(0)

    logger.info(f"[{game_type}] 공식 최신 회차: {official_latest}회")

    if official_latest == 0:
        logger.warning(f"[{game_type}] 공식 최신 회차 조회 실패 - 검증 생략")
        sys.exit(0)

    if db_latest >= official_latest:
        logger.info(f"[{game_type}] ✅ 업데이트 완료: DB({db_latest}회) == 공식({official_latest}회)")
        # 환경 변수로 회차 정보 출력 (워크플로우에서 캡처용)
        print(f"CRAWL_ROUND_{game_type.upper()}={official_latest}")
        sys.exit(0)
    else:
        missing = list(range(db_latest + 1, official_latest + 1))
        logger.error(f"[{game_type}] ❌ 업데이트 불완전: DB({db_latest}회) < 공식({official_latest}회)")
        logger.error(f"[{game_type}] 누락 회차: {missing}")
        sys.exit(1)
