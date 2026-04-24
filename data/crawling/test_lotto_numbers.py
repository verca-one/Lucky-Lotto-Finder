"""
로또 당첨번호 크롤링 테스트
1210~1220회 (10회차만)
"""

import requests
from bs4 import BeautifulSoup
import json
import time

BASE_URL = "https://www.dhlottery.co.kr/tt645/result"

def fetch_lotto_numbers(round_num):
    """로또 당첨번호 크롤링"""
    try:
        url = f"{BASE_URL}?drwNo={round_num}"

        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }

        print(f"🔍 크롤링 중: {round_num}회 - {url}")
        response = requests.get(url, headers=headers, timeout=10)
        response.encoding = 'utf-8'

        if response.status_code != 200:
            print(f"❌ HTTP {response.status_code}")
            return None

        soup = BeautifulSoup(response.content, 'html.parser')

        # 당첨번호 찾기
        numbers = []
        bonus = None

        # 방법 1: 공 클래스로 찾기
        balls = soup.find_all('span', {'class': ['ball']})

        if balls:
            print(f"   공 {len(balls)}개 발견")
            for i, ball in enumerate(balls):
                num = ball.text.strip()
                if num and num.isdigit():
                    numbers.append(int(num))
                    print(f"   - {i+1}: {num}")

        # 보너스 찾기
        bonus_element = soup.find('span', {'class': ['bonus']})
        if bonus_element:
            bonus_text = bonus_element.text.strip()
            if bonus_text.isdigit():
                bonus = int(bonus_text)
                print(f"   보너스: {bonus}")

        if numbers and bonus is not None:
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
    """메인 테스트 함수"""
    print("🎰 로또 당첨번호 크롤링 테스트")
    print("=" * 70)
    print("범위: 1210~1220회 (10회차)\n")

    results = []

    for round_num in range(1210, 1221):
        data = fetch_lotto_numbers(round_num)

        if data:
            results.append(data)

        time.sleep(1)  # 요청 간격

    # 결과 저장
    output_file = "test_lotto_numbers.json"
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    print("=" * 70)
    print(f"✅ 테스트 완료!")
    print(f"   성공: {len(results)}/10")
    print(f"   저장: {output_file}")

if __name__ == "__main__":
    main()
