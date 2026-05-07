-- 연금복권 관리자 발행 추적 테이블
CREATE TABLE IF NOT EXISTS pension_rounds (
  round integer PRIMARY KEY,
  status text NOT NULL DEFAULT 'pending',
  stores_published boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  published_at timestamptz
);

ALTER TABLE pension_rounds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pension_rounds_select" ON pension_rounds FOR SELECT USING (true);
CREATE POLICY "pension_rounds_insert" ON pension_rounds FOR INSERT WITH CHECK (true);
CREATE POLICY "pension_rounds_update" ON pension_rounds FOR UPDATE USING (true);
CREATE POLICY "pension_rounds_delete" ON pension_rounds FOR DELETE USING (true);
