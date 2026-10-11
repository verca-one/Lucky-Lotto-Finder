-- ================================================================
-- research_v2_replay_rounds.sql — 500→최신 순차 가설 재현의 회차별 실행 로그 (신규·독립)
-- 선행: research_v1_schema.sql, research_v1_1_mc_rls.sql
-- 각 회차 t: 사용 데이터 ≤ t, 생성·검증·전환 수, 가설 상태, 다음 회차 예측(발화한 가설) 저장
-- ================================================================
CREATE TABLE IF NOT EXISTS research_replay_rounds (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  model_version    text        NOT NULL,
  round            int         NOT NULL,          -- 연구 기준 회차 (이 회차 결과까지 반영)
  data_end_round   int         NOT NULL,          -- 사용한 데이터의 마지막 회차 (= round)
  created          int         NOT NULL DEFAULT 0, -- 이 회차에 새로 발견된 가설 수
  verified         int         NOT NULL DEFAULT 0, -- 이 회차 결과로 검증된 예측 수
  hits             int         NOT NULL DEFAULT 0, -- 그중 적중 수
  transitions      int         NOT NULL DEFAULT 0, -- 생명주기 전환 수
  status_counts    jsonb       NOT NULL DEFAULT '{}'::jsonb,
  accepted_keys    jsonb       NOT NULL DEFAULT '[]'::jsonb,
  predictions_next jsonb       NOT NULL DEFAULT '[]'::jsonb, -- 발화한 가설의 목표 회차·방향 (당시 정보만 사용)
  status           text        NOT NULL DEFAULT 'completed',
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_research_replay_round UNIQUE (model_version, round)
);
CREATE INDEX IF NOT EXISTS idx_research_replay_rounds ON research_replay_rounds (model_version, round);
ALTER TABLE research_replay_rounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "research_replay_rounds_all" ON research_replay_rounds;
CREATE POLICY "research_replay_rounds_all" ON research_replay_rounds
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

SELECT table_name FROM information_schema.tables WHERE table_name = 'research_replay_rounds';
