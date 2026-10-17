"""
다음 회차 예측 실행 시점 (서버 공통 규칙)

  · 추첨(토) 후 바로 예측하지 않는다. 지난 회차 검증·지방장 복기를 먼저 하고,
    다음 회차 추천번호 엔진은 수요일 0시(KST)에 자동 실행한다.
  · 그 전에 필요하면 관리자가 앱의 [수동 추천]으로 엔진 실행을 요청한다 (research_engine_requests, 회차당 1번).
  · 요청은 research_request_poll.py(10분마다)가 research-engine.yml 을 바로 실행시킨다.
이 파일은 판단만 한다 (DB 읽기). 크롤링 테이블은 lotto_winning_numbers 만 읽는다.
"""

from datetime import datetime, timedelta, timezone

RELEASE_DAYS = 4   # 토요일 추첨 + 4일 = 수요일


def release_at_utc(prev_draw_date, prev_round=None):
    """목표 회차 자동 실행 시각(UTC) = 직전 회차 추첨일 + 4일 0시 KST (= 화요일 15:00 UTC)"""
    try:
        d = datetime.strptime(str(prev_draw_date)[:10].replace(".", "-"), "%Y-%m-%d")
    except (TypeError, ValueError):
        if prev_round is None:
            return None
        d = datetime(2002, 12, 7) + timedelta(days=7 * (prev_round - 1))
    return datetime(d.year, d.month, d.day, tzinfo=timezone.utc) + timedelta(days=RELEASE_DAYS) - timedelta(hours=9)


def manual_request(get, target):
    """수동 추천 요청 행 (테이블이 아직 없으면 None)"""
    try:
        rows = get("research_engine_requests", {"select": "target_round,requested_at,status,dispatched_at,done_at",
                                                "target_round": f"eq.{target}"})
    except Exception:
        return None
    return rows[0] if rows else None


def prediction_allowed(get, target, prev_draw_date, prev_round, now=None):
    """(실행 가능 여부, 사유, 수동 요청 행)"""
    now = now or datetime.now(timezone.utc)
    req = manual_request(get, target)
    if req:
        return True, f"수동 추천 요청 ({req['requested_at'][:16]})", req
    at = release_at_utc(prev_draw_date, prev_round)
    if at is None or now >= at:
        return True, "수요일 0시 자동 실행", None
    k = at + timedelta(hours=9)
    return False, f"예측 대기: {k.month}/{k.day}(수) 0시 자동 실행 · 앱 [수동 추천]으로 먼저 실행 가능", None
