"""
로또 당첨번호 크롤링 (Selenium + webdriver-manager)
JavaScript 렌더링이 필요하므로 Selenium 사용
"""

import json
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from webdriver_manager.chrome import ChromeDriverManager
from selenium.webdriver.chrome.service import Service
import os

BASE_URL = "https://www.dhlottery.co.kr/tt645/result"

def setup_driver():
    """Chrome WebDriver 설정"""
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--disable-blink-features=AutomationControlled")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

    try:
        # webdriver-manager로 ChromeDriver 자동 설정
        service = Service(ChromeDriverManager().install())
        driver = webdriver.Chrome(service=service, options=chrome_options)
        print("✅ Chrome WebDriver 설정 완료")
        return driver
    except Exception as e:
        print(f"❌ WebDriver 설정 실패: {e}")
        return None

def fetch_lotto_number(driver, round_num):
    """특정 회차의 로또 당첨번호 크롤링"""
    try:
        url = f"{BASE_URL}?drwNo={round_num}"
        print(f"🔍 {round_num}회 크롤링 중: {url}")

        driver.get(url)

        # 공(ball) 요소가 로드될 때까지 대기
        WebDriverWait(driver, 15).until(
            EC.presence_of_all_elements_located((By.CLASS_NAME, "ball"))
        )

        time.sleep(2)  # 추가 렌더링 대기

        # 당첨번호 추출
        numbers = []
        bonus = None

        # 일반 공 추출
        balls = driver.find_elements(By.CLASS_NAME, "ball")
        print(f"   발견된 공: {len(balls)}개")

        for ball in balls:
            text = ball.text.strip()
            if text and text.isdigit():
                numbers.append(int(text))
                print(f"   - 번호: {text}")

        # 보너스 번호 추출
        try:
            bonus_elem = driver.find_element(By.CLASS_NAME, "bonus")
            bonus_text = bonus_elem.text.strip()
            if bonus_text.isdigit():
                bonus = int(bonus_text)
                print(f"   - 보너스: {bonus}")
        except:
            print(f"   - 보너스 미발견")

        if len(numbers) == 6 and bonus:
            print(f"✅ {round_num}회: {numbers} + {bonus}\n")
            return {
                'round': round_num,
                'numbers': numbers,
                'bonus': bonus
            }
        else:
            print(f"⚠️  {round_num}회: 데이터 불완전 (번호: {len(numbers)}개, 보너스: {bonus})\n")
            return None

    except Exception as e:
        print(f"❌ {round_num}회 오류: {e}\n")
        return None

def main():
    """메인 크롤링 함수"""
    print("🎰 로또 당첨번호 크롤링 (Selenium + webdriver-manager)")
    print("=" * 70)

    driver = setup_driver()
    if not driver:
        print("❌ Chrome WebDriver 초기화 실패")
        return

    results = []

    try:
        # 최근 3회차만 테스트 (전체는 시간이 오래 걸림)
        for round_num in range(1220, 1217, -1):
            data = fetch_lotto_number(driver, round_num)
            if data:
                results.append(data)
            time.sleep(1)  # 요청 간격

        # 결과 저장
        output_file = "lotto_numbers_crawled.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(results, f, ensure_ascii=False, indent=2)

        print("=" * 70)
        print(f"✅ 크롤링 완료!")
        print(f"   성공: {len(results)}/3")
        print(f"   저장: {output_file}")

    except Exception as e:
        print(f"❌ 크롤링 실패: {e}")

    finally:
        driver.quit()

if __name__ == "__main__":
    main()
