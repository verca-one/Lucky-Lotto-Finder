-- 연금복권720+ 당첨번호 테이블
CREATE TABLE IF NOT EXISTS pension_winning_numbers (
  round integer PRIMARY KEY,
  winning_group integer NOT NULL,      -- 1등 당첨 조 (1~5)
  winning_number text NOT NULL,        -- 1등 6자리 번호
  bonus_number text NOT NULL,          -- 보너스 6자리 번호
  draw_date text
);

ALTER TABLE pension_winning_numbers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON pension_winning_numbers FOR SELECT USING (true);
CREATE POLICY "Allow anon insert" ON pension_winning_numbers FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow anon update" ON pension_winning_numbers FOR UPDATE USING (true);
