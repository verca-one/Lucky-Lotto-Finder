#!/usr/bin/env python3
import requests
import json

# Supabase 설정
SUPABASE_URL = "https://unmkjwdfthanhatyudwg.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVubWtqd2RmdGhhbmhhdHl1ZHdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxNDc0MTMsImV4cCI6MjA5MjcyMzQxM30.gxHFHqS98fcUemZ5NshLjEy-WTkAeN_PNwVIwGvub-I"

# API 엔드포인트
headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json"
}

print("=" * 60)
print("🔍 Supabase 데이터 확인")
print("=" * 60)

# 1. lottery_stores 테이블 데이터 샘플
print("\n📊 lottery_stores 테이블 샘플 (최신 5개):")
response = requests.get(
    f"{SUPABASE_URL}/rest/v1/lottery_stores?select=round,store_name,prize_tier,lottery_type&order=created_at.desc&limit=5",
    headers=headers
)
if response.ok:
    result = response.json()
    if result:
        print(f"✅ 테이블 존재: {len(result)}개 항목")
        for item in result:
            print(f"  - {item.get('round')}회 | {item.get('store_name')} | {item.get('prize_tier')} | {item.get('lottery_type')}")
    else:
        print("❌ 데이터 없음")
else:
    print(f"❌ 오류: {response.status_code} - {response.text}")

# 2. 1220회 당첨지점 확인
print("\n🔎 1220회 당첨지점 조회:")
response = requests.get(
    f"{SUPABASE_URL}/rest/v1/lottery_stores?round=eq.1220&lottery_type=eq.lotto&select=store_name,prize_tier,region&limit=5",
    headers=headers
)
if response.ok:
    result = response.json()
    if result:
        print(f"✅ 1220회 당첨지점 {len(result)}개 발견!")
        for item in result:
            print(f"  - {item.get('store_name')} ({item.get('region')}) | {item.get('prize_tier')}")
    else:
        print("❌ 1220회 당첨지점 없음")
else:
    print(f"❌ 오류: {response.status_code}")

# 3. 최신 회차 확인
print("\n📍 최신 회차:")
response = requests.get(
    f"{SUPABASE_URL}/rest/v1/lottery_stores?select=round&order=round.desc&limit=1",
    headers=headers
)
if response.ok:
    result = response.json()
    if result:
        latest_round = result[0].get('round')
        print(f"✅ 최신 회차: {latest_round}회")

        # 최신 회차의 당첨지점 개수
        print(f"\n   {latest_round}회 당첨지점 조회:")
        response2 = requests.get(
            f"{SUPABASE_URL}/rest/v1/lottery_stores?round=eq.{latest_round}&lottery_type=eq.lotto&select=store_name&limit=10",
            headers=headers
        )
        if response2.ok:
            stores = response2.json()
            print(f"   - 1등/2등 지점: {len(stores)}개")
            for store in stores[:5]:
                print(f"     • {store.get('store_name')}")
            if len(stores) > 5:
                print(f"     ... 그 외 {len(stores)-5}개")
        else:
            print(f"   ❌ 오류: {response2.status_code}")
    else:
        print("❌ 데이터 없음")
else:
    print(f"❌ 오류: {response.status_code}")

# 4. 테이블 목록
print("\n📋 사용 가능한 테이블:")
response = requests.get(
    f"{SUPABASE_URL}/rest/v1/",
    headers=headers
)
if response.ok:
    tables = response.json()
    for table in tables:
        print(f"  - {table.get('name')}")
else:
    print(f"❌ 오류: {response.status_code}")

print("\n" + "=" * 60)
