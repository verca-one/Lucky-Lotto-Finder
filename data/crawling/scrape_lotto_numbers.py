"""
로또 당첨번호 크롤링 (API 직접 호출)
https://www.dhlottery.co.kr/common.do?method=getLottoNumber&drwNo={round}
"""

import requests
import json
import time

BASE_URL = "https://www.dhlottery.co.kr/common.do?method=getLottoNumber&drwNo="

def get_lotto(drwNo):
    """특정 회차의 로또 당첨번호 조회"""
    try:
        url = f"{BASE_URL}{drwNo}"
        res = requests.get(url, timeout=10)
        data = res.json()

        if data.get("returnValue") != "success":
            return None

        return {
            "round": drwNo,
            "numbers": [data[f"drwtNo{i}"] for i in range(1, 7)],
            "bonus": data["bnusNo"]
        }
    except Exception as e:
        print(f"❌ {drwNo}회 조회 실패: {e}")
        return None

def get_latest_round():
    """최신 회차 자동 찾기"""
    i = 1
    while True:
        if get_lotto(i) is None:
            return i - 1
        i += 1
        if i > 2000:  # 무한 루프 방지
            break
    return i - 1

def get_all_lotto(max_round=None):
    """모든 로또 당첨번호 수집"""
    if max_round is None:
        print("🔍 최신 회차 찾는 중...")
        max_round = get_latest_round()

    print(f"📊 1회차부터 {max_round}회차까지 수집 중...")
    print("=" * 70)

    results = []
    for i in range(1, max_round + 1):
        result = get_lotto(i)
        if result:
            results.append(result)
            print(f"✅ {i}회: {result['numbers']} + {result['bonus']}")
        time.sleep(0.1)  # 서버 부담 방지

    print("=" * 70)
    print(f"✅ 완료! 총 {len(results)}회차 수집")
    return results

def save_json(data, filename="lotto_numbers_crawled.json"):
    """JSON으로 저장"""
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"💾 저장: {filename}")

def get_lotto_reverse(max_round=1220):
    """역순으로 최신부터 수집"""
    print(f"📊 {max_round}회차부터 역순 수집 중...")
    print("=" * 70)

    results = []
    for i in range(max_round, 0, -1):
        result = get_lotto(i)
        if result:
            results.append(result)
            print(f"✅ {i}회: {result['numbers']} + {result['bonus']}")
        else:
            print(f"⏭️  {i}회: 데이터 없음")

        time.sleep(0.1)  # 서버 부담 방지

    print("=" * 70)
    print(f"✅ 완료! 총 {len(results)}회차 수집")
    return results

def main():
    """메인 함수"""
    print("🎰 로또 당첨번호 수집 (API)")
    print("=" * 70)

    # 1220회부터 역순으로 수집
    lotto_data = get_lotto_reverse(max_round=1220)

    if lotto_data:
        save_json(lotto_data)
        print(f"\n성공: {len(lotto_data)}회차")
    else:
        print("❌ 수집 실패")

if __name__ == "__main__":
    main()
