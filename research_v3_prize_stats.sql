-- ================================================================
-- research_v3_prize_stats.sql — 회차별 판매액·등수별 당첨자 수 (신규·독립, 2026-10-09 수집 승인)
-- 출처: 동행복권 공개 당첨결과 JSON (/lt645/selectPstLt645InfoNew.do)
-- 기존 크롤링 테이블(lotto_winning_numbers 등)과 무관. 구매예측 실증(판매량 보정)·이월 판정용.
-- ================================================================
CREATE TABLE IF NOT EXISTS research_prize_stats (
  round               int         PRIMARY KEY,
  draw_date           date,
  num1 int, num2 int, num3 int, num4 int, num5 int, num6 int, bonus int,
  rank1_winners       int,        -- 1등 당첨자 수
  rank2_winners       int,
  rank3_winners       int,
  rank4_winners       int,
  rank5_winners       int,
  rank1_amount        bigint,     -- 1등 1인 당첨금 (원)
  rank2_amount        bigint,
  rank3_amount        bigint,
  rank4_amount        bigint,
  rank5_amount        bigint,
  rank1_total         bigint,     -- 1등 당첨금 총액
  rank2_total         bigint,
  rank3_total         bigint,
  rank4_total         bigint,
  rank5_total         bigint,
  total_sales_amount  bigint,     -- 총판매액 (wholEpsdSumNtslAmt)
  prize_pool_amount   bigint,     -- 당첨금 풀 (rlvtEpsdSumNtslAmt, ≈ 판매액 50%)
  auto_winners        int,        -- 1등 자동 (winType1)
  manual_winners      int,        -- 1등 수동 (winType2)
  semi_auto_winners   int,        -- 1등 반자동 (winType3)
  source              text        NOT NULL DEFAULT 'dhlottery:selectPstLt645InfoNew',
  official            boolean     NOT NULL DEFAULT true,
  raw                 jsonb,      -- 원본 응답 항목 보존
  collected_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_research_prize_stats_date ON research_prize_stats (draw_date);
ALTER TABLE research_prize_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "research_prize_stats_all" ON research_prize_stats;
CREATE POLICY "research_prize_stats_all" ON research_prize_stats
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

SELECT table_name FROM information_schema.tables WHERE table_name = 'research_prize_stats';
