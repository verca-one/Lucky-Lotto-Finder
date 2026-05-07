"""
동행복권 당첨지점 크롤링 스크립트 (수정 버전)
로또, 연금복권, 스피또(2000/1000/500) 당첨지점 정보 수집
회차별로 모든 게임 타입을 동시에 크롤링 (1221회→1회 역순)
"""

import json
import time
import requests
from datetime import datetime
from typing import List, Dict, Optional
from bs4 import BeautifulSoup
import logging
import urllib3
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# SSL 경고 무시
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DHLotteryCrawler:
    """동행복권 당첨지점 크롤러"""

    def __init__(self):
        self.base_url = "https://www.dhlottery.co.kr"
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Referer': 'https://www.dhlottery.co.kr/',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'ko-KR,ko;q=0.9'
        }

        # 재시도 로직이 있는 session 설정
        self.session = requests.Session()
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

        self.stores_data = {
            "lotto": [],
            "pension": [],
            "speedlotto_2000": [],
            "speedlotto_1000": [],
            "speedlotto_500": []
        }
        self.store_id_counter = {
            "lotto": 0,
            "pension": 0,
            "speedlotto_2000": 0,
            "speedlotto_1000": 0,
            "speedlotto_500": 0
        }

    def generate_store_id(self, game_type: str) -> str:
        """게임별 고유 지점 ID 생성"""
        self.store_id_counter[game_type] += 1

        game_prefix_map = {
            "lotto": "LOTTO",
            "pension": "PENSION",
            "speedlotto_2000": "SPEEDLOTTO_2000",
            "speedlotto_1000": "SPEEDLOTTO_1000",
            "speedlotto_500": "SPEEDLOTTO_500"
        }

        prefix = game_prefix_map.get(game_type, "UNKNOWN")
        return f"{prefix}_STORE_{self.store_id_counter[game_type]:05d}"

    def normalize_region(self, address: str) -> str:
        """주소에서 지역 추출"""
        if not address:
            return "미상"

        # 첫 번째 공백 전까지의 텍스트가 지역명
        parts = address.split()
        return parts[0] if parts else "미상"

    def normalize_method(self, method: str) -> str:
        """판매 방식 정규화"""
        method_map = {
            "자종": "자종",
            "반자": "반자동",
            "수표": "수표",
            "자동": "자동",
            "Q": "자동",
            "M": "수동",
            "B": "반자동"
        }
        return method_map.get(method, method)

    def _get_prize_tier(self, rank: int) -> str:
        """순위를 당첨 등급으로 변환"""
        tier_map = {
            1: "first",
            2: "second",
            3: "third",
            4: "fourth",
            5: "fifth",
            6: "sixth",
            7: "seventh"
        }
        return tier_map.get(rank, "bonus")

    def create_store_object(
        self,
        game_type: str,
        round_num: int,
        prize_tier: str,
        store_rank: int,
        store_name: str,
        address: str,
        method: str,
        winning_amount: Optional[int] = None,
        latitude: Optional[float] = None,
        longitude: Optional[float] = None
    ) -> Dict:
        """지점 객체 생성"""

        game_store_id = self.generate_store_id(game_type)
        region = self.normalize_region(address)

        store_obj = {
            "game_store_id": game_store_id,
            "dhlottery_code": None,  # 동행복권 공식 코드 (크롤링으로 가져올 수 있으면 추가)

            "store_name": store_name,
            "address": address,
            "region": region,
            "method": self.normalize_method(method),
            "latitude": latitude,
            "longitude": longitude,

            "lottery_type": game_type,
            "round": round_num,
            "prize_tier": prize_tier,
            "store_rank": store_rank,
            "winning_amount": winning_amount,

            "created_at": datetime.now().isoformat(),
            "crawled_at": datetime.now().isoformat(),
            "winning_count": 1  # 첫 크롤링이므로 1로 시작
        }

        return store_obj

    def crawl_lotto_stores(self, round_num: int) -> bool:
        """로또 당첨지점 크롤링"""
        logger.info(f"로또 {round_num}회 당첨지점 크롤링 시작...")

        try:
            url = f"https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
            params = {
                "srchWnShpRnk": "all",
                "srchLtEpsd": round_num,
                "srchShpLctn": ""
            }

            response = self.session.get(url, params=params, headers=self.headers, timeout=30, verify=False)
            response.raise_for_status()
            data = response.json()

            if not data.get("data") or not data["data"].get("list"):
                logger.warning(f"로또 {round_num}회: 데이터 없음")
                return False

            stores = data["data"]["list"]
            logger.info(f"로또 {round_num}회: {len(stores)}개 당첨지점 발견")

            for store in stores:
                # 1등과 2등만 수집
                rank = store.get("wnShpRnk", 0)
                if rank not in [1, 2]:
                    continue

                store_obj = self.create_store_object(
                    game_type="lotto",
                    round_num=round_num,
                    prize_tier=self._get_prize_tier(rank),
                    store_rank=rank,
                    store_name=store.get("shpNm", ""),
                    address=store.get("shpAddr", "").strip(),
                    method=store.get("atmtPsvYnTxt", ""),
                    winning_amount=None,
                    latitude=store.get("shpLat"),
                    longitude=store.get("shpLot")
                )
                store_obj["dhlottery_code"] = store.get("ltShpId")
                self.stores_data["lotto"].append(store_obj)

            return True
        except Exception as e:
            logger.error(f"로또 {round_num}회 크롤링 실패: {e}")
            return False

    def crawl_pension_stores(self, round_num: int) -> bool:
        """연금복권 당첨지점 크롤링"""
        logger.info(f"연금복권 {round_num}회 당첨지점 크롤링 시작...")

        try:
            # 연금복권은 로또와 같은 엔드포인트 사용 (파라미터만 다름)
            url = f"https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
            params = {
                "srchWnShpRnk": "all",
                "srchLtEpsd": round_num,
                "srchShpLctn": "",
                "gameName": "pension"  # 연금복권 구분 파라미터
            }

            response = self.session.get(url, params=params, headers=self.headers, timeout=30, verify=False)
            response.raise_for_status()
            data = response.json()

            if not data.get("data") or not data["data"].get("list"):
                logger.warning(f"연금복권 {round_num}회: 데이터 없음")
                return False

            stores = data["data"]["list"]
            logger.info(f"연금복권 {round_num}회: {len(stores)}개 당첨지점 발견")

            for store in stores:
                # 1등과 2등만 수집
                rank = store.get("wnShpRnk", 0)
                if rank not in [1, 2]:
                    continue

                store_obj = self.create_store_object(
                    game_type="pension",
                    round_num=round_num,
                    prize_tier=self._get_prize_tier(rank),
                    store_rank=rank,
                    store_name=store.get("shpNm", ""),
                    address=store.get("shpAddr", "").strip(),
                    method=store.get("atmtPsvYnTxt", ""),
                    winning_amount=None,
                    latitude=store.get("shpLat"),
                    longitude=store.get("shpLot")
                )
                store_obj["dhlottery_code"] = store.get("ltShpId")
                self.stores_data["pension"].append(store_obj)

            return True
        except Exception as e:
            logger.error(f"연금복권 {round_num}회 크롤링 실패: {e}")
            return False

    def crawl_speedlotto_stores(self, game_type: str, round_num: int) -> bool:
        """스피또 당첨지점 크롤링"""
        logger.info(f"스피또 {game_type} {round_num}회 당첨지점 크롤링 시작...")

        try:
            # 스피또 전용 엔드포인트
            url = "https://www.dhlottery.co.kr/st/selectWnDsctn.do"

            # 게임 타입별 한글 이름 매핑
            game_name_map = {
                "speedlotto_2000": "스피또2000",
                "speedlotto_1000": "스피또1000",
                "speedlotto_500": "스피또500"
            }

            game_name = game_name_map.get(game_type, "스피또2000")

            # 지점별 당첨 정보 집계 (같은 지점이 여러 번 나타날 수 있음)
            stores_dict = {}
            total_records = 0
            page_num = 1
            records_per_page = 100

            while True:
                params = {
                    "stGmTypeNm": game_name,
                    "srchOption": 1,
                    "srchValue": "",
                    "pageNum": page_num,
                    "recordCountPerPage": records_per_page
                }

                response = self.session.get(url, params=params, headers=self.headers, timeout=30, verify=False)
                response.raise_for_status()
                data = response.json()

                if not data.get("data") or not data["data"].get("list"):
                    if page_num == 1:
                        logger.warning(f"스피또 {game_type} {round_num}회: 데이터 없음")
                        return False
                    break

                records = data["data"]["list"]

                if page_num == 1:
                    total_records = data["data"].get("total", 0)
                    logger.info(f"스피또 {game_type} {round_num}회: 총 {total_records}개 당첨 기록 발견")

                # 지점별로 당첨 정보 집계
                for record in records:
                    shop_id = record.get("ltShpId")
                    rank = record.get("wnSqNo", 0)

                    if not shop_id:
                        continue

                    # 1등과 2등만 수집
                    if rank not in [1, 2]:
                        continue

                    # 지점별 중복 제거 (첫 당첨 기록만 store_object로 생성)
                    if shop_id not in stores_dict:
                        # 상금 문자열에서 쉼표 제거
                        winning_amount_str = record.get("ltWnAmtCn", "0").replace(",", "")
                        try:
                            winning_amount = int(winning_amount_str)
                        except:
                            winning_amount = 0

                        store_obj = self.create_store_object(
                            game_type=game_type,
                            round_num=round_num,
                            prize_tier=self._get_prize_tier(rank),
                            store_rank=rank,
                            store_name=record.get("ltShpNm", ""),
                            address="",  # 스피또 API에는 주소 정보 없음
                            method="",   # 판매방식 정보 없음
                            winning_amount=winning_amount,
                            latitude=None,
                            longitude=None
                        )
                        store_obj["dhlottery_code"] = shop_id
                        stores_dict[shop_id] = store_obj
                    else:
                        # 같은 지점의 다른 당첨 기록이면 winning_count 증가
                        stores_dict[shop_id]["winning_count"] += 1

                # 다음 페이지 확인
                if len(records) < records_per_page:
                    break

                page_num += 1
                time.sleep(1.0)  # API 부하 방지

            # 집계된 지점들을 stores_data에 추가
            for store_obj in stores_dict.values():
                self.stores_data[game_type].append(store_obj)

            logger.info(f"스피또 {game_type} {round_num}회: {len(stores_dict)}개 당첨지점 수집 완료")
            return len(stores_dict) > 0

        except Exception as e:
            logger.error(f"스피또 {game_type} {round_num}회 크롤링 실패: {e}")
            return False

    def save_to_json(self, game_type: str, filename: str) -> bool:
        """데이터를 JSON 파일로 저장"""
        try:
            filepath = f"zero_plus_base_{game_type}_stores_all_rounds.json"

            output = {
                "lottery_type": game_type,
                "crawled_at": datetime.now().isoformat(),
                "total_count": len(self.stores_data[game_type]),
                "stores": self.stores_data[game_type]
            }

            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(output, f, ensure_ascii=False, indent=2)

            logger.info(f"{game_type} 데이터 저장 완료: {filepath} ({len(self.stores_data[game_type])}개)")
            return True
        except Exception as e:
            logger.error(f"JSON 저장 실패: {e}")
            return False

    def run_all_rounds_by_round(self):
        """
        모든 회차를 크롤링 (회차별로 모든 게임 타입을 동시에 처리)
        1221회→1회 역순 진행
        """
        logger.info("=" * 70)
        logger.info("동행복권 당첨지점 크롤링 시작 (전회차, 회차별 모든 게임 동시 처리)")
        logger.info("=" * 70)

        # 각 게임별 최대 회차
        max_rounds = {
            "lotto": 1221,
            "pension": 312,
            "speedlotto_2000": 67,
            "speedlotto_1000": 106,
            "speedlotto_500": 48
        }

        # 역순으로 처리 (1221회부터 1회까지)
        for round_num in range(1221, 0, -1):
            logger.info(f"\n[회차 {round_num}] 크롤링 시작")

            # 로또
            if round_num <= max_rounds["lotto"]:
                self.crawl_lotto_stores(round_num)
                time.sleep(0.5)

            # 연금복권
            if round_num <= max_rounds["pension"]:
                self.crawl_pension_stores(round_num)
                time.sleep(0.5)

            # 스피또 2000
            if round_num <= max_rounds["speedlotto_2000"]:
                self.crawl_speedlotto_stores("speedlotto_2000", round_num)
                time.sleep(0.5)

            # 스피또 1000
            if round_num <= max_rounds["speedlotto_1000"]:
                self.crawl_speedlotto_stores("speedlotto_1000", round_num)
                time.sleep(0.5)

            # 스피또 500
            if round_num <= max_rounds["speedlotto_500"]:
                self.crawl_speedlotto_stores("speedlotto_500", round_num)
                time.sleep(0.5)

            # 진행률 표시 (100회마다)
            if round_num % 100 == 0 or round_num <= 5:
                lotto_count = len(self.stores_data["lotto"])
                pension_count = len(self.stores_data["pension"])
                speed2000_count = len(self.stores_data["speedlotto_2000"])
                speed1000_count = len(self.stores_data["speedlotto_1000"])
                speed500_count = len(self.stores_data["speedlotto_500"])

                logger.info(f"[진행률] 로또: {lotto_count}, 연금: {pension_count}, 스피또2000: {speed2000_count}, 스피또1000: {speed1000_count}, 스피또500: {speed500_count}")

        # 최종 데이터 저장
        logger.info("\n" + "=" * 70)
        logger.info("크롤링 완료, 데이터 저장 중...")
        logger.info("=" * 70)

        for game_type in self.stores_data.keys():
            self.save_to_json(game_type, f"zero_plus_base_{game_type}_stores_all_rounds.json")

        logger.info("=" * 70)
        logger.info("전체 크롤링 완료!")
        logger.info("=" * 70)

    def run_latest(self):
        """최신 회차만 크롤링 (GitHub Actions용)"""
        logger.info("=" * 50)
        logger.info("동행복권 당첨지점 크롤링 시작 (최신 회차만)")
        logger.info("=" * 50)

        # 로또 최신 회차 (1221회)
        logger.info("로또 최신 회차 크롤링...")
        self.crawl_lotto_stores(1221)

        # 연금복권 최신 회차 (312회)
        logger.info("연금복권 최신 회차 크롤링...")
        self.crawl_pension_stores(312)

        # 스피또 최신 회차
        logger.info("스피또 최신 회차 크롤링...")
        self.crawl_speedlotto_stores("speedlotto_2000", 67)
        self.crawl_speedlotto_stores("speedlotto_1000", 106)
        self.crawl_speedlotto_stores("speedlotto_500", 48)

        # 데이터 저장
        for game_type in self.stores_data.keys():
            self.save_to_json(game_type, f"zero_plus_base_{game_type}_stores_latest.json")

        logger.info("=" * 50)
        logger.info("최신 회차 크롤링 완료")
        logger.info("=" * 50)

    def run(self):
        """전체 크롤링 실행 (게임별 처리 - 기존 방식)"""
        logger.info("=" * 50)
        logger.info("동행복권 당첨지점 크롤링 시작 (전회차, 게임별 처리)")
        logger.info("=" * 50)

        # 로또 크롤링 (1221회부터 역순)
        logger.info("로또 전회차 크롤링 시작 (최신→과거)...")
        for round_num in range(1221, 0, -1):
            self.crawl_lotto_stores(round_num)
            if (1222 - round_num) % 100 == 0:
                logger.info(f"로또 진행률: {1222 - round_num}/1221")
            time.sleep(0.5)

        # 연금복권 크롤링 (312회부터 역순)
        logger.info("연금복권 전회차 크롤링 시작 (최신→과거)...")
        for round_num in range(312, 0, -1):
            self.crawl_pension_stores(round_num)
            if (313 - round_num) % 50 == 0:
                logger.info(f"연금복권 진행률: {313 - round_num}/312")
            time.sleep(0.5)

        # 스피또 크롤링
        logger.info("스피또2000 전회차 크롤링 시작 (최신→과거)...")
        for round_num in range(67, 0, -1):
            self.crawl_speedlotto_stores("speedlotto_2000", round_num)
            if (68 - round_num) % 10 == 0:
                logger.info(f"스피또2000 진행률: {68 - round_num}/67")
            time.sleep(0.5)

        logger.info("스피또1000 전회차 크롤링 시작 (최신→과거)...")
        for round_num in range(106, 0, -1):
            self.crawl_speedlotto_stores("speedlotto_1000", round_num)
            if (107 - round_num) % 20 == 0:
                logger.info(f"스피또1000 진행률: {107 - round_num}/106")
            time.sleep(0.5)

        logger.info("스피또500 전회차 크롤링 시작 (최신→과거)...")
        for round_num in range(48, 0, -1):
            self.crawl_speedlotto_stores("speedlotto_500", round_num)
            if (49 - round_num) % 10 == 0:
                logger.info(f"스피또500 진행률: {49 - round_num}/48")
            time.sleep(0.5)

        # 데이터 저장
        for game_type in self.stores_data.keys():
            self.save_to_json(game_type, f"zero_plus_base_{game_type}_stores_all_rounds.json")

        logger.info("=" * 50)
        logger.info("크롤링 완료")
        logger.info("=" * 50)


if __name__ == "__main__":
    import sys
    crawler = DHLotteryCrawler()

    if len(sys.argv) > 1:
        if sys.argv[1] == 'latest':
            crawler.run_latest()
        elif sys.argv[1] == 'by_round':
            crawler.run_all_rounds_by_round()
        else:
            crawler.run()
    else:
        # 기본값: 회차별 처리 방식 (권장)
        crawler.run_all_rounds_by_round()
