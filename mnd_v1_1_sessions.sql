-- ================================================================
-- mnd_v1_1_sessions.sql
-- 명당 가설 연구소 연구 세션 진행 상태 테이블
-- 선행: mnd_v1_schema.sql 이미 적용됨
-- ================================================================

CREATE TABLE IF NOT EXISTS mnd_research_sessions (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_type    text        NOT NULL CHECK (session_type IN ('initial_historical', 'incremental')),
  status          text        NOT NULL DEFAULT 'running'
                    CHECK (status IN ('running', 'completed', 'failed')),
  model_version   text        NOT NULL DEFAULT '1.0',
  start_round     int,
  end_round       int,
  current_round   int,
  total_rounds    int,
  current_stage   text,
  error_message   text,
  started_at      timestamptz NOT NULL DEFAULT now(),
  completed_at    timestamptz
);

CREATE INDEX IF NOT EXISTS idx_mnd_sess_type_status
  ON mnd_research_sessions (session_type, model_version, status);

ALTER TABLE mnd_research_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mnd_sess_all" ON mnd_research_sessions;
CREATE POLICY "mnd_sess_all" ON mnd_research_sessions
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 확인 쿼리
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'mnd_research_sessions';
