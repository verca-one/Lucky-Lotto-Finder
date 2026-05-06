"""
당첨번호 수집 스크립트
로또, 연금복권, 스피또의 당첨번호를 API에서 수집
"""

import json
import time
import random
import requests
from datetime import datetime
from typing import Optional, Dict, List
import logging
import urllib3
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from bs4 import BeautifulSoup
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
try:
    from tqdm import tqdm
except ImportError:
    def tqdm(iterable, **kwargs):
        return iterable

# SSL 경고 무시
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WinningNumbersCrawler:
    """당첨번호 크롤러"""

    def __init__(self):
        self.base_url = "https://www.dhlottery.co.kr"
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Encoding': 'gzip, deflate, br',
            'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
            'Connection': 'keep-alive',
            'Referer': 'https://www.dhlottery.co.kr/wnprchsplcsrch/wnprchsplcsrch.do'
        }

        # 재시도 로직이 있는 session 설정
        self.session = requests.Session()
        retry_strategy = Retry(
            total=5,
            backoff_factor=2,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

    def get_lotto_numbers(self, round_no: int) -> Optional[Dict]:
        """로또 당첨번호 조회 (HTML 파싱 → JSON API Fallback)"""
        # 1차: HTML 파싱 (더 안정적)
        try:
            html_url = "https://dhlottery.co.kr/gameResult.do"
            html_params = {
                "method": "byWin",
                "drwNo": round_no
            }
            html_headers = self.headers.copy()
            html_headers.update({
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Referer": "https://dhlottery.co.kr/gameResult.do?method=byWin"
            })

            response = self.session.get(html_url, params=html_params, headers=html_headers, timeout=60, verify=False)
            response.encoding = "utf-8"
            soup = BeautifulSoup(response.text, "html.parser")

            # 로또 번호는 ball_645 클래스로 추출 (더 안정적)
            number_tags = soup.select(".win_result .ball_645")
            if len(number_tags) >= 7:
                # 모든 숫자 추출 및 검증
                all_numbers = []
                for tag in number_tags:
                    text = tag.get_text(strip=True)
                    if text.isdigit():
                        all_numbers.append(int(text))

                if len(all_numbers) >= 7:
                    numbers = all_numbers[:6]
                    bonus = all_numbers[6]

                    # 날짜 추출
                    date_tag = soup.select_one(".win_result .desc")
                    draw_date = date_tag.get_text(strip=True) if date_tag else ""

                    logger.info(f"✅ 로또 {round_no}회: HTML 파싱 성공")
                    return {
                        "lottery_type": "lotto",
                        "round": round_no,
                        "draw_date": draw_date,
                        "numbers": numbers,
                        "bonus": bonus,
                        "first_winner_count": None,
                        "first_prize_amount": None,
                        "total_sell_amount": None,
                        "created_at": datetime.now().isoformat()
                    }

            logger.warning(f"⚠️  로또 {round_no}회: HTML 파싱 실패 → JSON API로 전환")
        except Exception as e:
            logger.warning(f"⚠️  로또 {round_no}회: HTML 파싱 오류 → JSON API 시도 / {e}")

        # 2차: JSON API Fallback
        try:
            api_url = "https://www.dhlottery.co.kr/common.do"
            params = {
                "method": "getLottoNumber",
                "drwNo": round_no
            }
            headers = self.headers.copy()
            headers.update({
                "Accept": "application/json, text/javascript, */*; q=0.01",
                "Referer": "https://www.dhlottery.co.kr/gameResult.do?method=byWin",
                "X-Requested-With": "XMLHttpRequest"
            })

            response = self.session.get(api_url, params=params, headers=headers, timeout=60, verify=False)
            text = response.text.strip()

            if text.startswith("{"):
                data = response.json()
                if data.get("returnValue") == "success":
                    logger.info(f"✅ 로또 {round_no}회: JSON API 성공")
                    return {
                        "lottery_type": "lotto",
                        "round": data.get("drwNo"),
                        "draw_date": data.get("drwNoDate"),
                        "numbers": [
                            data.get("drwtNo1"),
                            data.get("drwtNo2"),
                            data.get("drwtNo3"),
                            data.get("drwtNo4"),
                            data.get("drwtNo5"),
                            data.get("drwtNo6")
                        ],
                        "bonus": data.get("bnusNo"),
                        "first_winner_count": data.get("firstPrzwnerCo"),
                        "first_prize_amount": data.get("firstWinamnt"),
                        "total_sell_amount": data.get("totSellamnt"),
                        "created_at": datetime.now().isoformat()
                    }

            logger.error(f"❌ 로또 {round_no}회: JSON API도 실패")
            return None
        except Exception as e:
            logger.error(f"❌ 로또 {round_no}회: 모두 실패 / {e}")
            return None

    def get_pension_numbers(self, round_no: int) -> Optional[Dict]:
        """연금복권 당첨번호 조회 (HTML 파싱 → JSON API Fallback)"""
        # 1차: HTML 파싱
        try:
            html_url = "https://dhlottery.co.kr/gameResult.do"
            html_params = {
                "method": "byWin",
                "drwNo": round_no,
                "gubun": "039"  # 연금복권 코드
            }
            html_headers = self.headers.copy()
            html_headers.update({
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Referer": "https://dhlottery.co.kr/gameResult.do?method=byWin&gubun=039"
            })

            response = self.session.get(html_url, params=html_params, headers=html_headers, timeout=60, verify=False)
            response.encoding = "utf-8"
            soup = BeautifulSoup(response.text, "html.parser")

            # 연금복권 번호 추출
            number_tags = soup.select(".win_result .num")
            if len(number_tags) >= 1:
                numbers = []
                for tag in number_tags:
                    text = tag.get_text(strip=True)
                    if text.isdigit():
                        numbers.append(int(text))

                if numbers:
                    # 날짜 추출
                    date_tag = soup.select_one(".win_result .desc")
                    draw_date = date_tag.get_text(strip=True) if date_tag else ""

                    logger.info(f"✅ 연금복권 {round_no}회: HTML 파싱 성공")
                    return {
                        "lottery_type": "pension",
                        "round": round_no,
                        "draw_date": draw_date,
                        "numbers": numbers,
                        "created_at": datetime.now().isoformat()
                    }

            logger.warning(f"⚠️  연금복권 {round_no}회: HTML 파싱 실패 → JSON API로 전환")
        except Exception as e:
            logger.warning(f"⚠️  연금복권 {round_no}회: HTML 파싱 오류 → JSON API 시도 / {e}")

        # 2차: JSON API Fallback
        try:
            url = "https://www.dhlottery.co.kr/common.do"
            params = {
                "method": "getPensionNumber",
                "drwNo": round_no
            }
            headers = self.headers.copy()
            headers["Referer"] = "https://www.dhlottery.co.kr/lottoResult.do?method=byWin"

            response = self.session.get(url, params=params, headers=headers, timeout=60, verify=False)
            response.raise_for_status()

            # JSON 응답 확인
            if "application/json" not in response.headers.get("Content-Type", ""):
                logger.warning(f"❌ 연금복권 {round_no}회: HTML 응답 (차단됨)")
                return None

            data = response.json()

            if data.get("returnValue") != "success":
                logger.debug(f"❌ 연금복권 {round_no}회: 데이터 없음")
                return None

            logger.info(f"✅ 연금복권 {round_no}회: JSON API 성공")
            return {
                "lottery_type": "pension",
                "round": data.get("drwNo"),
                "draw_date": data.get("drwNoDate"),
                "numbers": data.get("bnusNo"),
                "created_at": datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"❌ 연금복권 {round_no}회 조회 실패: {e}")
            return None

    def get_speedlotto_numbers(self, game_type: str, round_no: int) -> Optional[Dict]:
        """스피또 당첨번호 조회 (HTML 파싱 → JSON API Fallback)"""
        game_type_map = {
            "speedlotto_2000": ("01", "스피또2000"),
            "speedlotto_1000": ("02", "스피또1000"),
            "speedlotto_500": ("03", "스피또500")
        }
        game_code, game_name = game_type_map.get(game_type, ("01", "스피또2000"))

        # 1차: HTML 파싱
        try:
            html_url = "https://dhlottery.co.kr/gameResult.do"
            html_params = {
                "method": "byWin",
                "drwNo": round_no,
                "gubun": game_code  # 스피또 코드
            }
            html_headers = self.headers.copy()
            html_headers.update({
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Referer": f"https://dhlottery.co.kr/gameResult.do?method=byWin&gubun={game_code}"
            })

            response = self.session.get(html_url, params=html_params, headers=html_headers, timeout=60, verify=False)
            response.encoding = "utf-8"
            soup = BeautifulSoup(response.text, "html.parser")

            # 스피또 번호 추출
            number_tags = soup.select(".win_result .num")
            if len(number_tags) >= 1:
                numbers = []
                for tag in number_tags:
                    text = tag.get_text(strip=True)
                    if text.isdigit():
                        numbers.append(int(text))

                if numbers:
                    # 날짜 추출
                    date_tag = soup.select_one(".win_result .desc")
                    draw_date = date_tag.get_text(strip=True) if date_tag else ""

                    logger.info(f"✅ {game_type} {round_no}회: HTML 파싱 성공")
                    return {
                        "lottery_type": game_type,
                        "round": round_no,
                        "draw_date": draw_date,
                        "numbers": numbers,
                        "created_at": datetime.now().isoformat()
                    }

            logger.warning(f"⚠️  {game_type} {round_no}회: HTML 파싱 실패 → JSON API로 전환")
        except Exception as e:
            logger.warning(f"⚠️  {game_type} {round_no}회: HTML 파싱 오류 → JSON API 시도 / {e}")

        # 2차: JSON API Fallback
        try:
            url = f"{self.base_url}/st/drwNoInfo.do?drwNo={round_no}"
            response = self.session.get(url, headers=self.headers, timeout=60, verify=False)
            response.raise_for_status()
            data = response.json()

            if not data.get("data"):
                logger.debug(f"{game_type} {round_no}회: JSON API 실패")
                return None

            logger.info(f"✅ {game_type} {round_no}회: JSON API 성공")
            return {
                "lottery_type": game_type,
                "round": round_no,
                "draw_date": data.get("drwNoDate"),
                "numbers": data.get("data"),
                "created_at": datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"❌ {game_type} {round_no}회 조회 실패: {e}")
            return None

    def _fetch_single_number(self, game_type: str, round_no: int) -> Optional[Dict]:
        """단일 회차 당첨번호 수집 (병렬 처리용)"""
        time.sleep(random.uniform(0.1, 0.3))  # 요청 간 간격

        if game_type == "lotto":
            return self.get_lotto_numbers(round_no)
        elif game_type == "pension":
            return self.get_pension_numbers(round_no)
        else:
            return self.get_speedlotto_numbers(game_type, round_no)

    def fetch_recent_numbers(self, count: int = 5) -> List[Dict]:
        """최신 N개 회차의 당첨번호 수집 (병렬 처리)"""
        logger.info("=" * 70)
        logger.info(f"당첨번호 수집 시작 (병렬 처리 - {count}개 회차)")
        logger.info("=" * 70)

        winning_numbers = []

        # 각 게임별 최대 회차
        latest_rounds = {
            "lotto": 1221,
            "pension": 312,
            "speedlotto_2000": 67,
            "speedlotto_1000": 106,
            "speedlotto_500": 48,
        }

        # 수집할 작업 리스트
        tasks = []

        # 로또
        for round_no in range(latest_rounds["lotto"], latest_rounds["lotto"] - count, -1):
            tasks.append(("lotto", round_no))

        # 연금복권
        for round_no in range(latest_rounds["pension"], latest_rounds["pension"] - count, -1):
            tasks.append(("pension", round_no))

        # 스피또 2000
        for round_no in range(latest_rounds["speedlotto_2000"], latest_rounds["speedlotto_2000"] - count, -1):
            tasks.append(("speedlotto_2000", round_no))

        # 스피또 1000
        for round_no in range(latest_rounds["speedlotto_1000"], latest_rounds["speedlotto_1000"] - count, -1):
            tasks.append(("speedlotto_1000", round_no))

        # 스피또 500
        for round_no in range(latest_rounds["speedlotto_500"], latest_rounds["speedlotto_500"] - count, -1):
            tasks.append(("speedlotto_500", round_no))

        # 병렬 처리 (max_workers=3으로 서버 부하 조절)
        logger.info(f"📍 총 {len(tasks)}개 회차 병렬 수집 중...")

        with ThreadPoolExecutor(max_workers=3) as executor:
            future_to_task = {
                executor.submit(self._fetch_single_number, game_type, round_no): (game_type, round_no)
                for game_type, round_no in tasks
            }

            completed = 0
            for future in as_completed(future_to_task):
                game_type, round_no = future_to_task[future]
                try:
                    result = future.result()
                    if result:
                        winning_numbers.append(result)
                        logger.info(f"  ✅ {game_type} {round_no}회: 수집 완료")
                    else:
                        logger.warning(f"  ⚠️  {game_type} {round_no}회: 조회 실패")
                except Exception as e:
                    logger.error(f"  ❌ {game_type} {round_no}회: {e}")

                completed += 1
                if completed % 10 == 0:
                    logger.info(f"  진행률: {completed}/{len(tasks)}")

        # 저장
        self.save_winning_numbers(winning_numbers)

        logger.info("\n" + "=" * 70)
        logger.info(f"✅ 당첨번호 수집 완료!")
        logger.info(f"총 {len(winning_numbers)}개 항목 수집")
        logger.info("=" * 70)

        return winning_numbers

    def save_winning_numbers(self, winning_numbers: List[Dict]) -> None:
        """당첨번호 저장"""
        try:
            output = {
                "crawled_at": datetime.now().isoformat(),
                "total_items": len(winning_numbers),
                "numbers": winning_numbers
            }

            filename = "lotto_verca_winning_numbers.json"
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(output, f, ensure_ascii=False, indent=2)

            logger.info(f"✅ 저장 완료: {filename}")
        except Exception as e:
            logger.error(f"❌ 저장 실패: {e}")


if __name__ == "__main__":
    import sys

    # 작업 디렉토리 설정
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)
    logger.info(f"작업 디렉토리: {os.getcwd()}")

    crawler = WinningNumbersCrawler()

    # 기본값 5회, 인자로 개수 지정 가능
    count = 5
    if len(sys.argv) > 1:
        try:
            count = int(sys.argv[1])
        except ValueError:
            logger.warning(f"잘못된 인자: {sys.argv[1]}, 기본값 5 사용")

    crawler.fetch_recent_numbers(count=count)
