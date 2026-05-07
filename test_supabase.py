#!/usr/bin/env python3
import requests
import json

SUPABASE_URL = "https://unmkjwdfthanhatyudwg.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVubWtqd2RmdGhhbmhhdHl1ZHdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxNDc0MTMsImV4cCI6MjA5MjcyMzQxM30.gxHFHqS98fcUemZ5NshLjEy-WTkAeN_PNwVIwGvub-I"

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json"
}

print("=" * 70)
print("🔍 Supabase 실제 데이터 확인")
print("=" * 70)

# 최신 5개 당첨지점 데이터
print("\n📊 최신 당첨지점 5개:")
response = requests.get(
    f"{SUPABASE_URL}/rest/v1/lottery_stores?order=id.desc&limit=5",
    headers=headers
)
if response.ok:
    result = response.json()
    for item in result:
        print(f"  {item.get('round')}회 | {item.get('store_name')} | {item.get('region')} | {item.get('prize_tier')} | {item.get('lottery_type')}")
else:
    print(f"오류: {response.status_code} - {response.text}")

# 1220회 데이터 확인
print("\n🔎 1220회 당첨지점:")
response = requests.get(
    f"{SUPABASE_URL}/rest/v1/lottery_stores?round=eq.1220&limit=10",
    headers=headers
)
if response.ok:
    result = response.json()
    print(f"총 {len(result)}개")
    for item in result[:5]:
        print(f"  {item.get('store_name')} | {item.get('prize_tier')}")
else:
    print(f"오류: {response.status_code}")

# 존재하는 회차들
print("\n📍 존재하는 회차 (상위 10개):")
response = requests.get(
    f"{SUPABASE_URL}/rest/v1/lottery_stores?select=round&order=round.desc&limit=1",
    headers=headers
)
if response.ok:
    result = response.json()
    if result:
        latest = result[0].get('round')
        print(f"최신 회차: {latest}회")

print("\n" + "=" * 70)
