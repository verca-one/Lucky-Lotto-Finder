-- ================================================================
-- research_v7_score_sets.sql — 판매점 전체 점수 압축 저장 (신규·독립, 재실행 가능)
-- 작성: 2026-10-11. 기존 테이블·데이터는 변경·삭제하지 않는다.
--
-- 지금까지 실전 회차마다 research_agent_store_scores 에 판매점 10,586행(약 3MB/회)을 쌓았다.
-- 같은 정보를 지방장당 1행(순위순 배열)으로 저장해 회차당 약 0.3MB 로 줄인다.
-- Worker 는 이 테이블이 있으면 여기에만 쓰고, 없으면 기존 방식으로 쓴다. 앱은 둘 다 읽는다.
-- 쓰기: service_role 만. 저장 후 UPDATE/DELETE 금지(예측 이력).
-- ================================================================

CREATE TABLE IF NOT EXISTS research_agent_score_sets (
  model_version      text NOT NULL,
  target_round       int  NOT NULL,
  agent_id           text NOT NULL,
  store_codes        text[] NOT NULL DEFAULT '{}',              -- 지방장 내 순위순 (1위부터)
  scores             double precision[] NOT NULL DEFAULT '{}',  -- 회차당 1·2등 기대 빈도 (판매량 미보정)
  live_factors       double precision[] NOT NULL DEFAULT '{}',  -- 전부 1 이면 빈 배열
  explore_factors    double precision[] NOT NULL DEFAULT '{}',  -- 전부 1 이면 빈 배열
  hyp_counts         int[] NOT NULL DEFAULT '{}',
  first_share        double precision,                          -- p_first = score × first_share
  training_end_round int  NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (model_version, target_round, agent_id)
);
CREATE INDEX IF NOT EXISTS idx_rass2_target ON research_agent_score_sets (target_round);

DROP TRIGGER IF EXISTS research_agent_score_sets_immutable ON research_agent_score_sets;
CREATE TRIGGER research_agent_score_sets_immutable BEFORE UPDATE OR DELETE ON research_agent_score_sets
  FOR EACH ROW EXECUTE FUNCTION research_agent_block_mutation();

ALTER TABLE research_agent_score_sets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS research_agent_score_sets_read ON research_agent_score_sets;
CREATE POLICY research_agent_score_sets_read ON research_agent_score_sets FOR SELECT TO anon, authenticated USING (true);

SELECT table_name FROM information_schema.tables WHERE table_name = 'research_agent_score_sets';
