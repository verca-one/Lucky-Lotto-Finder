-- ================================================================
-- research_v15_strategy_sim.sql — 가설 모의(시뮬레이션) 결과 칸 추가
-- 비서가 가설을 '구매 전략'으로 적용했다면 1001회~ 실제 결과가 어떻게 달라졌을지 모의한 결과를 저장한다.
-- 앱은 읽기만, 쓰기는 서버(service_role)만 (research_v14 정책 그대로). 크롤링 테이블과 무관.
-- ================================================================
ALTER TABLE strategy_hypotheses ADD COLUMN IF NOT EXISTS simulation jsonb;

-- 확인
SELECT 'simulation_column' AS check,
       (count(*) = 1)::text AS value
  FROM information_schema.columns
 WHERE table_name = 'strategy_hypotheses' AND column_name = 'simulation';
