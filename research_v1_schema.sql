-- ================================================================
-- research_v1_schema.sql — 예측 연구 시스템 (신규·독립)
-- 기존 크롤링 테이블(lottery_stores, winning_history, lotto_winning_numbers 등)은
-- 읽기 전용으로만 사용하며 이 파일은 신규 테이블 2개만 생성한다.
-- ================================================================

-- 1. 연구 결과 누적 저장 (번호 빈도, WF 무작위 대조군, 구매예측 모델 등)
CREATE TABLE IF NOT EXISTS research_results (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  research_type      text        NOT NULL,   -- number_frequency | engine_wf_control | region_wf_control | purchase_model | purchase_recommend | store_analysis
  model_version      text        NOT NULL,
  training_end_round int         NOT NULL,   -- 사용한 데이터의 마지막 회차
  target_round       int         NOT NULL DEFAULT 0, -- 예측 대상 회차 (해당 없으면 0)
  payload            jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_research_result UNIQUE (research_type, model_version, training_end_round, target_round)
);
CREATE INDEX IF NOT EXISTS idx_research_results_lookup
  ON research_results (research_type, model_version, training_end_round DESC);
ALTER TABLE research_results ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "research_results_all" ON research_results;
CREATE POLICY "research_results_all" ON research_results
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 2. 사전 등록 예측 (판매 마감 전 생성·잠금 → 추첨 후 자동 채점)
CREATE TABLE IF NOT EXISTS research_predictions (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  algorithm       text        NOT NULL,   -- number_engine | purchase_prediction | random_control
  version         text        NOT NULL,
  target_round    int         NOT NULL,
  data_end_round  int         NOT NULL,   -- 사용한 데이터의 마지막 회차
  sets            jsonb       NOT NULL,   -- [[n1..n6], ...]
  generated_at    timestamptz NOT NULL DEFAULT now(),
  deadline_at     timestamptz NOT NULL,   -- 해당 회차 판매 마감 (토 20:00 KST)
  pre_deadline    boolean     NOT NULL DEFAULT true, -- 마감 전 생성 여부 (사후 생성은 실적 불인정)
  locked          boolean     NOT NULL DEFAULT true, -- 번호 변경 불가
  verification    jsonb,                  -- 채점 결과 (추첨 후)
  status          text        NOT NULL DEFAULT 'pending', -- pending | verified | invalid
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_research_prediction UNIQUE (algorithm, version, target_round)
);
CREATE INDEX IF NOT EXISTS idx_research_predictions_lookup
  ON research_predictions (algorithm, version, target_round DESC);
ALTER TABLE research_predictions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "research_predictions_all" ON research_predictions;
CREATE POLICY "research_predictions_all" ON research_predictions
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 잠금 보장: sets/generated_at/target_round 는 수정 불가 (채점 필드만 갱신 가능)
CREATE OR REPLACE FUNCTION research_predictions_lock() RETURNS trigger AS $$
BEGIN
  IF OLD.locked AND (NEW.sets IS DISTINCT FROM OLD.sets
                     OR NEW.generated_at IS DISTINCT FROM OLD.generated_at
                     OR NEW.target_round IS DISTINCT FROM OLD.target_round
                     OR NEW.algorithm IS DISTINCT FROM OLD.algorithm
                     OR NEW.version IS DISTINCT FROM OLD.version) THEN
    RAISE EXCEPTION 'research_predictions row is locked';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_research_predictions_lock ON research_predictions;
CREATE TRIGGER trg_research_predictions_lock
  BEFORE UPDATE ON research_predictions
  FOR EACH ROW EXECUTE FUNCTION research_predictions_lock();

-- 확인
SELECT table_name FROM information_schema.tables
WHERE table_name IN ('research_results', 'research_predictions');
