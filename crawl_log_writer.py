"""
크롤링 실행 로그를 Supabase에 기록하는 유틸리티
GitHub Actions 워크플로우에서 호출

사용법:
  python crawl_log_writer.py start <lottery_type> [round_info]
  python crawl_log_writer.py finish <log_id> [success|failure] [error_message]
"""

import sys
import os
import json
from datetime import datetime, timezone

try:
    from supabase import create_client
except ImportError:
    print("supabase 패키지 설치 필요: pip install supabase")
    sys.exit(1)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "")

def get_client():
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("❌ SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
        sys.exit(1)
    return create_client(SUPABASE_URL, SUPABASE_KEY)

def start_log(lottery_type: str, rounds_processed: str = "latest"):
    """크롤링 시작 로그 생성, log_id 출력"""
    client = get_client()
    run_id = os.environ.get("GITHUB_RUN_ID", "")

    data = {
        "lottery_type": lottery_type,
        "status": "running",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "rounds_processed": rounds_processed,
        "workflow_run_id": run_id,
    }

    result = client.table("crawl_logs").insert(data).execute()
    log_id = result.data[0]["id"]
    print(log_id)  # stdout으로 log_id 출력 (GitHub Actions에서 캡처)
    return log_id

def finish_log(log_id: str, status: str = "success", error_message: str = None):
    """크롤링 완료 로그 업데이트"""
    client = get_client()
    now = datetime.now(timezone.utc)

    # started_at 조회
    existing = client.table("crawl_logs").select("started_at").eq("id", log_id).execute()
    duration = None
    if existing.data:
        started = datetime.fromisoformat(existing.data[0]["started_at"].replace("Z", "+00:00"))
        duration = int((now - started).total_seconds())

    update_data = {
        "status": status,
        "completed_at": now.isoformat(),
        "duration_seconds": duration,
    }
    if error_message:
        update_data["error_message"] = error_message

    client.table("crawl_logs").update(update_data).eq("id", log_id).execute()
    print(f"✅ 크롤링 로그 업데이트: {status} ({duration}초)" if duration else f"✅ 크롤링 로그 업데이트: {status}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("사용법:")
        print("  python crawl_log_writer.py start <lottery_type> [round_info]")
        print("  python crawl_log_writer.py finish <log_id> [success|failure] [error_message]")
        sys.exit(1)

    action = sys.argv[1]

    if action == "start":
        lottery_type = sys.argv[2]
        rounds = sys.argv[3] if len(sys.argv) > 3 else "latest"
        start_log(lottery_type, rounds)

    elif action == "finish":
        log_id = sys.argv[2]
        status = sys.argv[3] if len(sys.argv) > 3 else "success"
        error_msg = sys.argv[4] if len(sys.argv) > 4 else None
        finish_log(log_id, status, error_msg)

    else:
        print(f"알 수 없는 액션: {action}")
        sys.exit(1)
