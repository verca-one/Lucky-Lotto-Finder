"""
자동 크롤링 스케줄러
- 매주 목요일 19:30: 연금복권 크롤링 + Firebase 업로드
- 매주 토요일 09:30: 로또 크롤링 + Firebase 업로드
- 매일 00:00: 스피또 크롤링 + Firebase 업로드
"""

import schedule
import time
import subprocess
import sys
from datetime import datetime
import os

# Firebase 초기화
import firebase_admin
from firebase_admin import credentials, firestore

# Firebase 인증 (serviceAccountKey.json 필요)
try:
    # 절대 경로로 설정
    key_path = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
    cred = credentials.Certificate(key_path)

    # 기존 앱 삭제 후 초기화
    try:
        firebase_admin.delete_app(firebase_admin.get_app())
    except:
        pass

    firebase_admin.initialize_app(cred)
    print(f"✅ Firebase 초기화 완료")
except Exception as e:
    print(f"⚠️  Firebase 초기화 실패: {e}")
    print(f"   경로: {key_path}")
    print("   serviceAccountKey.json 파일을 확인하세요")
    sys.exit(1)

db = firestore.client()

def upload_to_firebase(data: list, lottery_type: str):
    """JSON 데이터를 Firebase에 업로드"""
    try:
        print(f"\n📤 Firebase 업로드 시작: {lottery_type}")

        batch = db.batch()
        count = 0

        for store in data:
            # store_id를 문서 ID로 사용
            doc_ref = db.collection("win_history").document()
            batch.set(doc_ref, store)
            count += 1

        batch.commit()
        print(f"✅ Firebase 업로드 완료: {lottery_type} ({count}건)")

    except Exception as e:
        print(f"❌ Firebase 업로드 실패: {e}")

def run_lottery_crawl():
    """로또만 크롤링"""
    print(f"\n{'='*60}")
    print(f"🎰 로또 크롤링 시작: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*60}")

    result = subprocess.run(
        [sys.executable, "lotto_crawler.py", "--type", "lotto"],
        capture_output=True,
        text=True
    )

    print(result.stdout)
    if result.returncode != 0:
        print(f"❌ 오류: {result.stderr}")
    else:
        # winner_stores.json에서 로또 데이터만 읽어서 Firebase 업로드
        try:
            with open("winner_stores.json", "r", encoding="utf-8") as f:
                stores = json.load(f)
                lotto_data = [s for s in stores if s.get("lottery_type") == "lotto"]
                upload_to_firebase(lotto_data, "lotto")
        except Exception as e:
            print(f"⚠️  데이터 로드 실패: {e}")

def run_pension_crawl():
    """연금복권만 크롤링"""
    print(f"\n{'='*60}")
    print(f"💎 연금복권 크롤링 시작: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*60}")

    result = subprocess.run(
        [sys.executable, "lotto_crawler.py", "--type", "pension"],
        capture_output=True,
        text=True
    )

    print(result.stdout)
    if result.returncode != 0:
        print(f"❌ 오류: {result.stderr}")
    else:
        try:
            with open("winner_stores.json", "r", encoding="utf-8") as f:
                stores = json.load(f)
                pension_data = [s for s in stores if s.get("lottery_type") == "pension"]
                upload_to_firebase(pension_data, "pension")
        except Exception as e:
            print(f"⚠️  데이터 로드 실패: {e}")

def run_speeto_crawl():
    """스피또만 크롤링"""
    print(f"\n{'='*60}")
    print(f"⭐ 스피또 크롤링 시작: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*60}")

    result = subprocess.run(
        [sys.executable, "lotto_crawler.py", "--type", "speeto"],
        capture_output=True,
        text=True
    )

    print(result.stdout)
    if result.returncode != 0:
        print(f"❌ 오류: {result.stderr}")
    else:
        try:
            with open("winner_stores.json", "r", encoding="utf-8") as f:
                stores = json.load(f)
                speeto_data = [s for s in stores if s.get("lottery_type") == "speeto"]
                upload_to_firebase(speeto_data, "speeto")
        except Exception as e:
            print(f"⚠️  데이터 로드 실패: {e}")

def job_notification(job_name: str, scheduled_time: str):
    """작업 예약 알림"""
    print(f"\n✅ {job_name} 예약됨: 매주 {scheduled_time}")

if __name__ == "__main__":
    import json

    print("\n" + "="*60)
    print("🎯 동행복권 자동 크롤링 스케줄러 시작")
    print("="*60)

    # 스케줄 등록
    schedule.every().thursday.at("19:30").do(run_pension_crawl)
    job_notification("연금복권", "목요일 19:30")

    schedule.every().saturday.at("09:30").do(run_lottery_crawl)
    job_notification("로또", "토요일 09:30")

    schedule.every().day.at("00:00").do(run_speeto_crawl)
    job_notification("스피또", "매일 00:00")

    print("="*60)
    print("⏳ 스케줄러 대기 중...\n")

    # 무한 루프로 스케줄 실행
    try:
        while True:
            schedule.run_pending()
            time.sleep(60)  # 60초마다 체크
    except KeyboardInterrupt:
        print("\n\n🛑 스케줄러 중지됨")
        sys.exit(0)
