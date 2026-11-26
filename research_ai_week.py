"""
제미나이 요일 나눠 돌리기 (research-strategy.yml 첫 단계) — 서버 전용 · 읽기만

제미나이 무료 한도(하루 20번 · 17:00 KST 에 풀림)를 한 번에 다 쓰지 않게, 매일 17:05 KST 에 그날 몫만 돌린다.
  월: 7183 에이전트 · AI 브리핑전담부서(복기)   화: AI 전략기획부   수: 연금 추리   목: 스피또 추리
  금 · 토 · 일: 자동으로는 돌지 않는다 (2026-11-27 사용자 지시 — 금요일 자동 재시도 대신 수동으로 고름)
연구소 › AI 부서: 단계별 [재시도] = 그 몫만 (--parts) · 위쪽 [새로고침] = 이번 주에 실패 · 빠진 것 모두(없으면 오늘 몫)

출력: GITHUB_OUTPUT 에 parts=a7183,review,... (빈 값이면 제미나이 단계 모두 건너뜀)
앱 브리핑 진척도(ai_dept_status.dart AiWeekPlan)와 같은 표 — 바꾸면 같이 바꿀 것.
"""

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone

import requests

KST = timezone(timedelta(hours=9))
# 요일(월=0) → 그날 몫
PLAN = {0: ["a7183", "review"], 1: ["direction"], 2: ["pension"], 3: ["speetto"]}
ALL = [p for d in sorted(PLAN) for p in PLAN[d]]
DAY_OF = {p: d for d, ps in PLAN.items() for p in ps}
KIND = {"direction": "ai_direction", "pension": "ai_pension", "speetto": "ai_speetto"}


def week_start(now):
    """이번 주 월요일 0시 KST (UTC 로)"""
    k = now.astimezone(KST)
    return (k - timedelta(days=k.weekday())).replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)


def parts_for(now, done, manual=False):
    """오늘 돌릴 몫 (순수 함수 — selfcheck 대상). done: 몫 → 이번 주 성공 여부"""
    wd = now.astimezone(KST).weekday()
    missed = [p for p in ALL if DAY_OF[p] <= min(wd, 4) and not done.get(p)]
    if manual:
        return missed or PLAN.get(wd, [])
    return PLAN.get(wd, [])   # 금 · 토 · 일은 계획이 없어 빈 목록


def chosen(explicit, now, done):
    """단계별 [재시도]로 고른 몫 — 'auto' 가 섞여 있으면 이번 주 실패 · 빠진 것도 더한다 (순수 함수)"""
    want = set(explicit) & set(ALL)
    if "auto" in explicit:
        want |= set(parts_for(now, done, True))
    return [p for p in ALL if p in want]


def week_done(get, now):
    """이번 주 몫별 성공 여부 (DB 저장본)"""
    latest = get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})[0]["round"]
    nxt = latest + 1
    a = get("research_results", {"select": "source:payload->>source", "research_type": "eq.agent_7183",
                                 "target_round": f"eq.{nxt}", "order": "created_at.desc", "limit": "1"})
    rv = get("research_results", {"select": "source:payload->>source", "research_type": "eq.set_review", "model_version": "eq.sr-1.0",
                                  "target_round": f"eq.{nxt}", "limit": "1"})
    since = week_start(now).isoformat()
    runs = get("strategy_runs", {"select": "kind,status", "kind": "in.(ai_direction,ai_pension,ai_speetto)",
                                 "created_at": f"gte.{since}"})
    ok = {r["kind"] for r in runs if r["status"] in ("success", "skipped")}
    return {
        "a7183": bool(a and a[0].get("source") in ("gemini", "claude")),   # claude = 제미나이 대신 쓴 주 (research_7183.AI_SOURCES)
        "review": bool(rv and rv[0].get("source") == "gemini"),
        **{p: KIND[p] in ok for p in KIND},
    }


def selfcheck():
    mon = datetime(2026, 11, 23, 8, 5, tzinfo=timezone.utc)  # 월 17:05 KST
    assert week_start(mon) == datetime(2026, 11, 22, 15, 0, tzinfo=timezone.utc)
    assert parts_for(mon, {}) == ["a7183", "review"]
    assert parts_for(mon + timedelta(days=1), {}) == ["direction"]
    fri = mon + timedelta(days=4)
    assert parts_for(fri, {"a7183": True, "review": True, "direction": False, "pension": True, "speetto": True}) == []   # 금요일 자동 재시도 없음
    assert parts_for(fri, {"direction": False, "a7183": True, "review": True, "pension": True, "speetto": True}, manual=True) == ["direction"]
    assert chosen(["pension", "x"], fri, {}) == ["pension"] and chosen(["speetto", "a7183"], fri, {}) == ["a7183", "speetto"]
    assert chosen(["auto", "speetto"], mon + timedelta(days=1), {"a7183": True, "review": True, "direction": True}) == ["direction", "speetto"]   # 빠진 것이 없으면 auto = 오늘 몫
    assert parts_for(mon + timedelta(days=5), {}) == []                        # 토
    assert parts_for(mon + timedelta(days=1), {"a7183": False}, manual=True) == ["a7183", "review", "direction"]
    assert parts_for(mon + timedelta(days=2), {p: True for p in ALL}, manual=True) == ["pension"]
    print("selfcheck ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manual", action="store_true", help="연구소 새로고침 — 이번 주 실패 · 빠진 것만")
    ap.add_argument("--parts", default="", help="단계별 재시도로 고른 몫 (쉼표로 · auto = 이번 주 실패 · 빠진 것)")
    ap.add_argument("--selfcheck", action="store_true")
    a = ap.parse_args()
    if a.selfcheck:
        return selfcheck()
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
    h = {"apikey": key}
    if not key.startswith("sb_"):
        h["Authorization"] = f"Bearer {key}"

    def get(t, p):
        r = requests.get(url.rstrip("/") + "/rest/v1/" + t, params=p, headers=h, timeout=60)
        r.raise_for_status()
        return r.json()

    now = datetime.now(timezone.utc)
    try:
        done = week_done(get, now)
    except Exception as e:  # 못 읽으면 오늘 몫만
        print(f"이번 주 상태 못 읽음 — 오늘 몫만: {e}")
        done = {}
    explicit = [x for x in a.parts.split(",") if x]
    parts = chosen(explicit, now, done) if explicit else parts_for(now, done, a.manual)
    print(f"이번 주 상태: {done}")
    print(f"오늘 돌릴 제미나이 몫: {parts or '없음'}")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(f"parts={','.join(parts)}\n")


if __name__ == "__main__":
    main()
