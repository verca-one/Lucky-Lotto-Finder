-- ================================================================
-- research_v14_strategy.sql — AI 전략기획부 (방향 제시) · 가설 공장 (비서 검증·유지·폐기)
--   strategy_directions : 연구 방향 — AI(전략기획부) 또는 관리자(수동)가 제시. AI 가 쓸 수 있는 곳은 여기뿐
--   strategy_hypotheses : 방향에서 만든 가설 — 비서(서버)가 저장된 데이터로 검증 → 통과/기각 → 유지/폐기
--   strategy_runs       : 전략기획부 · 가설 공장 실행 기록
-- 앱(anon)은 읽기만, 쓰기는 서버(service_role)만. 크롤링 테이블은 건드리지 않는다.
-- ================================================================
CREATE TABLE IF NOT EXISTS strategy_directions (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  after_round  integer     NOT NULL,                 -- 이 회차 검증 결과를 보고 낸 방향
  source       text        NOT NULL DEFAULT 'ai',    -- ai | manual
  model        text,                                 -- AI 모델 (수동이면 null)
  title        text        NOT NULL,
  rationale    text        NOT NULL DEFAULT '',
  focus        text,                                 -- popularity | calendar | sales | numbers | stores
  status       text        NOT NULL DEFAULT 'active',-- active | closed
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_strategy_directions_round ON strategy_directions (after_round DESC);

CREATE TABLE IF NOT EXISTS strategy_hypotheses (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  direction_id  uuid        REFERENCES strategy_directions(id),
  code          text        NOT NULL UNIQUE,         -- 조건·결과·방향 조합 (같은 가설 중복 방지)
  statement     text        NOT NULL,                -- 가설 문장
  spec          jsonb       NOT NULL,                -- {condition, outcome, expect}
  status        text        NOT NULL DEFAULT 'proposed', -- proposed | rejected | validated | maintained | discarded | unsupported
  discovery     jsonb,                               -- 발견 구간 검정
  confirm       jsonb,                               -- 확인 구간 검정
  forward       jsonb,                               -- 통과 이후 새 회차 추적
  verdict       text,                                -- 비서 판정 설명
  created_round integer     NOT NULL,
  last_round    integer,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_strategy_hypotheses_direction ON strategy_hypotheses (direction_id);

CREATE TABLE IF NOT EXISTS strategy_runs (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  kind        text        NOT NULL,                  -- ai_direction | factory
  status      text        NOT NULL,                  -- success | skipped | failed
  after_round integer,
  stats       jsonb       NOT NULL DEFAULT '{}'::jsonb,
  note        text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_strategy_runs_created ON strategy_runs (created_at DESC);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['strategy_directions', 'strategy_hypotheses', 'strategy_runs'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS "%s_read" ON %I', t, t);
    EXECUTE format('CREATE POLICY "%s_read" ON %I FOR SELECT TO anon, authenticated USING (true)', t, t);
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON %I FROM anon, authenticated', t);
    EXECUTE format('GRANT SELECT ON %I TO anon, authenticated', t);
    EXECUTE format('GRANT ALL ON %I TO service_role', t);
  END LOOP;
END $$;

-- 확인
SELECT 'strategy_tables' AS check, count(*)::text AS value
  FROM information_schema.tables WHERE table_name IN ('strategy_directions', 'strategy_hypotheses', 'strategy_runs')
UNION ALL
SELECT 'policies', count(*)::text FROM pg_policies
 WHERE tablename IN ('strategy_directions', 'strategy_hypotheses', 'strategy_runs');
