"""
로또 당첨번호 CSV → Supabase 업로드

사전 준비:
  Supabase SQL Editor에서 아래 SQL 실행:

  CREATE TABLE IF NOT EXISTS lotto_winning_numbers (
    round integer PRIMARY KEY,
    num1 integer NOT NULL,
    num2 integer NOT NULL,
    num3 integer NOT NULL,
    num4 integer NOT NULL,
    num5 integer NOT NULL,
    num6 integer NOT NULL,
    bonus integer NOT NULL,
    draw_date text
  );

  ALTER TABLE lotto_winning_numbers ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "Allow public read" ON lotto_winning_numbers FOR SELECT USING (true);
  CREATE POLICY "Allow anon insert" ON lotto_winning_numbers FOR INSERT WITH CHECK (true);
  CREATE POLICY "Allow anon update" ON lotto_winning_numbers FOR UPDATE USING (true);

사용법:
  $env:SUPABASE_URL="your-url"
  $env:SUPABASE_KEY="your-key"
  python lotto_winning_upload.py lotto_1_1220.csv
"""

import os
import sys
import csv
import json
import requests

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("SUPABASE_URL, SUPABASE_KEY 환경변수를 설정하세요")
    exit(1)

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates,return=minimal"
}


def upload_csv(filepath):
    rows = []
    with open(filepath, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            rows.append({
                "round": int(row['회차']),
                "num1": int(row['번호1']),
                "num2": int(row['번호2']),
                "num3": int(row['번호3']),
                "num4": int(row['번호4']),
                "num5": int(row['번호5']),
                "num6": int(row['번호6']),
                "bonus": int(row['보너스']),
            })

    print(f"총 {len(rows)}건 로드됨")

    # Batch upsert (500개씩)
    batch_size = 500
    total = len(rows)
    for i in range(0, total, batch_size):
        batch = rows[i:i + batch_size]
        url = f"{SUPABASE_URL}/rest/v1/lotto_winning_numbers"
        resp = requests.post(url, headers=HEADERS, json=batch, timeout=30)
        if resp.status_code not in (200, 201):
            print(f"오류 ({resp.status_code}): {resp.text[:200]}")
            return
        done = min(i + batch_size, total)
        print(f"  [{done}/{total}] 업로드 완료")

    print(f"완료! {total}건 업로드됨")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("사용법: python lotto_winning_upload.py <csv파일>")
        exit(1)
    upload_csv(sys.argv[1])
