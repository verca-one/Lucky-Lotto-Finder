"""
동행복권 당첨지점 크롤링 스크립트 (base_big 누적 버전)
로또, 연금복권, 스피또(2000/1000/500) 당첨지점 정보 수집
회차별로 모든 게임 타입을 동시에 크롤링 (1221회→1회 역순)
같은 지점의 당첨을 게임별로 누적 저장
"""

import json
import time
import random
import requests
from datetime import datetime
from typing import List, Dict, Optional
from bs4 import BeautifulSoup
import logging
import urllib3
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import os

# SSL 경고 무시
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DHLotteryCrawler:
    """동행복권 당첨지점 크롤러 (base_big 누적 버전)"""

    def __init__(self):
        self.base_url = "https://www.dhlottery.co.kr"
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Referer': 'https://www.dhlottery.co.kr/',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'ko-KR,ko;q=0.9'
        }

        # 재시도 로직이 있는 session 설정 (강화된 안정성)
        self.session = requests.Session()
        retry_strategy = Retry(
            total=5,  # 재시도 5번
            backoff_factor=2,  # 지수 백오프 (2, 4, 8, 16, 32초)
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

        # dhlottery_code를 키로 사용하여 중복 제거
        self.stores_data = {}

        # 기존 데이터 로드
        self._load_existing_data()

    def _load_existing_data(self) -> None:
        """기존 게임별 파일에서 데이터 로드 및 병합"""
        game_types = ["lotto", "pension", "speedlotto_500", "speedlotto_1000", "speedlotto_2000"]
        total_loaded = 0

        for game_type in game_types:
            filename = f"lost_verca_plus_{game_type}_stores.json"

            if os.path.exists(filename):
                try:
                    with open(filename, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                        for store in data.get("stores", []):
                            dhlottery_code = store.get("dhlottery_code")
                            if dhlottery_code:
                                # 지점이 없으면 새로 생성
                                if dhlottery_code not in self.stores_data:
                                    self.stores_data[dhlottery_code] = {
                                        "dhlottery_code": dhlottery_code,
                                        "store_name": store.get("store_name", ""),
                                        "address": store.get("address", ""),
                                        "region": store.get("region", ""),
                                        "lotto": {"first_wins": [], "second_wins": [], "first_count": 0, "second_count": 0, "total_count": 0},
                                        "pension": {"first_wins": [], "second_wins": [], "first_count": 0, "second_count": 0, "total_count": 0},
                                        "speedlotto_2000": {"first_wins": [], "second_wins": [], "first_count": 0, "second_count": 0, "total_count": 0},
                                        "speedlotto_1000": {"first_wins": [], "second_wins": [], "first_count": 0, "second_count": 0, "total_count": 0},
                                        "speedlotto_500": {"first_wins": [], "second_wins": [], "first_count": 0, "second_count": 0, "total_count": 0}
                                    }

                                # 게임 데이터 병합
                                if game_type in store:
                                    game_data = store[game_type]
                                    self.stores_data[dhlottery_code][game_type]["first_wins"] = game_data.get("first_wins", [])
                                    self.stores_data[dhlottery_code][game_type]["second_wins"] = game_data.get("second_wins", [])
                                    self.stores_data[dhlottery_code][game_type]["first_count"] = game_data.get("first_count", 0)
                                    self.stores_data[dhlottery_code][game_type]["second_count"] = game_data.get("second_count", 0)
                                    self.stores_data[dhlottery_code][game_type]["total_count"] = game_data.get("total_count", 0)
                                    total_loaded += 1

                    logger.info(f"{game_type} 파일 로드 완료: {filename}")
                except Exception as e:
                    logger.error(f"{game_type} 파일 로드 실패 ({filename}): {e}")

        if total_loaded > 0:
            logger.info(f"기존 데이터 로드 완료: {len(self.stores_data)}개 지점")
        else:
            logger.info("기존 데이터 없음 (새로 시작)")

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

    def normalize_region(self, address: str) -> str:
        """주소에서 지역 추출"""
        if not address:
            return "미상"
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

    def _get_purchase_method(self, method_code: str) -> str:
        """구매 방식 코드를 한글로 변환"""
        if not method_code:
            return ""

        method_code = str(method_code).strip()
        method_map = {
            "0": "자동",
            "1": "수동",
            "2": "반자동",
            "Q": "자동",
            "M": "수동",
            "B": "반자동"
        }
        return method_map.get(method_code, method_code)

    def _ensure_store_entry(self, dhlottery_code: str, store_name: str, address: str, purchase_method: str = "") -> None:
        """지점 기본 정보 초기화 (기존 데이터 있으면 유지)"""
        if dhlottery_code not in self.stores_data:
            self.stores_data[dhlottery_code] = {
                "dhlottery_code": dhlottery_code,
                "store_name": store_name,
                "address": address,
                "region": self.normalize_region(address),
                "purchase_method": purchase_method,

                "lotto": {
                    "first_wins": [],
                    "second_wins": [],
                    "first_count": 0,
                    "second_count": 0,
                    "total_count": 0
                },
                "pension": {
                    "first_wins": [],
                    "second_wins": [],
                    "first_count": 0,
                    "second_count": 0,
                    "total_count": 0
                },
                "speedlotto_2000": {
                    "first_wins": [],
                    "second_wins": [],
                    "first_count": 0,
                    "second_count": 0,
                    "total_count": 0
                },
                "speedlotto_1000": {
                    "first_wins": [],
                    "second_wins": [],
                    "first_count": 0,
                    "second_count": 0,
                    "total_count": 0
                },
                "speedlotto_500": {
                    "first_wins": [],
                    "second_wins": [],
                    "first_count": 0,
                    "second_count": 0,
                    "total_count": 0
                }
            }
        else:
            # 기존 데이터가 있으면 주소, 지역, 구매방식 업데이트
            if not self.stores_data[dhlottery_code].get("address"):
                self.stores_data[dhlottery_code]["address"] = address
                self.stores_data[dhlottery_code]["region"] = self.normalize_region(address)
            # 구매방식은 항상 업데이트 (새로운 데이터가 있으면)
            if purchase_method:
                self.stores_data[dhlottery_code]["purchase_method"] = purchase_method

    def _add_winning_record(self, dhlottery_code: str, game_type: str, round_num: int, prize_tier: str, purchase_method: str = "") -> None:
        """당첨 기록 추가 및 카운트 업데이트"""
        if dhlottery_code not in self.stores_data:
            return

        store = self.stores_data[dhlottery_code]
        game_data = store[game_type]

        # 중복 방지 (이미 있는 회차면 추가 안함)
        if prize_tier == "first":
            if round_num not in game_data["first_wins"]:
                game_data["first_wins"].append(round_num)
                game_data["first_count"] += 1
                game_data["total_count"] += 1
        elif prize_tier == "second":
            if round_num not in game_data["second_wins"]:
                game_data["second_wins"].append(round_num)
                game_data["second_count"] += 1
                game_data["total_count"] += 1

        # 당첨 이력 기록 (회차별 구매방식 저장)
        if "winning_history" not in game_data:
            game_data["winning_history"] = []

        # 중복 체크 (이미 기록된 회차-상금등급 조합이 있으면 스킵)
        history_exists = any(
            h["round"] == round_num and h["prize_tier"] == prize_tier
            for h in game_data["winning_history"]
        )

        if not history_exists:
            game_data["winning_history"].append({
                "round": round_num,
                "prize_tier": prize_tier,
                "purchase_method": purchase_method
            })

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

            response = self.session.get(url, params=params, headers=self.headers, timeout=60, verify=False)
            response.raise_for_status()
            data = response.json()

            if not data.get("data") or not data["data"].get("list"):
                logger.debug(f"로또 {round_num}회: 데이터 없음")
                return False

            stores = data["data"]["list"]
            logger.info(f"로또 {round_num}회: {len(stores)}개 당첨지점 발견")

            for store in stores:
                rank = store.get("wnShpRnk", 0)
                if rank not in [1, 2]:
                    continue

                dhlottery_code = store.get("ltShpId")
                store_name = store.get("shpNm", "")
                address = store.get("shpAddr", "").strip()
                prize_tier = self._get_prize_tier(rank)
                # 구매 방식: shpPtrnCode (0=자동, 1=수동, 2=반자동)
                purchase_method_code = store.get("shpPtrnCode", "")
                purchase_method = self._get_purchase_method(purchase_method_code)

                self._ensure_store_entry(dhlottery_code, store_name, address, purchase_method)
                self._add_winning_record(dhlottery_code, "lotto", round_num, prize_tier, purchase_method)

            return True
        except Exception as e:
            logger.error(f"로또 {round_num}회 크롤링 실패: {e}")
            return False

    def crawl_pension_stores(self, round_num: int) -> bool:
        """연금복권 당첨지점 크롤링"""
        logger.info(f"연금복권 {round_num}회 당첨지점 크롤링 시작...")

        try:
            url = f"https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
            params = {
                "srchWnShpRnk": "all",
                "srchLtEpsd": round_num,
                "srchShpLctn": "",
                "gameName": "pension"
            }

            response = self.session.get(url, params=params, headers=self.headers, timeout=60, verify=False)
            response.raise_for_status()
            data = response.json()

            if not data.get("data") or not data["data"].get("list"):
                logger.debug(f"연금복권 {round_num}회: 데이터 없음")
                return False

            stores = data["data"]["list"]
            logger.info(f"연금복권 {round_num}회: {len(stores)}개 당첨지점 발견")

            for store in stores:
                rank = store.get("wnShpRnk", 0)
                if rank not in [1, 2]:
                    continue

                dhlottery_code = store.get("ltShpId")
                store_name = store.get("shpNm", "")
                address = store.get("shpAddr", "").strip()
                prize_tier = self._get_prize_tier(rank)
                # 구매 방식: shpPtrnCode (0=자동, 1=수동, 2=반자동)
                purchase_method_code = store.get("shpPtrnCode", "")
                purchase_method = self._get_purchase_method(purchase_method_code)

                self._ensure_store_entry(dhlottery_code, store_name, address, purchase_method)
                self._add_winning_record(dhlottery_code, "pension", round_num, prize_tier, purchase_method)

            return True
        except Exception as e:
            logger.error(f"연금복권 {round_num}회 크롤링 실패: {e}")
            return False

    def crawl_speedlotto_stores(self, game_type: str, round_num: int) -> bool:
        """스피또 당첨지점 크롤링"""
        logger.info(f"스피또 {game_type} {round_num}회 당첨지점 크롤링 시작...")

        try:
            url = "https://www.dhlottery.co.kr/st/selectWnDsctn.do"

            game_name_map = {
                "speedlotto_2000": "스피또2000",
                "speedlotto_1000": "스피또1000",
                "speedlotto_500": "스피또500"
            }

            game_name = game_name_map.get(game_type, "스피또2000")

            page_num = 1
            records_per_page = 100
            first_page = True

            while True:
                params = {
                    "stGmTypeNm": game_name,
                    "srchOption": 1,
                    "srchValue": "",
                    "pageNum": page_num,
                    "recordCountPerPage": records_per_page
                }

                response = self.session.get(url, params=params, headers=self.headers, timeout=60, verify=False)
                response.raise_for_status()
                data = response.json()

                if not data.get("data") or not data["data"].get("list"):
                    if first_page:
                        logger.debug(f"스피또 {game_type} {round_num}회: 데이터 없음")
                        return False
                    break

                records = data["data"]["list"]

                if first_page:
                    total_found = data["data"].get("total", 0)
                    logger.info(f"스피또 {game_type} {round_num}회: 총 {total_found}개 당첨 기록 발견")
                    first_page = False

                # 지점별로 기록 추가
                for record in records:
                    shop_id = record.get("ltShpId")
                    rank = record.get("wnSqNo", 0)

                    if not shop_id:
                        continue

                    if rank not in [1, 2]:
                        continue

                    store_name = record.get("ltShpNm", "")
                    prize_tier = self._get_prize_tier(rank)
                    # 구매 방식: shpPtrnCode
                    purchase_method_code = record.get("shpPtrnCode", "")
                    purchase_method = self._get_purchase_method(purchase_method_code)

                    self._ensure_store_entry(shop_id, store_name, "", purchase_method)
                    self._add_winning_record(shop_id, game_type, round_num, prize_tier, purchase_method)

                # 다음 페이지 확인
                if len(records) < records_per_page:
                    break

                page_num += 1
                time.sleep(2)

            logger.info(f"스피또 {game_type} {round_num}회: 처리 완료")
            return True

        except Exception as e:
            logger.error(f"스피또 {game_type} {round_num}회 크롤링 실패: {e}")
            return False

    def save_to_files(self) -> None:
        """게임별로 JSON 파일 저장 (누적 데이터 기반)"""
        game_types = ["lotto", "pension", "speedlotto_500", "speedlotto_1000", "speedlotto_2000"]

        # 모든 게임 회차를 내림차순으로 정렬
        for dhlottery_code in self.stores_data.keys():
            store = self.stores_data[dhlottery_code]
            for game_type in game_types:
                # 1등 회차를 내림차순 정렬
                store[game_type]["first_wins"] = sorted(list(set(store[game_type]["first_wins"])), reverse=True)
                # 2등 회차를 내림차순 정렬
                store[game_type]["second_wins"] = sorted(list(set(store[game_type]["second_wins"])), reverse=True)
                # 카운트 재계산
                store[game_type]["first_count"] = len(store[game_type]["first_wins"])
                store[game_type]["second_count"] = len(store[game_type]["second_wins"])
                store[game_type]["total_count"] = store[game_type]["first_count"] + store[game_type]["second_count"]

        # 1. Master 파일 생성 (모든 지점, 모든 게임 정보 포함)
        master_data = []
        for dhlottery_code, store_info in self.stores_data.items():
            # 당첨된 게임이 하나라도 있는 지점만 포함
            if any(store_info[game_type]["total_count"] > 0 for game_type in game_types):
                master_data.append(store_info)

        # Master 파일 저장
        try:
            master_output = {
                "crawled_at": datetime.now().isoformat(),
                "total_stores": len(master_data),
                "stores": master_data
            }

            with open("lost_verca_plus_all_stores.json", 'w', encoding='utf-8') as f:
                json.dump(master_output, f, ensure_ascii=False, indent=2)

            logger.info(f"Master 파일 저장 완료: base_big_all_stores.json ({len(master_data)}개 지점)")
        except Exception as e:
            logger.error(f"Master 파일 저장 실패: {e}")

        # 2. 개별 게임별 파일 생성 (지점정보 + 이력분리)
        for game_type in game_types:
            game_stores = []
            game_histories = []

            for dhlottery_code, store_info in self.stores_data.items():
                if store_info[game_type]["total_count"] > 0:
                    # 지점 정보 (latest만)
                    first_wins = store_info[game_type]["first_wins"]
                    second_wins = store_info[game_type]["second_wins"]

                    game_store_info = {
                        "dhlottery_code": store_info["dhlottery_code"],
                        "store_name": store_info["store_name"],
                        "address": store_info["address"],
                        "region": store_info["region"],
                        "lottery_type": game_type,
                        "purchase_method": store_info.get("purchase_method", ""),
                        "first_count": store_info[game_type]["first_count"],
                        "second_count": store_info[game_type]["second_count"],
                        "total_count": store_info[game_type]["total_count"],
                        "latest_first_win": first_wins[0] if first_wins else None,
                        "latest_second_win": second_wins[0] if second_wins else None
                    }
                    game_stores.append(game_store_info)

                    # 이력 정보 (winning_history에서 직접 가져오기)
                    game_data = store_info[game_type]
                    if "winning_history" in game_data:
                        for history_record in game_data["winning_history"]:
                            game_histories.append({
                                "dhlottery_code": dhlottery_code,
                                "lottery_type": game_type,
                                "round": history_record["round"],
                                "prize_tier": history_record["prize_tier"],
                                "purchase_method": history_record.get("purchase_method", "")
                            })

            # 1. 지점정보 파일 저장
            stores_filename = f"lost_verca_plus_{game_type}_stores.json"
            try:
                output = {
                    "lottery_type": game_type,
                    "crawled_at": datetime.now().isoformat(),
                    "total_winning_stores": len(game_stores),
                    "stores": game_stores
                }

                with open(stores_filename, 'w', encoding='utf-8') as f:
                    json.dump(output, f, ensure_ascii=False, indent=2)

                logger.info(f"{game_type} 지점정보 파일 저장 완료: {stores_filename} ({len(game_stores)}개 지점)")
            except Exception as e:
                logger.error(f"{game_type} 지점정보 파일 저장 실패: {e}")

            # 2. 이력정보 파일 저장
            histories_filename = f"lost_verca_plus_{game_type}_histories.json"
            try:
                output = {
                    "lottery_type": game_type,
                    "crawled_at": datetime.now().isoformat(),
                    "total_histories": len(game_histories),
                    "histories": game_histories
                }

                with open(histories_filename, 'w', encoding='utf-8') as f:
                    json.dump(output, f, ensure_ascii=False, indent=2)

                logger.info(f"{game_type} 이력정보 파일 저장 완료: {histories_filename} ({len(game_histories)}개 이력)")
            except Exception as e:
                logger.error(f"{game_type} 이력정보 파일 저장 실패: {e}")

    def get_latest_round(self, game_type: str) -> Optional[int]:
        """각 게임의 최신 회차 조회"""
        try:
            if game_type == "lotto":
                # 로또: 높은 회차부터 역순으로 시도해서 첫 성공 회차가 최신
                for round_num in range(1300, 1000, -1):
                    url = f"https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
                    params = {
                        "srchWnShpRnk": "all",
                        "srchLtEpsd": round_num,
                        "srchShpLctn": ""
                    }
                    try:
                        response = self.session.get(url, params=params, headers=self.headers, timeout=60, verify=False)
                        data = response.json()
                        if data.get("data") and data["data"].get("list"):
                            logger.info(f"로또 최신 회차: {round_num}회")
                            return round_num
                    except:
                        continue
                return None

            elif game_type == "pension":
                # 연금: 높은 회차부터 역순
                for round_num in range(400, 250, -1):
                    url = f"https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
                    params = {
                        "srchWnShpRnk": "all",
                        "srchLtEpsd": round_num,
                        "srchShpLctn": "",
                        "gameName": "pension"
                    }
                    try:
                        response = self.session.get(url, params=params, headers=self.headers, timeout=60, verify=False)
                        data = response.json()
                        if data.get("data") and data["data"].get("list"):
                            logger.info(f"연금복권 최신 회차: {round_num}회")
                            return round_num
                    except:
                        continue
                return None

            elif "speedlotto" in game_type:
                # 스피또: 최신 회차 조회
                game_name_map = {
                    "speedlotto_2000": "스피또2000",
                    "speedlotto_1000": "스피또1000",
                    "speedlotto_500": "스피또500"
                }
                game_name = game_name_map.get(game_type, "스피또2000")

                url = "https://www.dhlottery.co.kr/st/selectWnDsctn.do"
                params = {
                    "stGmTypeNm": game_name,
                    "srchOption": 1,
                    "srchValue": "",
                    "pageNum": 1,
                    "recordCountPerPage": 1
                }

                try:
                    response = self.session.get(url, params=params, headers=self.headers, timeout=60, verify=False)
                    data = response.json()

                    if data.get("data") and data["data"].get("list"):
                        records = data["data"]["list"]
                        if records:
                            # 스피또는 회차 정보를 직접 파싱해야 함
                            # 첫 번째 기록에서 최신 회차를 추출
                            latest_record = records[0]
                            # 데이터 구조에서 회차 정보를 추출 (실제 필드명은 API 응답에서 확인 필요)
                            logger.info(f"{game_type} 최신 기록 조회 완료")
                            return 1  # 스피또는 항상 최신 1회만 처리
                except Exception as e:
                    logger.error(f"{game_type} 최신 회차 조회 실패: {e}")
                    return 1

        except Exception as e:
            logger.error(f"{game_type} 최신 회차 조회 중 오류: {e}")

        return None

    def run_latest_round(self):
        """최신 회차만 크롤링"""
        logger.info("=" * 70)
        logger.info("동행복권 최신 회차 크롤링 시작")
        logger.info("=" * 70)

        # 각 게임별 최신 회차 조회
        latest_rounds = {
            "lotto": self.get_latest_round("lotto"),
            "pension": self.get_latest_round("pension"),
            "speedlotto_2000": self.get_latest_round("speedlotto_2000"),
            "speedlotto_1000": self.get_latest_round("speedlotto_1000"),
            "speedlotto_500": self.get_latest_round("speedlotto_500")
        }

        # 로또
        if latest_rounds["lotto"]:
            self.crawl_lotto_stores(latest_rounds["lotto"])
            time.sleep(random.uniform(2.0, 3.5))

        # 연금
        if latest_rounds["pension"]:
            self.crawl_pension_stores(latest_rounds["pension"])
            time.sleep(random.uniform(2.0, 3.5))

        # 스피또 2000
        if latest_rounds["speedlotto_2000"]:
            self.crawl_speedlotto_stores("speedlotto_2000", latest_rounds["speedlotto_2000"])
            time.sleep(random.uniform(2.0, 3.5))

        # 스피또 1000
        if latest_rounds["speedlotto_1000"]:
            self.crawl_speedlotto_stores("speedlotto_1000", latest_rounds["speedlotto_1000"])
            time.sleep(random.uniform(2.0, 3.5))

        # 스피또 500
        if latest_rounds["speedlotto_500"]:
            self.crawl_speedlotto_stores("speedlotto_500", latest_rounds["speedlotto_500"])
            time.sleep(random.uniform(2.0, 3.5))

        # 최종 데이터 저장
        logger.info("\n" + "=" * 70)
        logger.info("크롤링 완료, 데이터 저장 중...")
        logger.info("=" * 70)

        self.save_to_files()

        logger.info("=" * 70)
        logger.info("최신 회차 크롤링 완료!")
        logger.info(f"총 누적 지점: {len(self.stores_data)}")
        logger.info("=" * 70)

    def run_all_rounds_by_round(self):
        """
        모든 회차를 크롤링 (회차별로 모든 게임 타입을 동시에 처리)
        1221회→1회 역순 진행
        누적 데이터 기반
        """
        logger.info("=" * 70)
        logger.info("동행복권 당첨지점 크롤링 시작 (base_big 누적 버전)")
        logger.info("=" * 70)

        max_rounds = {
            "lotto": 1221,
            "pension": 312,
            "speedlotto_2000": 67,
            "speedlotto_1000": 106,
            "speedlotto_500": 48
        }

        total_rounds = 1221
        for idx, round_num in enumerate(range(1221, 0, -1)):
            # 로또
            if round_num <= max_rounds["lotto"]:
                self.crawl_lotto_stores(round_num)
                time.sleep(random.uniform(3.0, 8.0))  # 2~3.5초 무작위 대기

            # 연금복권
            if round_num <= max_rounds["pension"]:
                self.crawl_pension_stores(round_num)
                time.sleep(random.uniform(3.0, 8.0))

            # 스피또 2000
            if round_num <= max_rounds["speedlotto_2000"]:
                self.crawl_speedlotto_stores("speedlotto_2000", round_num)
                time.sleep(random.uniform(3.0, 8.0))

            # 스피또 1000
            if round_num <= max_rounds["speedlotto_1000"]:
                self.crawl_speedlotto_stores("speedlotto_1000", round_num)
                time.sleep(random.uniform(3.0, 8.0))

            # 스피또 500
            if round_num <= max_rounds["speedlotto_500"]:
                self.crawl_speedlotto_stores("speedlotto_500", round_num)
                time.sleep(random.uniform(3.0, 8.0))

            # 100회마다 추가 대기 (자연스러운 패턴)
            if round_num % 100 == 0:
                rest_time = random.uniform(5.0, 10.0)
                logger.info(f"[휴식] {rest_time:.1f}초 대기...")
                time.sleep(rest_time)

            # 진행률 표시
            if round_num % 100 == 0 or round_num <= 5:
                progress = 1222 - round_num
                logger.info(f"[진행률] {progress}/{total_rounds} 회차 완료 (누적 지점: {len(self.stores_data)})")

        # 최종 데이터 저장
        logger.info("\n" + "=" * 70)
        logger.info("크롤링 완료, 데이터 저장 중...")
        logger.info("=" * 70)

        self.save_to_files()

        logger.info("=" * 70)
        logger.info("전체 크롤링 완료!")
        logger.info(f"총 누적 지점: {len(self.stores_data)}")
        logger.info("=" * 70)


if __name__ == "__main__":
    import sys

    # 작업 디렉토리를 스크립트 위치로 변경
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)
    logger.info(f"작업 디렉토리: {os.getcwd()}")

    crawler = DHLotteryCrawler()

    # 커맨드 라인 인자 처리
    if len(sys.argv) > 1 and sys.argv[1].lower() == "latest":
        # 최신 회차만 크롤링
        crawler.run_latest_round()
    else:
        # 전체 회차 크롤링 (1221→1)
        crawler.run_all_rounds_by_round()
