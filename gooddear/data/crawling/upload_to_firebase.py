"""
크롤링한 당첨지점 데이터를 Firebase에 업로드
"""

import json
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime
import logging
import os
from pathlib import Path

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class FirebaseUploader:
    """Firebase에 당첨지점 데이터 업로드"""

    def __init__(self, service_account_path: str):
        """Firebase 초기화"""
        try:
            if not firebase_admin._apps:
                cred = credentials.Certificate(service_account_path)
                firebase_admin.initialize_app(cred)
            self.db = firestore.client()
            logger.info("Firebase 연결 성공")
        except Exception as e:
            logger.error(f"Firebase 초기화 실패: {e}")
            raise

    def upload_stores(self, game_type: str, json_file: str) -> bool:
        """JSON 파일의 당첨지점 데이터를 Firebase에 업로드"""
        logger.info(f"{game_type} 데이터 업로드 시작: {json_file}")

        try:
            # JSON 파일 읽기
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)

            stores = data.get("stores", [])
            total = len(stores)
            logger.info(f"업로드할 지점: {total}개")

            if total == 0:
                logger.warning(f"{game_type}: 업로드할 데이터 없음")
                return False

            # Firestore 컬렉션 이름
            collection_name = f"zero_plus_firebase_{game_type}"

            # 배치 업로드 (최대 500개씩)
            batch = self.db.batch()
            batch_count = 0
            batch_max = 500
            success_count = 0

            for idx, store in enumerate(stores, 1):
                try:
                    # 게임지점 ID를 문서 ID로 사용
                    doc_id = store.get("game_store_id")

                    if not doc_id:
                        logger.warning(f"행 {idx}: game_store_id 없음 - 스킵")
                        continue

                    # 데이터 준비
                    store_data = {
                        "game_store_id": store.get("game_store_id"),
                        "dhlottery_code": store.get("dhlottery_code"),
                        "store_name": store.get("store_name"),
                        "address": store.get("address"),
                        "region": store.get("region"),
                        "method": store.get("method"),
                        "latitude": store.get("latitude"),
                        "longitude": store.get("longitude"),
                        "lottery_type": store.get("lottery_type"),
                        "round": store.get("round"),
                        "prize_tier": store.get("prize_tier"),
                        "store_rank": store.get("store_rank"),
                        "winning_amount": store.get("winning_amount"),
                        "created_at": store.get("created_at"),
                        "crawled_at": store.get("crawled_at"),
                        "winning_count": store.get("winning_count", 1),
                        "updated_at": datetime.now().isoformat()
                    }

                    # 배치에 추가
                    doc_ref = self.db.collection(collection_name).document(doc_id)
                    batch.set(doc_ref, store_data, merge=True)
                    batch_count += 1
                    success_count += 1

                    # 500개마다 배치 커밋
                    if batch_count >= batch_max:
                        batch.commit()
                        logger.info(f"{game_type}: {idx}/{total} 업로드 완료")
                        batch = self.db.batch()
                        batch_count = 0

                except Exception as e:
                    logger.error(f"행 {idx} 처리 실패: {e}")
                    continue

            # 남은 데이터 커밋
            if batch_count > 0:
                batch.commit()

            logger.info(f"{game_type}: {success_count}/{total}개 업로드 완료")
            return success_count > 0

        except FileNotFoundError:
            logger.error(f"파일을 찾을 수 없음: {json_file}")
            return False
        except json.JSONDecodeError:
            logger.error(f"JSON 파싱 오류: {json_file}")
            return False
        except Exception as e:
            logger.error(f"{game_type} 업로드 실패: {e}")
            return False

    def run(self, data_dir: str = "."):
        """모든 JSON 파일을 Firebase에 업로드"""
        logger.info("=" * 50)
        logger.info("Firebase 업로드 시작")
        logger.info("=" * 50)

        game_types = [
            ("lotto", "base_lotto_stores_latest.json"),
            ("pension", "base_pension_stores_latest.json"),
            ("speedlotto_2000", "base_speedlotto_2000_stores_latest.json"),
            ("speedlotto_1000", "base_speedlotto_1000_stores_latest.json"),
            ("speedlotto_500", "base_speedlotto_500_stores_latest.json"),
        ]

        results = {}
        for game_type, filename in game_types:
            filepath = os.path.join(data_dir, filename)

            # 파일 존재 확인
            if not os.path.exists(filepath):
                logger.warning(f"{game_type}: 파일 없음 - {filepath}")
                results[game_type] = False
                continue

            # 업로드
            success = self.upload_stores(game_type, filepath)
            results[game_type] = success

        # 결과 요약
        logger.info("=" * 50)
        logger.info("업로드 완료")
        logger.info("=" * 50)
        for game_type, success in results.items():
            status = "✅ 성공" if success else "❌ 실패"
            logger.info(f"{game_type}: {status}")


if __name__ == "__main__":
    # Firebase 서비스 계정 키 경로
    SERVICE_ACCOUNT = "serviceAccountKey.json"

    # serviceAccountKey.json이 없으면 경고
    if not os.path.exists(SERVICE_ACCOUNT):
        logger.error(f"⚠️  {SERVICE_ACCOUNT} 파일을 찾을 수 없습니다.")
        logger.error("Firebase 서비스 계정 키 파일이 필요합니다.")
        logger.error("Firebase 콘솔에서 다운로드 후 이 디렉토리에 저장하세요.")
        exit(1)

    try:
        uploader = FirebaseUploader(SERVICE_ACCOUNT)
        uploader.run()
    except Exception as e:
        logger.error(f"업로드 실패: {e}")
        exit(1)
