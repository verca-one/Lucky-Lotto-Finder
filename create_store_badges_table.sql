-- store_badges: 배지 계산 결과 캐시 테이블
CREATE TABLE IF NOT EXISTS store_badges (
  id bigserial PRIMARY KEY,
  dhlottery_code text NOT NULL,
  lottery_type text NOT NULL,        -- 'lotto', 'pension'
  badge_type text NOT NULL,          -- 'hot', 'first', 'second', 'regional', 'streak', 'rank', 'pattern'
  badge_label text NOT NULL,         -- 표시 텍스트 (예: '로또 1등 3회')
  priority integer DEFAULT 0,        -- 정렬 우선순위 (낮을수록 먼저)
  calculated_at timestamptz DEFAULT now(),
  UNIQUE(dhlottery_code, lottery_type, badge_type, badge_label)
);

CREATE INDEX IF NOT EXISTS idx_store_badges_code ON store_badges(dhlottery_code);
CREATE INDEX IF NOT EXISTS idx_store_badges_type ON store_badges(lottery_type);

ALTER TABLE store_badges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON store_badges FOR SELECT USING (true);
CREATE POLICY "Allow anon insert" ON store_badges FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow anon update" ON store_badges FOR UPDATE USING (true);
CREATE POLICY "Allow anon delete" ON store_badges FOR DELETE USING (true);
