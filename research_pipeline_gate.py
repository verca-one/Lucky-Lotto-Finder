"""
서버 연구 파이프라인 실행 여부 판단 (research-engine.yml 첫 단계) — DB 읽기 + 실행 기록만, 외부 사이트 접속 없음

실행 조건 (모두 충족해야 run=true)
  1. 최신 회차 당첨번호 있음 (lotto_winning_numbers)
  2. 최신 회차 판매점 크롤링 완료 표시 (round_crawl_status.stores_status = success)
  3. 최신 회차 2등 판매점 기록 있음, 1등 판매점 기록 ≥ 1등 당첨자 수의 80% (research_agent_worker.ready_latest 와 같은 규칙)
  4. 같은 (파이프라인 버전, 목표 회차) 성공 기록 없음 (FORCE=true 면 무시하지 않음 — 성공 기록은 다시 만들지 않는다)
  5. 예측 실행 시점: 월요일 0시(KST) 이후, 또는 앱 [수동 추천] 요청이 있음 (research_release.py)
     — 추첨 후 바로 예측하지 않고 지난 회차 검증을 먼저 한다
준비가 안 됐으면 실행하지 않고 'waiting' 기록만 남긴다. 3시간 넘게 running 인 기록은 failed(timeout)로 정리한다.

출력 (GITHUB_OUTPUT): run, latest, target
"""

import os
import re
import sys
from datetime import datetime, timedelta, timezone

import requests

from research_release import prediction_allowed

PIPELINE_VERSION = "sp-1.0"   # tool/server/research_pipeline_test.dart 와 같아야 한다
STALE_HOURS = 3


class Db:
    def __init__(self, url, key):
        self.base = url.rstrip("/") + "/rest/v1/"
        self.h = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}

    def get(self, table, params):
        r = requests.get(self.base + table, params=params, headers=self.h, timeout=60)
        if r.status_code != 200:
            raise RuntimeError(f"select {table} {r.status_code} {r.text[:200]}")
        return r.json()

    def count(self, table, params):
        h = dict(self.h, Prefer="count=exact", Range="0-0")
        r = requests.get(self.base + table, params=dict(params, select="round"), headers=h, timeout=60)
        if r.status_code not in (200, 206):
            raise RuntimeError(f"count {table} {r.status_code} {r.text[:200]}")
        return int(r.headers.get("Content-Range", "*/0").split("/")[-1])

    def post(self, table, row):
        r = requests.post(self.base + table, headers=dict(self.h, Prefer="return=minimal"), json=row, timeout=60)
        if r.status_code not in (200, 201, 204):
            raise RuntimeError(f"insert {table} {r.status_code} {r.text[:200]}")

    def patch(self, table, params, row):
        r = requests.patch(self.base + table, params=params, headers=dict(self.h, Prefer="return=minimal"),
                           json=row, timeout=60)
        if r.status_code not in (200, 204):
            raise RuntimeError(f"patch {table} {r.status_code} {r.text[:200]}")


def now():
    return datetime.now(timezone.utc)


def readiness(db, latest):
    """최신 회차 준비 여부와 미준비 사유"""
    why = []
    rcs = db.get("round_crawl_status", {"select": "stores_status", "lottery_type": "eq.lotto", "round": f"eq.{latest}"})
    if not rcs or rcs[0].get("stores_status") != "success":
        why.append(f"판매점 크롤링 완료 표시 없음({rcs[0].get('stores_status') if rcs else '행 없음'})")
    first = db.count("winning_history", {"lottery_type": "eq.lotto", "round": f"eq.{latest}", "prize_tier": "eq.first"})
    second = db.count("winning_history", {"lottery_type": "eq.lotto", "round": f"eq.{latest}", "prize_tier": "eq.second"})
    p = db.get("research_prize_stats", {"select": "rank1_winners,auto_winners,semi_auto_winners,manual_winners",
                                        "round": f"eq.{latest}"})
    p1 = p[0].get("rank1_winners") if p else None
    if second == 0:
        why.append("2등 판매점 기록 없음")
    if first == 0 and p1 != 0:
        why.append("1등 판매점 기록 없음")
    elif p1 and first < need_first(p[0]):
        why.append(f"1등 판매점 기록 부족 {first}/{p1} (최소 {need_first(p[0])})")
    return why


def need_first(p):
    """1등 판매점 기록 최소 수 — 수동은 한 사람이 같은 판매점에서 같은 번호를 여러 장 사는 경우가 많아
    판매점 기록 1건으로 남는다 (1247회: 1등 8명 = 자동 5 + 수동 3, 판매점 기록 6 = 자동 5 + 수동 1).
    자동·반자동 수 + 수동 있으면 1. 내역이 없으면 이전 기준(1등 수의 80%)."""
    a, s, m = p.get("auto_winners"), p.get("semi_auto_winners"), p.get("manual_winners")
    if a is None or s is None or m is None:
        return 0.8 * (p.get("rank1_winners") or 0)
    return a + s + (1 if m > 0 else 0)


def output(**kv):
    path = os.environ.get("GITHUB_OUTPUT")
    lines = [f"{k}={v}" for k, v in kv.items()]
    print("\n".join(lines))
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


def record_failure(db, log_path):
    """엔진 단계가 실행 기록을 남기기 전에 죽은 경우(컴파일·초기화 오류 등) 로그 끝부분을 failed 로 남긴다."""
    try:
        lines = open(log_path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        lines = ["(로그 파일 없음)"]
    tail = "\n".join(lines[-60:])
    tail = re.sub(r"sb_(secret|publishable)_[A-Za-z0-9_\-]+", "sb_***", tail)
    tail = re.sub(r"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+", "jwt_***", tail)
    nums = db.get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})
    latest = int(nums[0]["round"]) if nums else 0
    running = db.get("research_pipeline_runs", {"select": "id", "pipeline_version": f"eq.{PIPELINE_VERSION}",
                                                "status": "eq.running", "limit": "1"})
    row = {"status": "failed", "error": tail[-4000:], "finished_at": now().isoformat()}
    if running:   # 실행 기록을 만든 뒤 프로세스가 죽은 경우
        db.patch("research_pipeline_runs", {"id": f"eq.{running[0]['id']}"}, row)
    else:
        db.post("research_pipeline_runs", dict(row, pipeline_version=PIPELINE_VERSION, latest_round=latest,
                                               target_round=latest + 1, trigger=os.environ.get("GITHUB_EVENT_NAME"),
                                               runner=os.environ.get("GITHUB_RUN_ID")))
    print("엔진 실패 기록 저장")


def main():
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        print("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
        sys.exit(1)
    db = Db(url, key)
    if len(sys.argv) > 2 and sys.argv[1] == "--record-failure":
        record_failure(db, sys.argv[2])
        return

    # 오래된 running 정리 (실행 중 중단된 기록이 다음 실행을 막지 않게)
    cutoff = (now() - timedelta(hours=STALE_HOURS)).isoformat()
    db.patch("research_pipeline_runs",
             {"pipeline_version": f"eq.{PIPELINE_VERSION}", "status": "eq.running", "started_at": f"lt.{cutoff}"},
             {"status": "failed", "error": f"{STALE_HOURS}시간 초과 — 중단된 실행으로 정리", "finished_at": now().isoformat()})

    nums = db.get("lotto_winning_numbers", {"select": "round,draw_date", "order": "round.desc", "limit": "1"})
    if not nums:
        print("당첨번호 데이터 없음")
        output(run="false", latest=0, target=0)
        return
    latest = int(nums[0]["round"])
    target = latest + 1

    def record_waiting(note):
        prev = db.get("research_pipeline_runs", {"select": "id,status", "pipeline_version": f"eq.{PIPELINE_VERSION}",
                                                 "target_round": f"eq.{target}", "order": "started_at.desc", "limit": "1"})
        if prev and prev[0]["status"] == "waiting":
            db.patch("research_pipeline_runs", {"id": f"eq.{prev[0]['id']}"}, {"error": note, "finished_at": now().isoformat()})
        else:
            db.post("research_pipeline_runs", {"pipeline_version": PIPELINE_VERSION, "latest_round": latest,
                                               "target_round": target, "status": "waiting", "error": note,
                                               "trigger": os.environ.get("GITHUB_EVENT_NAME"),
                                               "runner": os.environ.get("GITHUB_RUN_ID"), "finished_at": now().isoformat()})

    done = db.get("research_pipeline_runs", {"select": "id", "pipeline_version": f"eq.{PIPELINE_VERSION}",
                                             "target_round": f"eq.{target}", "status": "eq.success", "limit": "1"})
    if done:
        print(f"{target}회 파이프라인 이미 성공 ({done[0]['id']}) — 중복 실행하지 않음")
        output(run="false", latest=latest, target=target)
        return

    running = db.get("research_pipeline_runs", {"select": "id,started_at", "pipeline_version": f"eq.{PIPELINE_VERSION}",
                                                "status": "eq.running", "limit": "1"})
    if running:
        print(f"다른 실행이 진행 중 ({running[0]['id']}, {running[0]['started_at']}) — 이번에는 건너뜀")
        output(run="false", latest=latest, target=target)
        return

    why = readiness(db, latest)
    if why:
        print(f"{latest}회 데이터 준비 안 됨 — 대기: {', '.join(why)}")
        record_waiting("데이터 준비 대기: " + ", ".join(why))
        output(run="false", latest=latest, target=target)
        return

    ok, reason, _ = prediction_allowed(db.get, target, nums[0].get("draw_date"), latest)
    if not ok:
        print(f"{latest}회 데이터 준비 완료 · {reason}")
        record_waiting(reason)
        output(run="false", latest=latest, target=target)
        return

    print(f"{latest}회 데이터 준비 완료 · {reason} → {target}회 파이프라인 실행")
    output(run="true", latest=latest, target=target)


if __name__ == "__main__":
    main()
