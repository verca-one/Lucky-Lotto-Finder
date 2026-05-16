-- ============================================
-- 평가 승인 시스템 마이그레이션
-- ============================================

-- 1. store_reviews에 status 컬럼 추가
ALTER TABLE store_reviews ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';

-- 기존 데이터는 모두 approved로 (이미 반영된 평가)
UPDATE store_reviews SET status = 'approved' WHERE status IS NULL;

-- 2. 보류 테이블 (자동 승인 제외 지점)
CREATE TABLE IF NOT EXISTS review_holds (
  id SERIAL PRIMARY KEY,
  dhlottery_code TEXT NOT NULL UNIQUE,
  held_at TIMESTAMPTZ DEFAULT NOW(),
  reason TEXT
);

ALTER TABLE review_holds ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_read_holds" ON review_holds FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_holds" ON review_holds FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_delete_holds" ON review_holds FOR DELETE TO anon USING (true);

-- 3. 주단위 일괄 승인 함수 (보류 지점 제외)
CREATE OR REPLACE FUNCTION approve_pending_reviews()
RETURNS INTEGER AS $$
DECLARE
  cnt INTEGER;
BEGIN
  UPDATE store_reviews
  SET status = 'approved'
  WHERE status = 'pending'
    AND dhlottery_code NOT IN (SELECT dhlottery_code FROM review_holds);
  GET DIAGNOSTICS cnt = ROW_COUNT;
  RETURN cnt;
END;
$$ LANGUAGE plpgsql;

-- 4. store_reviews RLS 업데이트 (insert시 status 포함)
-- 기존 정책 유지, 새 투표는 pending으로 들어감
