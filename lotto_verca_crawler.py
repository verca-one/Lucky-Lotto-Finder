"""
동행복권 당첨지점 크롤링 스크립트 (base_big 누적 버전)
로또, 연금복권, 스피또(2000/1000/500) 당첨지점 정보 수집
회차별로 모든 게임 타입을 동시에 크롤링 (1221회→1회 역순)
같은 지점의 당첨을 게임별로 누적 저장
"""

import json
import sys
import time
import random
import requests
from datetime import datetime
from typing import List, Dict, Optional
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
        # 기본 헤더 (HTML 페이지 요청용)
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Accept-Encoding': 'gzip, deflate, br',
            'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
        }
        # AJAX/JSON API 전용 헤더 — 서버가 JSON 반환하도록 강제
        self.ajax_headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Accept-Encoding': 'gzip, deflate, br',
            'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Connection': 'keep-alive',
            'X-Requested-With': 'XMLHttpRequest',   # ← JSON 응답 유도 핵심 헤더
            'Referer': 'https://www.dhlottery.co.kr/wnprchsplcsrch/selectWnPrchsPlcList.do',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
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

        # IP 보호: 연속 실패 카운터
        self._consecutive_failures = 0
        self._total_requests = 0

        # 기존 데이터 로드
        self._load_existing_data()

        # 세션 워밍업: 홈페이지 방문으로 쿠키 획득
        self._warm_up_session()

    def _load_existing_data(self) -> None:
        """기존 게임별 파일에서 데이터 로드 및 병합"""
        game_types = ["lotto", "pension", "speedlotto_500", "speedlotto_1000", "speedlotto_2000"]
        total_loaded = 0

        for game_type in game_types:
            filename = f"lotto_verca_{game_type}_stores.json"

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

    def _warm_up_session(self) -> None:
        """홈페이지 방문으로 세션 쿠키 획득 (API 호출 전 필수)"""
        warm_up_urls = [
            "https://www.dhlottery.co.kr/common.do?method=main",
            "https://www.dhlottery.co.kr/wnprchsplcsrch/selectWnPrchsPlcList.do",
        ]
        for url in warm_up_urls:
            try:
                resp = self.session.get(url, headers=self.headers, timeout=30, verify=False)
                logger.info(f"[세션워밍업] {url} → HTTP {resp.status_code} | 쿠키: {dict(self.session.cookies)}")
                time.sleep(random.uniform(1.0, 2.0))
            except Exception as e:
                logger.warning(f"[세션워밍업] {url} 실패 (무시): {e}")

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

    def _safe_request(self, url: str, params: dict = None, timeout: int = 60,
                      use_ajax_headers: bool = True) -> Optional[requests.Response]:
        """IP 보호가 적용된 안전한 HTTP 요청.
        use_ajax_headers=True(기본): JSON API 호출용 AJAX 헤더 사용
        """
        self._total_requests += 1

        # 매 10번 요청마다 추가 랜덤 대기
        if self._total_requests % 10 == 0:
            pause = random.uniform(3.0, 8.0)
            logger.debug(f"[IP보호] {self._total_requests}번째 요청, {pause:.1f}초 추가 대기")
            time.sleep(pause)

        req_headers = self.ajax_headers if use_ajax_headers else self.headers
        try:
            response = self.session.get(url, params=params, headers=req_headers, timeout=timeout, verify=False)

            # 429 (Too Many Requests) 또는 403 (Forbidden) 감지
            if response.status_code in [429, 403]:
                self._consecutive_failures += 1
                wait_time = min(60 * self._consecutive_failures, 300)  # 최대 5분
                logger.warning(f"[IP보호] {response.status_code} 응답! {wait_time}초 대기 (연속실패: {self._consecutive_failures})")
                time.sleep(wait_time)
                # 한 번 더 시도
                response = self.session.get(url, params=params, headers=req_headers, timeout=timeout, verify=False)

            if response.status_code == 200:
                self._consecutive_failures = 0  # 성공하면 리셋

            response.raise_for_status()
            return response

        except requests.exceptions.ConnectionError:
            self._consecutive_failures += 1
            wait_time = min(120 * self._consecutive_failures, 600)  # 최대 10분
            logger.error(f"[IP보호] 연결 거부! IP 차단 가능성. {wait_time}초 대기 (연속실패: {self._consecutive_failures})")
            time.sleep(wait_time)
            return None
        except Exception as e:
            self._consecutive_failures += 1
            logger.error(f"[IP보호] 요청 실패: {e} (연속실패: {self._consecutive_failures})")
            if self._consecutive_failures >= 5:
                wait_time = random.uniform(120, 300)
                logger.warning(f"[IP보호] 연속 {self._consecutive_failures}회 실패! {wait_time:.0f}초 긴급 대기")
                time.sleep(wait_time)
            return None

    def _get_purchase_method(self, method_code: str) -> str:
        """구매 방식 코드를 한글로 변환 (스피또용)"""
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

    def get_lotto_numbers(self, round_num: int) -> Optional[Dict]:
        """로또 당첨번호 조회"""
        try:
            url = f"{self.base_url}/common.do?method=getLottoNumber&drwNo={round_num}"
            response = self.session.get(url, headers=self.headers, timeout=60, verify=False)
            response.raise_for_status()
            data = response.json()

            if data.get("returnValue") != "success":
                return None

            return {
                "lottery_type": "lotto",
                "round": data.get("drwNo"),
                "draw_date": data.get("drwNoDate"),
                "num1": data.get("drwtNo1"),
                "num2": data.get("drwtNo2"),
                "num3": data.get("drwtNo3"),
                "num4": data.get("drwtNo4"),
                "num5": data.get("drwtNo5"),
                "num6": data.get("drwtNo6"),
                "bonus": data.get("bnusNo"),
                "created_at": datetime.now().isoformat()
            }
        except Exception as e:
            logger.debug(f"로또 {round_num}회 당첨번호 조회 실패: {e}")
            return None

    def get_pension_numbers(self, round_num: int) -> Optional[Dict]:
        """연금복권 당첨번호 조회"""
        try:
            url = f"{self.base_url}/common.do?method=getPensionNumber&drwNo={round_num}"
            response = self.session.get(url, headers=self.headers, timeout=60, verify=False)
            response.raise_for_status()
            data = response.json()

            if data.get("returnValue") != "success":
                return None

            return {
                "lottery_type": "pension",
                "round": data.get("drwNo"),
                "draw_date": data.get("drwNoDate"),
                "numbers": data.get("bnusNo"),  # 연금복권은 구조가 다를 수 있음
                "created_at": datetime.now().isoformat()
            }
        except Exception as e:
            logger.debug(f"연금복권 {round_num}회 당첨번호 조회 실패: {e}")
            return None

    # _extract_purchase_methods_from_html 제거됨
    # → API 응답의 atmtPsvYnTxt 필드에서 구매방식 직접 추출 (추가 HTTP 요청 불필요)

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
        logger.info(f"[로또] Fetching round {round_num}")

        try:
            url = f"https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
            params = {
                "srchWnShpRnk": "all",
                "srchLtEpsd": round_num,
                "srchShpLctn": ""
            }

            response = self._safe_request(url, params=params)
            if not response:
                logger.error(f"[로또] {round_num}회 HTTP 요청 실패 (response=None) → 저장 실패")
                return False

            logger.info(f"[로또] {round_num}회 HTTP {response.status_code} | 응답 길이 {len(response.content)} bytes")

            try:
                data = response.json()
            except Exception as je:
                logger.error(f"[로또] {round_num}회 JSON 파싱 실패: {je} → 저장 실패")
                return False

            if not data.get("data") or not data["data"].get("list"):
                logger.warning(f"[로또] {round_num}회 파싱 성공 but 데이터 없음 (list 비어있음) → 저장 실패")
                return False

            stores = data["data"]["list"]
            logger.info(f"[로또] {round_num}회 파싱 성공: {len(stores)}개 당첨지점 발견")

            saved = 0
            for store in stores:
                rank = store.get("wnShpRnk", 0)
                if rank not in [1, 2]:
                    continue

                dhlottery_code = store.get("ltShpId")
                store_name = store.get("shpNm", "")
                address = store.get("shpAddr", "").strip()
                prize_tier = self._get_prize_tier(rank)

                # API 응답에서 구매방식 직접 추출 (1등만 존재, 2등은 빈값)
                purchase_method = store.get("atmtPsvYnTxt", "") or ""

                self._ensure_store_entry(dhlottery_code, store_name, address, purchase_method)
                self._add_winning_record(dhlottery_code, "lotto", round_num, prize_tier, purchase_method)
                saved += 1

            logger.info(f"[로또] {round_num}회 저장 성공: {saved}개 기록 (1등/2등 합산)")
            return True
        except Exception as e:
            logger.error(f"[로또] {round_num}회 크롤링 예외 → 저장 실패: {e}")
            return False

    def crawl_pension_stores(self, round_num: int) -> bool:
        """연금복권 당첨지점 크롤링 (신규 API: selectPtWnShp.do)"""
        logger.info(f"[연금] Fetching round {round_num}")

        try:
            # 연금복권 전용 엔드포인트 (로또와 별도)
            url = f"https://www.dhlottery.co.kr/wnprchsplcsrch/selectPtWnShp.do"
            params = {
                "srchWnShpRnk": "all",
                "srchLtEpsd": round_num,
                "srchShpLctn": ""
            }

            response = self._safe_request(url, params=params)
            if not response:
                logger.error(f"[연금] {round_num}회 HTTP 요청 실패 (response=None) → 저장 실패")
                return False

            content_type = response.headers.get("Content-Type", "")
            final_url = response.url
            body_preview = response.text[:300].replace("\n", " ").replace("\r", "")
            logger.info(f"[연금] {round_num}회 HTTP {response.status_code} | {len(response.content)} bytes"
                        f" | Content-Type: {content_type}")
            logger.info(f"[연금] {round_num}회 최종 URL: {final_url}")
            logger.info(f"[연금] {round_num}회 응답 앞 300자: {body_preview}")

            # 로그인/오류 페이지 감지
            suspicious = any(kw in response.text for kw in ["로그인", "login", "접근 제한", "오류", "error", "<!DOCTYPE"])
            if suspicious:
                logger.warning(f"[연금] {round_num}회 ⚠️  HTML/오류 페이지 감지 (차단 가능성)")

            try:
                data = response.json()
            except Exception as je:
                logger.error(f"[연금] {round_num}회 JSON 파싱 실패: {je} → 저장 실패")
                return False

            has_list = bool(data.get("data") and data["data"].get("list"))
            store_count = len(data["data"]["list"]) if has_list else 0
            logger.info(f"[연금] {round_num}회 판매점 테이블 존재: {has_list} | 추출 개수: {store_count}")

            if not has_list or store_count == 0:
                logger.warning(f"[연금] {round_num}회 판매점 목록 비어있음 → stores_status=empty")
                return False

            stores = data["data"]["list"]
            logger.info(f"[연금] {round_num}회 파싱 성공: {len(stores)}개 당첨지점 발견")

            saved = 0
            for store in stores:
                # wnShpRnk: "1"=1등, "2"=2등, "21"=보너스 (문자열)
                rank_str = str(store.get("wnShpRnk", ""))
                if rank_str not in ["1", "2"]:
                    continue

                rank = int(rank_str)
                dhlottery_code = store.get("ltShpId")
                store_name = store.get("shpNm", "")
                address = store.get("shpAddr", "").strip()
                prize_tier = self._get_prize_tier(rank)

                # 연금복권 API에는 atmtPsvYnTxt가 없음
                purchase_method = ""

                self._ensure_store_entry(dhlottery_code, store_name, address, purchase_method)
                self._add_winning_record(dhlottery_code, "pension", round_num, prize_tier, purchase_method)
                saved += 1

            logger.info(f"[연금] {round_num}회 저장 성공: {saved}개 기록 (1등/2등 합산)")
            return True
        except Exception as e:
            logger.error(f"[연금] {round_num}회 크롤링 예외 → 저장 실패: {e}")
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

                response = self._safe_request(url, params=params)
                if not response:
                    if first_page:
                        return False
                    break
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

    def _save_winning_numbers(self, winning_numbers: List[Dict]) -> None:
        """당첨번호 저장"""
        try:
            output = {
                "crawled_at": datetime.now().isoformat(),
                "total_numbers": len(winning_numbers),
                "numbers": winning_numbers
            }

            filename = "lotto_verca_winning_numbers.json"
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(output, f, ensure_ascii=False, indent=2)

            logger.info(f"당첨번호 저장 완료: {filename} ({len(winning_numbers)}개)")
        except Exception as e:
            logger.error(f"당첨번호 저장 실패: {e}")

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

            with open("lotto_verca_all_stores.json", 'w', encoding='utf-8') as f:
                json.dump(master_output, f, ensure_ascii=False, indent=2)

            logger.info(f"Master 파일 저장 완료: lotto_verca_all_stores.json ({len(master_data)}개 지점)")
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
            stores_filename = f"lotto_verca_{game_type}_stores.json"
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
            histories_filename = f"lotto_verca_{game_type}_histories.json"
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

    def _estimate_round_from_date(self, game_type: str) -> int:
        """날짜 계산 기반 회차 추정 (시작점 확보용)"""
        from datetime import date, timedelta
        today = date.today()

        if game_type == "lotto":
            base_date = date(2002, 12, 7)
            days_since_saturday = (today.weekday() + 2) % 7
            last_saturday = today - timedelta(days=days_since_saturday)
            return (last_saturday - base_date).days // 7 + 1
        elif game_type == "pension":
            base_date = date(2020, 4, 2)
            days_since_thursday = (today.weekday() - 3) % 7
            last_thursday = today - timedelta(days=days_since_thursday)
            return (last_thursday - base_date).days // 7 + 1
        return 1

    def _get_supabase(self):
        """Supabase 클라이언트 반환 (환경변수 없으면 None)"""
        supabase_url = os.environ.get("SUPABASE_URL", "")
        supabase_key = os.environ.get("SUPABASE_KEY", "")
        if not supabase_url or not supabase_key:
            return None
        from supabase import create_client
        return create_client(supabase_url, supabase_key)

    def _get_db_latest_round(self, game_type: str) -> Optional[int]:
        """round_crawl_status에서 가장 최근 확인된 회차 조회 (판매점 유무와 무관)"""
        try:
            sb = self._get_supabase()
            if not sb:
                return None
            result = sb.table("round_crawl_status") \
                .select("round") \
                .eq("lottery_type", game_type) \
                .order("round", desc=True) \
                .limit(1) \
                .execute()
            if result.data:
                return result.data[0]["round"]
            # fallback: round_crawl_status 테이블 없으면 winning_history로 폴백
            result = sb.table("winning_history") \
                .select("round") \
                .eq("lottery_type", game_type) \
                .eq("prize_tier", "first") \
                .order("round", desc=True) \
                .limit(1) \
                .execute()
            return result.data[0]["round"] if result.data else None
        except Exception as e:
            logger.warning(f"DB 최신 회차 조회 실패: {e}")
            return None

    def _get_db_latest_success_round(self, game_type: str) -> Optional[int]:
        """실제 winning_history에 저장된 가장 최근 회차 조회 (실제 저장 완료 기준)"""
        try:
            sb = self._get_supabase()
            if not sb:
                return None
            result = sb.table("winning_history") \
                .select("round") \
                .eq("lottery_type", game_type) \
                .order("round", desc=True) \
                .limit(1) \
                .execute()
            return result.data[0]["round"] if result.data else None
        except Exception as e:
            logger.warning(f"DB 최신 저장 회차 조회 실패 (winning_history): {e}")
            return None

    def _cleanup_future_pension_rounds(self, official_latest: int) -> list:
        """공식 최신 회차보다 큰 연금 미래 placeholder 행 삭제 (round_crawl_status)
        winning_history에 실제 데이터가 없는 경우에만 삭제.
        """
        deleted = []
        try:
            sb = self._get_supabase()
            if not sb:
                return deleted

            # round_crawl_status에서 official_latest 초과 연금 회차 조회
            result = sb.table("round_crawl_status") \
                .select("round,stores_status") \
                .eq("lottery_type", "pension") \
                .gt("round", official_latest) \
                .order("round") \
                .execute()
            future_rows = result.data or []

            for row in future_rows:
                r = row["round"]
                # winning_history에 실제 데이터가 있으면 삭제 안 함
                wh = sb.table("winning_history") \
                    .select("round") \
                    .eq("lottery_type", "pension") \
                    .eq("round", r) \
                    .limit(1) \
                    .execute()
                if wh.data:
                    logger.info(f"[연금] {r}회 winning_history 데이터 존재 → 삭제 생략")
                    continue
                sb.table("round_crawl_status") \
                    .delete() \
                    .eq("lottery_type", "pension") \
                    .eq("round", r) \
                    .execute()
                deleted.append(r)
                logger.info(f"[연금] 미래 placeholder {r}회 삭제 (stores_status={row['stores_status']})")

        except Exception as e:
            logger.warning(f"미래 placeholder 정리 실패: {e}")
        return deleted

    def _upsert_round_status(self, game_type: str, round_num: int, stores_status: str) -> bool:
        """round_crawl_status 테이블에 회차 상태 upsert"""
        try:
            sb = self._get_supabase()
            if not sb:
                return False
            from datetime import timezone
            now = datetime.now(timezone.utc).isoformat()
            row = {
                "lottery_type": game_type,
                "round": round_num,
                "stores_status": stores_status,
                "confirmed_at": now,
            }
            if stores_status == "success":
                row["stores_crawled_at"] = now
            sb.table("round_crawl_status").upsert(row, on_conflict="lottery_type,round").execute()
            return True
        except Exception as e:
            logger.warning(f"round_crawl_status upsert 실패 ({game_type} {round_num}회): {e}")
            return False

    def _get_pending_store_rounds(self, game_type: str, max_rounds: int = 10) -> list:
        """stores_status가 pending/empty/failed인 최근 회차 목록 반환"""
        try:
            sb = self._get_supabase()
            if not sb:
                return []
            result = sb.table("round_crawl_status") \
                .select("round") \
                .eq("lottery_type", game_type) \
                .in_("stores_status", ["pending", "empty", "failed"]) \
                .order("round", desc=True) \
                .limit(max_rounds) \
                .execute()
            return [r["round"] for r in (result.data or [])]
        except Exception as e:
            logger.warning(f"pending 회차 조회 실패: {e}")
            return []

    def _probe_round(self, game_type: str, try_round: int) -> bool:
        """단일 회차가 공식 사이트에 존재하는지 확인 (당첨 판매점 API 기반)."""
        if game_type == "lotto":
            return self._probe_lotto_stores_api(try_round)
        else:
            return self._probe_pension_api(try_round)

    def _probe_lotto_stores_api(self, try_round: int) -> bool:
        """로또 회차 존재 확인: selectLtWnShp.do 판매점 API (GitHub Actions에서도 정상 접근 가능)"""
        url = "https://www.dhlottery.co.kr/wnprchsplcsrch/selectLtWnShp.do"
        params = {"srchWnShpRnk": "all", "srchLtEpsd": try_round, "srchShpLctn": ""}
        logger.info(f"[로또] {try_round}회 판매점 API 탐색: {url}?srchLtEpsd={try_round}")
        try:
            response = self._safe_request(url, params=params)
            if not response:
                logger.warning(f"[로또] {try_round}회 응답 없음")
                return False
            ct = response.headers.get("Content-Type", "")
            logger.info(f"[로또] {try_round}회 HTTP {response.status_code} | {len(response.content)} bytes | {ct}")
            data = response.json()
            lst = (data.get("data") or {}).get("list") or []
            logger.info(f"[로또] {try_round}회 데이터 존재: {bool(lst)} (판매점 {len(lst)}개)")
            return bool(lst)
        except Exception as e:
            logger.warning(f"[로또] {try_round}회 판매점 API 탐색 실패: {e}")
            return False

    def _probe_pension_api(self, try_round: int) -> bool:
        """연금복권 회차 존재 확인: selectPtWnShp.do JSON API"""
        import traceback, urllib.parse

        url = "https://www.dhlottery.co.kr/wnprchsplcsrch/selectPtWnShp.do"
        params = {"srchWnShpRnk": "all", "srchLtEpsd": try_round, "srchShpLctn": ""}
        headers = {**self.ajax_headers, "Referer": "https://www.dhlottery.co.kr/wnprchsplcsrch/wnprchsplcsrch.do"}
        full_url = url + "?" + urllib.parse.urlencode(params)
        logger.info(f"[연금] {try_round}회 API 탐색: {full_url}")

        try:
            resp_nr = self.session.get(url, params=params, headers=headers, timeout=60,
                                       verify=False, allow_redirects=False)
            if resp_nr.status_code in (301, 302, 303, 307, 308):
                logger.warning(f"[연금] {try_round}회 리다이렉트: HTTP {resp_nr.status_code}"
                               f" → {resp_nr.headers.get('Location', '')}")

            response = self.session.get(url, params=params, headers=headers, timeout=60, verify=False)
            ct = response.headers.get("Content-Type", "")
            logger.info(f"[연금] {try_round}회 HTTP {response.status_code} | {len(response.content)} bytes"
                        f" | Content-Type: {ct} | 최종 URL: {response.url}")
            preview = response.text[:300].replace("\n", " ")
            logger.info(f"[연금] {try_round}회 응답 앞 300자: {preview}")

            if "json" not in ct.lower():
                logger.warning(f"[연금] {try_round}회 JSON 아님: {ct}")
                return False

            data = response.json()
            has_list = bool(data.get("data") and data["data"].get("list"))
            store_count = len(data["data"]["list"]) if has_list else 0
            logger.info(f"[연금] {try_round}회 데이터 존재: {has_list} (판매점 {store_count}개)")
            return has_list

        except Exception:
            logger.warning(f"[연금] {try_round}회 API 탐색 예외:\n{traceback.format_exc()}")
            return False

    def _validate_confirmed_round(self, game_type: str, confirmed: int) -> bool:
        """확정 회차 최종 검증: 판매점 API 응답 존재 + DB 최신보다 크거나 같음"""
        import traceback
        label = "로또" if game_type == "lotto" else "연금"
        try:
            if game_type == "lotto":
                if not self._probe_lotto_stores_api(confirmed):
                    logger.error(f"[{label}] 확정 {confirmed}회 판매점 API 재검증 실패")
                    return False
                logger.info(f"[{label}] 확정 {confirmed}회 검증 완료 ✅")
            else:
                if not self._probe_pension_api(confirmed):
                    logger.error(f"[{label}] 확정 {confirmed}회 재검증 실패")
                    return False
                logger.info(f"[{label}] 확정 {confirmed}회 검증 완료 ✅")

            # DB 최신 회차 비교
            # 연금은 미공개 회차가 empty 상태로 먼저 저장될 수 있으므로 success 기준으로 비교
            if game_type == "pension":
                db_latest = self._get_db_latest_success_round(game_type)
            else:
                db_latest = self._get_db_latest_round(game_type)
            if db_latest and confirmed < db_latest:
                logger.error(
                    f"[{label}] ❌ 확정 회차({confirmed}) < DB 성공 최신({db_latest})"
                    f" → 과거 회차로 업데이트 불가, 크롤링 중단"
                )
                return False
            if db_latest:
                logger.info(f"[{label}] DB 최신 회차: {db_latest}회 | 확정 회차: {confirmed}회 ✅")

            return True
        except Exception:
            logger.error(f"[{label}] 확정 회차 검증 중 예외:\n{traceback.format_exc()}")
            return False

    def get_latest_round(self, game_type: str) -> Optional[int]:
        """각 게임의 최신 회차 조회.
        1단계: 추정 회차에서 역방향 탐색
        2단계: DB 최신 이후 순방향 보완 탐색 (누락 회차 검출용)
        두 결과 중 큰 값을 최신 회차로 확정.
        """
        if "speedlotto" in game_type:
            logger.info(f"{game_type} 최신 기록 조회")
            return 1

        MAX_SEARCH = 10
        label = "로또" if game_type == "lotto" else "연금"
        estimated = self._estimate_round_from_date(game_type)

        logger.info(f"[{label}] 날짜 기반 추정 회차: {estimated}회")

        # ── 1단계: 추정 회차에서 역탐색 ──
        confirmed = None
        for try_round in range(estimated, max(estimated - MAX_SEARCH, 0), -1):
            logger.info(f"[{label}] 역탐색: {try_round}회")
            if self._probe_round(game_type, try_round):
                confirmed = try_round
                break
            time.sleep(random.uniform(0.5, 1.5))

        # ── 2단계: DB 최신 이후 순방향 보완 탐색 (누락 회차 검출) ──
        db_latest = self._get_db_latest_round(game_type)
        if db_latest:
            forward_start = db_latest + 1
            logger.info(f"[{label}] 순방향 보완 탐색: {forward_start}~{db_latest + MAX_SEARCH}회")
            last_found = None
            consecutive_miss = 0
            for try_round in range(forward_start, db_latest + MAX_SEARCH + 1):
                logger.info(f"[{label}] 순탐색: {try_round}회")
                if self._probe_round(game_type, try_round):
                    last_found = try_round
                    consecutive_miss = 0
                else:
                    consecutive_miss += 1
                    if consecutive_miss >= 2:
                        break
                time.sleep(random.uniform(0.3, 0.8))
            if last_found and (confirmed is None or last_found > confirmed):
                logger.info(f"[{label}] 순방향 탐색 결과 {last_found}회로 갱신")
                confirmed = last_found

        if confirmed is None:
            logger.error(f"[{label}] 탐색 실패 → None 반환")
            return None

        logger.info(f"[{label}] 최종 확정 회차: {confirmed}회 (검증 시작)")
        if not self._validate_confirmed_round(game_type, confirmed):
            return None

        logger.info(f"[{label}] ✅ 최신 회차 최종 확정: {confirmed}회")
        return confirmed

    def run_latest_by_game(self, game_type: str, count: int = 5):
        """게임 타입별 최신 회차 크롤링 (공식 최신 회차 ~ DB 마지막 회차+1)"""
        logger.info("=" * 70)
        logger.info(f"[{game_type}] 최신 회차 크롤링 시작")
        logger.info("=" * 70)

        if game_type == "lotto":
            official_latest = self.get_latest_round("lotto")
            date_estimate = self._estimate_round_from_date("lotto")
            if not official_latest:
                official_latest = date_estimate
                logger.warning(f"[로또] 판매점 API 탐색 실패 → 날짜 기반 추정 회차 사용: {official_latest}회")

            # 공식 탐색 결과와 날짜 추정 중 큰 값까지 시도 (데이터 공개 지연 대응)
            upper_bound = max(official_latest, date_estimate)
            if upper_bound > official_latest:
                logger.info(f"[로또] 날짜 추정({date_estimate}회)이 공식({official_latest}회)보다 높음 → {upper_bound}회까지 시도")

            db_latest = self._get_db_latest_round("lotto")
            start_round = (db_latest + 1) if db_latest else max(upper_bound - count + 1, 1)

            logger.info(f"[로또] 공식 최신 회차: {official_latest}회 | 탐색 상한: {upper_bound}회")
            logger.info(f"[로또] DB 마지막 회차: {db_latest}회" if db_latest else "[로또] DB 마지막 회차: 없음")
            logger.info(f"[로또] 수집 예정 회차: {start_round}~{upper_bound}회")

            if start_round > upper_bound:
                logger.info(f"[로또] DB가 이미 최신 상태 ({upper_bound}회). 크롤링 생략.")
            else:
                rounds_to_crawl = list(range(upper_bound, start_round - 1, -1))
                stores_success, stores_pending = [], []
                for i, round_num in enumerate(rounds_to_crawl, 1):
                    logger.info(f"\n[{i}/{len(rounds_to_crawl)}] 로또 {round_num}회 크롤링 중...")
                    self._upsert_round_status("lotto", round_num, "pending")
                    ok = self.crawl_lotto_stores(round_num)
                    if ok:
                        self._upsert_round_status("lotto", round_num, "success")
                        stores_success.append(round_num)
                    else:
                        self._upsert_round_status("lotto", round_num, "empty")
                        stores_pending.append(round_num)
                        logger.warning(f"[로또] {round_num}회 판매점 없음(empty) → 다음 회차 계속")
                    if i % 50 == 0:
                        self.save_to_files()
                    time.sleep(random.uniform(2.0, 4.0))

                # 최종 요약
                actual_db = self._get_db_latest_round("lotto")
                logger.info(f"\n[로또] 공식 최신 회차: {official_latest}회 | 탐색 상한: {upper_bound}회")
                logger.info(f"[로또] DB 최신 회차: {actual_db}회")
                logger.info(f"[로또] 회차 데이터 저장 완료: {sorted(stores_success + stores_pending)}")
                logger.info(f"[로또] 판매점 저장 완료: {sorted(stores_success) or '없음'}")
                logger.info(f"[로또] 판매점 재수집 대기: {sorted(stores_pending) or '없음'}")
                if stores_pending:
                    logger.info(f"[로또] 결과: 회차 업데이트 성공 / 판매점 부분 미완료")
                else:
                    logger.info(f"[로또] 결과: 회차 업데이트 성공 / 판매점 저장 완료")
                if actual_db != official_latest:
                    logger.error(f"[로또] ❌ round_crawl_status 불일치: DB={actual_db} 공식={official_latest}")

        elif game_type == "pension":
            official_latest = self.get_latest_round("pension")

            # 공식 최신 회차 조회 실패 시 즉시 실패 (날짜 추정 대체 금지)
            if not official_latest:
                logger.error(f"[연금] ❌ 공식 사이트 최신 회차 조회 실패 — 작업 중단")
                sys.exit(1)

            # winning_history 기준 DB 최신 성공 회차
            db_latest = self._get_db_latest_success_round("pension")

            # 공식 최신 회차보다 큰 미래 placeholder 정리
            deleted_future = self._cleanup_future_pension_rounds(official_latest)

            logger.info(f"[연금] 공식 최신 회차: {official_latest}회")
            logger.info(f"[연금] DB 최신 성공 회차 (winning_history): {db_latest}회" if db_latest else "[연금] DB 최신 성공 회차 (winning_history): 없음")
            logger.info(f"[연금] 삭제한 미래 placeholder: {sorted(deleted_future) or '없음'}")

            # 누락 회차 = 공식 사이트 존재 회차 - DB 저장 완료 회차 (미래 추정 없음)
            start_round = (db_latest + 1) if db_latest else max(official_latest - count + 1, 1)
            missing_rounds = list(range(start_round, official_latest + 1))

            logger.info(f"[연금] 누락 회차: {missing_rounds if missing_rounds else '없음 (이미 최신)'}")

            if not missing_rounds:
                logger.info(f"[연금] DB가 이미 최신 상태 ({official_latest}회). 크롤링 생략.")
            else:
                rounds_to_crawl = list(range(official_latest, start_round - 1, -1))  # 최신→오래된 순
                stores_success, stores_pending, created_rounds = [], [], []
                for i, round_num in enumerate(rounds_to_crawl, 1):
                    logger.info(f"\n[{i}/{len(rounds_to_crawl)}] 연금복권 {round_num}회 크롤링 중...")
                    # pending 삽입: 실제 수집 시작 직전에만
                    self._upsert_round_status("pension", round_num, "pending")
                    created_rounds.append(round_num)
                    ok = self.crawl_pension_stores(round_num)
                    if ok:
                        self._upsert_round_status("pension", round_num, "success")
                        stores_success.append(round_num)
                    else:
                        # 공식 범위 내 회차이므로 empty 유지 (데이터 공개 대기)
                        self._upsert_round_status("pension", round_num, "empty")
                        stores_pending.append(round_num)
                        logger.warning(f"[연금] {round_num}회 판매점 없음(empty) → 다음 회차 계속")
                    if i % 50 == 0:
                        self.save_to_files()
                    time.sleep(random.uniform(2.0, 4.0))

                # 최종 요약 (winning_history 기준)
                actual_db = self._get_db_latest_success_round("pension")
                logger.info(f"\n{'='*60}")
                logger.info(f"[연금] 크롤링 완료 요약")
                logger.info(f"[연금] 공식 최신 회차: {official_latest}회")
                logger.info(f"[연금] 작업 전 DB 최신 회차: {db_latest}회")
                logger.info(f"[연금] 작업 후 DB 최신 회차 (winning_history): {actual_db}회")
                logger.info(f"[연금] 실제 신규 생성 회차: {sorted(created_rounds) or '없음'}")
                logger.info(f"[연금] 실제 저장 성공 회차: {sorted(stores_success) or '없음'}")
                logger.info(f"[연금] 판매점 없음/재수집 대기: {sorted(stores_pending) or '없음'}")

                # 최종 일치 여부 검증
                if actual_db is not None and actual_db >= official_latest:
                    logger.info(f"[연금] ✅ winning_history({actual_db}회) >= 공식({official_latest}회) — 성공")
                else:
                    logger.error(f"[연금] ❌ winning_history({actual_db}회) < 공식({official_latest}회) — 실제 데이터 미저장")
                    logger.error(f"[연금] ❌ winning_history에 최신 회차 데이터가 없습니다. 작업 실패 처리.")
                    sys.exit(1)

        elif game_type == "speed":
            speed_max = {
                "speedlotto_2000": 68,
                "speedlotto_1000": 106,
                "speedlotto_500": 48,
            }
            for speed_type, max_round in speed_max.items():
                actual_count = min(count, max_round)
                logger.info(f"\n{'='*50}")
                logger.info(f"[{speed_type}] 1~{max_round}회 크롤링 시작 ({actual_count}회)")
                logger.info(f"{'='*50}")
                for i in range(actual_count):
                    round_num = max_round - i
                    if round_num <= 0:
                        break
                    logger.info(f"\n[{i+1}/{actual_count}] {speed_type} {round_num}회 크롤링 중...")
                    self.crawl_speedlotto_stores(speed_type, round_num)
                    if (i + 1) % 50 == 0:
                        self.save_to_files()
                        logger.info(f"[중간저장] {speed_type} {round_num}회 완료")
                    time.sleep(random.uniform(2.0, 4.0))
                self.save_to_files()
                logger.info(f"[{speed_type}] 크롤링 완료!")

        else:
            logger.error(f"알 수 없는 게임 타입: {game_type}")
            return

        self.save_to_files()
        logger.info("=" * 70)
        logger.info(f"[{game_type}] 크롤링 완료!")
        logger.info(f"총 누적 지점: {len(self.stores_data)}")
        logger.info(f"총 HTTP 요청: {self._total_requests}건")
        logger.info("=" * 70)

    def retry_pending_stores(self, game_type: str, rounds: list = None):
        """판매점 정보가 없는(pending/empty/failed) 회차 재수집
        rounds: 명시적 회차 리스트, None이면 DB에서 자동 조회
        """
        logger.info("=" * 70)
        logger.info(f"[{game_type}] 판매점 재수집 시작")
        logger.info("=" * 70)

        if rounds is None:
            rounds = self._get_pending_store_rounds(game_type, max_rounds=10)
            if not rounds:
                logger.info(f"[{game_type}] 재수집 대기 회차 없음")
                return

        # 연금: 공식 최신 회차 초과 미래 placeholder 제외
        if game_type == "pension":
            official_latest = self.get_latest_round("pension")
            if official_latest:
                future = [r for r in rounds if r > official_latest]
                if future:
                    logger.info(f"[연금] 재수집 제외 (공식 미공개 미래 회차): {sorted(future)}")
                    # 미래 placeholder 삭제
                    self._cleanup_future_pension_rounds(official_latest)
                rounds = [r for r in rounds if r <= official_latest]
                if not rounds:
                    logger.info(f"[연금] 재수집 대기 회차 없음 (미래 회차 제외 후)")
                    return
            else:
                logger.warning(f"[연금] 공식 최신 회차 조회 실패 — 재수집 목록 그대로 사용")

        logger.info(f"[{game_type}] 재수집 대상: {sorted(rounds)}")

        crawl_fn = self.crawl_lotto_stores if game_type == "lotto" else self.crawl_pension_stores
        success, still_pending = [], []
        for i, round_num in enumerate(sorted(rounds, reverse=True), 1):
            logger.info(f"\n[{i}/{len(rounds)}] {game_type} {round_num}회 판매점 재수집...")
            ok = crawl_fn(round_num)
            if ok:
                self._upsert_round_status(game_type, round_num, "success")
                success.append(round_num)
                logger.info(f"[{game_type}] {round_num}회 판매점 재수집 성공 ✅")
            else:
                still_pending.append(round_num)
                logger.warning(f"[{game_type}] {round_num}회 판매점 여전히 없음")
            time.sleep(random.uniform(2.0, 4.0))

        self.save_to_files()
        logger.info(f"\n[{game_type}] 재수집 완료: 성공 {sorted(success)}, 미완료 {sorted(still_pending)}")

    def run_latest_rounds(self, count: int = 5):
        """전체 게임 최신 N개 회차 크롤링 (하위 호환)"""
        self.run_latest_by_game("lotto", count)
        self.run_latest_by_game("pension", count)
        self.run_latest_by_game("speed", count)

    def run_all_rounds_by_round(self):
        """
        모든 회차를 크롤링 (회차별로 모든 게임 타입을 동시에 처리)
        최신회차→1회 역순 진행, 동적으로 최신 회차 탐색
        누적 데이터 기반
        """
        logger.info("=" * 70)
        logger.info("동행복권 당첨지점 크롤링 시작 (누적 버전)")
        logger.info("=" * 70)

        # 최신 회차 동적 조회
        latest_lotto = self.get_latest_round("lotto")
        time.sleep(random.uniform(3.0, 6.0))
        latest_pension = self.get_latest_round("pension")
        time.sleep(random.uniform(3.0, 6.0))

        if not latest_lotto:
            logger.error("최신 로또 회차를 조회할 수 없습니다. 중단.")
            return

        max_rounds = {
            "lotto": latest_lotto,
            "pension": latest_pension or 313,
            "speedlotto_2000": 67,
            "speedlotto_1000": 106,
            "speedlotto_500": 48
        }

        total_rounds = max_rounds["lotto"]
        logger.info(f"로또 최신: {max_rounds['lotto']}회 / 연금 최신: {max_rounds['pension']}회")

        for idx, round_num in enumerate(range(total_rounds, 0, -1)):
            # 로또
            if round_num <= max_rounds["lotto"]:
                self.crawl_lotto_stores(round_num)
                time.sleep(random.uniform(5.0, 12.0))

            # 연금복권
            if round_num <= max_rounds["pension"]:
                self.crawl_pension_stores(round_num)
                time.sleep(random.uniform(5.0, 12.0))

            # 스피또 2000
            if round_num <= max_rounds["speedlotto_2000"]:
                self.crawl_speedlotto_stores("speedlotto_2000", round_num)
                time.sleep(random.uniform(5.0, 12.0))

            # 스피또 1000
            if round_num <= max_rounds["speedlotto_1000"]:
                self.crawl_speedlotto_stores("speedlotto_1000", round_num)
                time.sleep(random.uniform(5.0, 12.0))

            # 스피또 500
            if round_num <= max_rounds["speedlotto_500"]:
                self.crawl_speedlotto_stores("speedlotto_500", round_num)
                time.sleep(random.uniform(5.0, 12.0))

            # 50회마다 중간 저장 + 추가 대기 (IP 보호 강화)
            if round_num % 50 == 0:
                self.save_to_files()
                rest_time = random.uniform(20.0, 40.0)
                logger.info(f"[중간저장+휴식] {rest_time:.1f}초 대기...")
                time.sleep(rest_time)

            # 진행률 표시
            if round_num % 100 == 0 or round_num <= 5:
                progress = total_rounds + 1 - round_num
                logger.info(f"[진행률] {progress}/{total_rounds} 회차 완료 (누적 지점: {len(self.stores_data)})")

        # 최종 데이터 저장
        logger.info("\n" + "=" * 70)
        logger.info("크롤링 완료, 데이터 저장 중...")
        logger.info("=" * 70)

        self.save_to_files()

        logger.info("=" * 70)
        logger.info("전체 크롤링 완료!")
        logger.info(f"총 누적 지점: {len(self.stores_data)}")
        logger.info(f"총 HTTP 요청: {self._total_requests}건")
        logger.info("=" * 70)


if __name__ == "__main__":
    import sys

    # 작업 디렉토리를 스크립트 위치로 변경
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)
    logger.info(f"작업 디렉토리: {os.getcwd()}")

    crawler = DHLotteryCrawler()

    # 커맨드 라인 인자 처리
    # 사용법:
    #   python lotto_verca_crawler.py                    → 전체 크롤링
    #   python lotto_verca_crawler.py latest              → 모든 게임 최신 5회차
    #   python lotto_verca_crawler.py lotto latest        → 로또만 최신 5회차
    #   python lotto_verca_crawler.py pension latest      → 연금복권만 최신 5회차
    #   python lotto_verca_crawler.py speed latest        → 스피또만 최신 5회차
    raw_args = sys.argv[1:]
    args = [a.lower() for a in raw_args]

    if len(args) == 0:
        crawler.run_all_rounds_by_round()
    elif len(args) == 1 and args[0] == "latest":
        crawler.run_latest_rounds(count=5)
    elif len(args) >= 2 and args[1] == "latest":
        game_type = args[0]
        count = int(args[2]) if len(args) >= 3 else 5
        crawler.run_latest_by_game(game_type, count=count)
    elif args[0] in ("lotto-stores", "pension-stores"):
        # 판매점 재수집
        # 사용법:
        #   python lotto_verca_crawler.py pension-stores            → pending 자동 조회
        #   python lotto_verca_crawler.py pension-stores --rounds 321,322,323
        game_type = "pension" if args[0] == "pension-stores" else "lotto"
        rounds = None
        if "--rounds" in args:
            idx = args.index("--rounds")
            if idx + 1 < len(args):
                rounds = [int(r.strip()) for r in raw_args[idx + 1].split(",")]
        crawler.retry_pending_stores(game_type, rounds=rounds)
        crawler.save_to_files()
    else:
        print("사용법:")
        print("  python lotto_verca_crawler.py                           → 전체 크롤링")
        print("  python lotto_verca_crawler.py latest                    → 모든 게임 최신 5회차")
        print("  python lotto_verca_crawler.py lotto latest              → 로또만 최신 5회차")
        print("  python lotto_verca_crawler.py pension latest            → 연금복권만 최신 5회차")
        print("  python lotto_verca_crawler.py speed latest              → 스피또만 최신 5회차")
        print("  python lotto_verca_crawler.py lotto latest 3            → 로또만 최신 3회차")
        print("  python lotto_verca_crawler.py pension-stores            → 연금 판매점 pending 자동 재수집")
        print("  python lotto_verca_crawler.py pension-stores --rounds 321,322,323  → 지정 회차 재수집")
