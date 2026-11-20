"""
수동 추천 요청 처리 (research-request-poll.yml, 10분마다) — 서버 전용

앱 [수동 추천] → research_engine_requests 에 (목표 회차) 요청 1행
이 스크립트: 요청이 있고 그 회차 엔진이 아직 성공하지 않았으면 research-engine.yml 을 바로 실행시킨다 (GITHUB_TOKEN).
  pending    → 실행 요청 후 dispatched
  dispatched → 45분 지나도 성공 기록이 없으면 다시 실행 요청 (데이터 준비 대기 등)
  성공 기록이 생기면 done
앱 [토요일 최종본 지금 반영] → research_weekly_requests → research-weekly.yml 을 바로 실행 (토요일 점검 기록이 생기면 done)
최신 회차 + 1 이 아닌 요청은 무시한다. 외부 사이트 접속 없음 (DB · GitHub API 만).
"""

import os
import sys
from datetime import datetime, timedelta, timezone

import requests

PIPELINE_VERSION = "sp-1.0"
REDISPATCH_MIN = 45


def main():
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    token, repo = os.environ.get("GH_TOKEN", ""), os.environ.get("GITHUB_REPOSITORY", "")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
    base = url.rstrip("/") + "/rest/v1/"
    h = {"apikey": key, "Content-Type": "application/json"}
    if not key.startswith("sb_"):
        h["Authorization"] = f"Bearer {key}"

    def get(t, p):
        r = requests.get(base + t, params=p, headers=h, timeout=60)
        r.raise_for_status()
        return r.json()

    def patch(t, p, row):
        r = requests.patch(base + t, params=p, headers=dict(h, Prefer="return=minimal"), json=row, timeout=60)
        r.raise_for_status()

    latest = get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})[0]["round"]
    now = datetime.now(timezone.utc)

    def engine_done(t):
        return bool(get("research_pipeline_runs", {"select": "id", "pipeline_version": f"eq.{PIPELINE_VERSION}",
                                                   "target_round": f"eq.{t}", "status": "eq.success", "limit": "1"}))

    def weekly_done(t):
        rows = get("research_results", {"select": "payload->sat", "research_type": "eq.weekly_digest", "model_version": "eq.wd-1.0",
                                        "target_round": f"eq.{t}", "limit": "1"})
        return bool(rows and rows[0].get("sat"))

    # (요청 테이블, 실행할 워크플로, 완료 판단, 이름)
    for table, wf, is_done, name in [("research_engine_requests", "research-engine.yml", engine_done, "수동 추천 → Research Engine"),
                                     ("research_weekly_requests", "research-weekly.yml", weekly_done, "토요일 최종본 지금 반영 → Research Weekly Check")]:
        try:
            reqs = get(table, {"select": "*", "status": "neq.done", "order": "target_round.desc"})
        except requests.HTTPError as e:
            print(f"{table} 없음 또는 조회 실패 — 건너뜀 ({e.response.status_code})")
            continue
        if not reqs:
            print(f"{name} 요청 없음")
            continue
        for r in reqs:
            t = r["target_round"]
            if t != latest + 1:
                print(f"{t}회 요청 — 현재 목표({latest + 1}회)가 아니므로 무시")
                continue
            if is_done(t):
                patch(table, {"target_round": f"eq.{t}"}, {"status": "done", "done_at": now.isoformat()})
                print(f"{t}회 {name} 이미 완료 — 요청 완료 처리")
                continue
            last = r.get("dispatched_at")
            if r["status"] == "dispatched" and last:
                age = now - datetime.fromisoformat(last.replace("Z", "+00:00"))
                if age < timedelta(minutes=REDISPATCH_MIN):
                    print(f"{t}회 실행 요청 후 {int(age.total_seconds() // 60)}분 — 대기")
                    continue
            if not token or not repo:
                print("GH_TOKEN / GITHUB_REPOSITORY 없음 — 실행 요청 불가")
                continue
            res = requests.post(f"https://api.github.com/repos/{repo}/actions/workflows/{wf}/dispatches",
                                headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
                                json={"ref": "main"}, timeout=30)
            if res.status_code != 204:
                print(f"{wf} 실행 요청 실패 {res.status_code} {res.text[:200]}")
                continue
            patch(table, {"target_round": f"eq.{t}"}, {"status": "dispatched", "dispatched_at": now.isoformat()})
            print(f"{t}회 {name} 실행 요청")


if __name__ == "__main__":
    main()
