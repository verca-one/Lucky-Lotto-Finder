"""
Supabase lottery_stores 주소 → 좌표 변환 (지오코딩)
Nominatim (OpenStreetMap) 사용 - 완전 무료, API 키 불필요
requests만 사용 (supabase 패키지 불필요)

사용법:
  환경변수 설정:
    $env:SUPABASE_URL="your-url"
    $env:SUPABASE_KEY="your-key"

  실행:
    python lotto_verca_geocoder.py          # 좌표 없는 판매점만
    python lotto_verca_geocoder.py all       # 전체 재실행
    python lotto_verca_geocoder.py test 10   # 테스트 (10건만)
"""

import os
import sys
import time
import json
import re
import requests

# =========================
# 환경변수
# =========================
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ SUPABASE_URL, SUPABASE_KEY 환경변수를 설정하세요")
    exit(1)

SUPABASE_HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=minimal"
}

# =========================
# Supabase REST API
# =========================
def supabase_get(table, params=None):
    """Supabase REST GET"""
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
    }
    resp = requests.get(url, headers=headers, params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()

def supabase_patch(table, match_params, data):
    """Supabase REST PATCH (update)"""
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal"
    }
    resp = requests.patch(url, headers=headers, params=match_params, json=data, timeout=30)
    resp.raise_for_status()

# =========================
# Nominatim 지오코딩 (무료)
# =========================
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
NOM_HEADERS = {"User-Agent": "LuckyLottoFinder/1.0 (geocoder)"}

def geocode_address(address: str) -> tuple:
    """주소 → (latitude, longitude). 실패 시 (None, None)"""
    clean = re.sub(r'\(.*?\)', '', address).strip()
    clean = re.sub(r'\d+층.*$', '', clean).strip()
    clean = re.sub(r'\d+호.*$', '', clean).strip()

    params = {"q": clean, "format": "json", "limit": 1, "countrycodes": "kr"}

    try:
        resp = requests.get(NOMINATIM_URL, headers=NOM_HEADERS, params=params, timeout=15)
        if resp.status_code == 429:
            print("⚠️  요청 한도 초과. 60초 대기...")
            time.sleep(60)
            resp = requests.get(NOMINATIM_URL, headers=NOM_HEADERS, params=params, timeout=15)
        if resp.status_code != 200:
            return (None, None)

        data = resp.json()
        if data:
            lat = float(data[0].get("lat", 0))
            lng = float(data[0].get("lon", 0))
            if lat != 0 and lng != 0:
                return (lat, lng)

        # 시/구까지만으로 재시도
        parts = clean.split()
        if len(parts) >= 2:
            params["q"] = " ".join(parts[:2])
            time.sleep(1.1)
            resp2 = requests.get(NOMINATIM_URL, headers=NOM_HEADERS, params=params, timeout=15)
            if resp2.status_code == 200:
                data2 = resp2.json()
                if data2:
                    lat = float(data2[0].get("lat", 0))
                    lng = float(data2[0].get("lon", 0))
                    if lat != 0 and lng != 0:
                        return (lat, lng)

        return (None, None)
    except Exception as e:
        print(f"  ⚠️  지오코딩 오류: {e}")
        return (None, None)

# =========================
# 판매점 조회
# =========================
def get_stores(only_missing=True, limit=None):
    all_stores = []
    page_size = 1000
    offset = 0

    while True:
        params = {
            "select": "id,dhlottery_code,store_name,address,lottery_type",
            "order": "id.asc",
            "offset": str(offset),
            "limit": str(page_size),
        }
        if only_missing:
            params["latitude"] = "is.null"

        batch = supabase_get("lottery_stores", params)
        all_stores.extend(batch)

        if len(batch) < page_size:
            break
        offset += page_size
        if limit and len(all_stores) >= limit:
            all_stores = all_stores[:limit]
            break

    return all_stores

# =========================
# 좌표 업데이트
# =========================
def update_coords(store_id: int, lat: float, lng: float):
    supabase_patch(
        "lottery_stores",
        {"id": f"eq.{store_id}"},
        {"latitude": lat, "longitude": lng}
    )

# =========================
# 중간저장
# =========================
PROGRESS_FILE = "geocoder_progress.json"

def load_progress():
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, "r") as f:
            return set(json.load(f))
    return set()

def save_progress(done_ids):
    with open(PROGRESS_FILE, "w") as f:
        json.dump(list(done_ids), f)

# =========================
# 메인
# =========================
def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "missing"
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else None

    if mode == "all":
        print("🔄 전체 판매점 지오코딩 시작...")
        stores = get_stores(only_missing=False, limit=limit)
    elif mode == "test":
        test_limit = limit or 10
        print(f"🧪 테스트: {test_limit}건")
        stores = get_stores(only_missing=True, limit=test_limit)
    elif mode == "missing":
        print("📍 좌표 없는 판매점만 지오코딩...")
        stores = get_stores(only_missing=True, limit=limit)
    else:
        print("사용법: python lotto_verca_geocoder.py [missing|all|test] [limit]")
        return

    total = len(stores)
    print(f"  대상: {total:,}개")
    if total == 0:
        print("✅ 처리할 판매점이 없습니다.")
        return

    done_ids = load_progress()
    success = failed = skipped = 0

    for i, store in enumerate(stores):
        sid = store.get("id")
        addr = store.get("address", "")

        if sid in done_ids:
            skipped += 1
            continue

        if "dhlottery.co.kr" in addr or "동행복권" in addr or len(addr) < 5:
            skipped += 1
            done_ids.add(sid)
            continue

        lat, lng = geocode_address(addr)
        if lat and lng:
            update_coords(sid, lat, lng)
            success += 1
        else:
            failed += 1

        done_ids.add(sid)

        if (i + 1) % 50 == 0 or (i + 1) == total:
            pct = (i + 1) / total * 100
            print(f"  [{i+1:,}/{total:,}] {pct:.1f}% | 성공:{success:,} 실패:{failed} 스킵:{skipped}")
            save_progress(done_ids)

        time.sleep(1.1)  # Nominatim 초당 1건 제한

    save_progress(done_ids)
    print(f"\n✅ 완료! 성공:{success:,} 실패:{failed} 스킵:{skipped}")

if __name__ == "__main__":
    main()
