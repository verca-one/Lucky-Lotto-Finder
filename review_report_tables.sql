-- ============================================
-- 판매점 평가 테이블
-- ============================================
CREATE TABLE IF NOT EXISTS store_reviews (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  dhlottery_code TEXT NOT NULL,
  review_key TEXT NOT NULL,
  device_id TEXT NOT NULL,
  vote_type TEXT NOT NULL CHECK (vote_type IN ('up', 'down')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(dhlottery_code, review_key, device_id)
);

CREATE INDEX IF NOT EXISTS idx_store_reviews_code ON store_reviews(dhlottery_code);
CREATE INDEX IF NOT EXISTS idx_store_reviews_device ON store_reviews(device_id);

-- RLS
ALTER TABLE store_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow read store_reviews" ON store_reviews FOR SELECT USING (true);
CREATE POLICY "Allow insert store_reviews" ON store_reviews FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow update store_reviews" ON store_reviews FOR UPDATE USING (true);
CREATE POLICY "Allow delete store_reviews" ON store_reviews FOR DELETE USING (true);

-- ============================================
-- 판매점 신고 테이블
-- ============================================
CREATE TABLE IF NOT EXISTS store_reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  dhlottery_code TEXT NOT NULL,
  device_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  detail TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'fixed', 'rejected')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_store_reports_code ON store_reports(dhlottery_code);
CREATE INDEX IF NOT EXISTS idx_store_reports_device ON store_reports(device_id);
CREATE INDEX IF NOT EXISTS idx_store_reports_status ON store_reports(status);

-- RLS
ALTER TABLE store_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow read store_reports" ON store_reports FOR SELECT USING (true);
CREATE POLICY "Allow insert store_reports" ON store_reports FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow update store_reports" ON store_reports FOR UPDATE USING (true);
CREATE POLICY "Allow delete store_reports" ON store_reports FOR DELETE USING (true);

-- ============================================
-- 평가 집계 뷰 (항목별 up/down 카운트)
-- ============================================
CREATE OR REPLACE VIEW store_review_summary AS
SELECT
  dhlottery_code,
  review_key,
  COUNT(*) FILTER (WHERE vote_type = 'up') AS up_count,
  COUNT(*) FILTER (WHERE vote_type = 'down') AS down_count
FROM store_reviews
GROUP BY dhlottery_code, review_key;
