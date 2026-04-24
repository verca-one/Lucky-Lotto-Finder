"""
로또 페이지 HTML 구조 분석
당첨번호가 어디에 있는지 찾기
"""

import requests
from bs4 import BeautifulSoup
import json

BASE_URL = "https://www.dhlottery.co.kr/tt645/result"

def analyze_html(round_num):
    """HTML 구조 분석"""
    try:
        url = f"{BASE_URL}?drwNo={round_num}"

        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }

        print(f"🔍 분석 중: {round_num}회")
        response = requests.get(url, headers=headers, timeout=10)
        response.encoding = 'utf-8'

        if response.status_code != 200:
            print(f"❌ HTTP {response.status_code}\n")
            return

        soup = BeautifulSoup(response.content, 'html.parser')

        # 전체 HTML 저장
        html_file = f"lotto_{round_num}_raw.html"
        with open(html_file, 'w', encoding='utf-8') as f:
            f.write(soup.prettify())
        print(f"✅ HTML 저장: {html_file}")

        # 숫자가 포함된 모든 span 찾기
        print("\n🔍 모든 span 요소 (숫자 포함):")
        spans = soup.find_all('span')
        print(f"   총 span: {len(spans)}개\n")

        number_spans = []
        for i, span in enumerate(spans):
            text = span.text.strip()
            if text and any(c.isdigit() for c in text):
                classes = span.get('class', [])
                print(f"   [{i}] {text}")
                print(f"        클래스: {classes}")
                print(f"        HTML: {str(span)[:100]}...")
                print()
                number_spans.append({
                    'index': i,
                    'text': text,
                    'class': classes
                })

        # 당첨번호 관련 키워드 찾기
        print("\n🔍 당첨번호 관련 요소:")
        for keyword in ['drw', 'number', 'ball', 'result', '당첨', '번호']:
            elements = soup.find_all(string=lambda text: text and keyword in str(text).lower())
            if elements:
                print(f"   '{keyword}' 포함: {len(elements)}개")
                for elem in elements[:3]:
                    print(f"      - {str(elem)[:80]}")

        # div, p 등 다른 요소도 확인
        print("\n🔍 div/article 구조:")
        divs = soup.find_all('div', limit=20)
        articles = soup.find_all('article', limit=10)
        print(f"   div: {len(divs)}개")
        print(f"   article: {len(articles)}개")

        if articles:
            print(f"\n   첫 번째 article:")
            print(articles[0].prettify()[:500])

    except Exception as e:
        print(f"❌ 오류: {e}\n")

def main():
    print("🎰 로또 HTML 구조 분석")
    print("=" * 70)

    # 1220회만 분석
    analyze_html(1220)

if __name__ == "__main__":
    main()
