-- ================================================================
-- research_v6_replay.sql — 지방장 에이전트 '실전형 순차 재현' 계보 (신규·독립, 재실행 가능)
-- 작성: 2026-10-11. 기존 테이블(크롤링·ag-1.0 백테스트·1246회 실전 스냅샷)은 건드리지 않는다.
-- 생산자: research_agent_replay.py (GitHub Actions, service_role 키)
--
-- 한 회차 = 예측 동결(predictions·agent_predictions·pre 브리핑) → 결과 확인(results) →
--           사후 검증(agent_evals·central_evals·post 브리핑) → 연구 갱신(hypotheses·events)
-- replay_mode: 'sequential_replay' = 과거 회차를 당시 데이터만으로 사후 재현(계산 시각은 추첨 이후),
--              'live' = 추첨 전에 동결된 실제 예측.
-- 쓰기: service_role 만 (anon/authenticated 는 SELECT). 예측·검증·브리핑·이벤트는 UPDATE/DELETE 금지.
-- ================================================================

-- 1. 재현 실행 (계보)
CREATE TABLE IF NOT EXISTS research_replay_runs (
  replay_run_id         text PRIMARY KEY,
  model_version         text NOT NULL,
  replay_mode           text NOT NULL,
  status                text NOT NULL CHECK (status IN ('running','completed','failed')),
  start_round           int  NOT NULL,
  last_completed_round  int,                 -- 예측·검증·갱신까지 끝난 마지막 회차
  last_prediction_round int,                 -- 마지막으로 동결된 예측 목표 회차
  config                jsonb NOT NULL DEFAULT '{}'::jsonb,
  data_provenance       jsonb NOT NULL DEFAULT '{}'::jsonb,
  stats                 jsonb NOT NULL DEFAULT '{}'::jsonb,
  error                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

-- 2. 회차 예측 스냅샷 (중앙 엔진 지역 점수 + 통합 판매점 추천)
CREATE TABLE IF NOT EXISTS research_replay_predictions (
  prediction_snapshot_id       text PRIMARY KEY,
  replay_run_id                text NOT NULL,
  model_version                text NOT NULL,
  target_round                 int  NOT NULL,
  available_data_through_round int  NOT NULL,     -- 이 회차까지의 실제 결과만 사용
  replay_mode                  text NOT NULL CHECK (replay_mode IN ('sequential_replay','live')),
  prediction_created_at        timestamptz NOT NULL,
  regions                      jsonb NOT NULL DEFAULT '[]'::jsonb,  -- 전체 지역 [{region_id,p,base,ratio,factor,rank}]
  focus_regions                jsonb NOT NULL DEFAULT '[]'::jsonb,  -- 주목 지역 상위 10
  store_top                    jsonb NOT NULL DEFAULT '[]'::jsonb,  -- 전국 통합 추천 상위 20
  active_hypotheses            int NOT NULL DEFAULT 0,              -- 이 시점에 존재하던 가설 수
  live_hypotheses_applied      jsonb NOT NULL DEFAULT '[]'::jsonb,  -- 실전 반영된 검증 통과 가설 id
  explore_hypotheses_fired     int NOT NULL DEFAULT 0,
  snapshot_hash                text NOT NULL,
  data_provenance              jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT uq_rrp UNIQUE (replay_run_id, target_round)
);
CREATE INDEX IF NOT EXISTS idx_rrp_target ON research_replay_predictions (target_round);

-- 3. 지방장 납품 스냅샷 (지역별 상위 5곳)
CREATE TABLE IF NOT EXISTS research_replay_agent_predictions (
  prediction_snapshot_id       text NOT NULL,
  agent_id                     text NOT NULL,
  replay_run_id                text NOT NULL,
  model_version                text NOT NULL,
  target_round                 int  NOT NULL,
  available_data_through_round int  NOT NULL,
  region_id                    text NOT NULL,
  store_ids                    text[] NOT NULL DEFAULT '{}',   -- 순위순
  scores                       double precision[] NOT NULL DEFAULT '{}',  -- 회차당 1·2등 기대 빈도(판매량 미보정)
  p_first                      double precision[] NOT NULL DEFAULT '{}',
  live_factors                 double precision[] NOT NULL DEFAULT '{}',
  applied_hypothesis_ids       jsonb,                           -- 판매점별 실전 반영 가설 id (없으면 null)
  n_stores                     int NOT NULL DEFAULT 0,
  prediction_created_at        timestamptz NOT NULL,
  replay_mode                  text NOT NULL,
  PRIMARY KEY (prediction_snapshot_id, agent_id)
);
CREATE INDEX IF NOT EXISTS idx_rrap_agent ON research_replay_agent_predictions (agent_id, target_round);
CREATE INDEX IF NOT EXISTS idx_rrap_target ON research_replay_agent_predictions (target_round);

-- 4. 실제 결과 (예측과 분리)
CREATE TABLE IF NOT EXISTS research_replay_results (
  prediction_snapshot_id text PRIMARY KEY,
  replay_run_id          text NOT NULL,
  target_round           int  NOT NULL,
  result_verified_at     timestamptz NOT NULL,
  first_store_ids        text[] NOT NULL DEFAULT '{}',
  first_regions          text[] NOT NULL DEFAULT '{}',
  event_store_count      int NOT NULL DEFAULT 0,     -- 1·2등 판매점 수 (매칭 성공)
  unmatched_first        int NOT NULL DEFAULT 0,     -- 판매점 목록에 없는 코드
  unmatched_second       int NOT NULL DEFAULT 0,
  data_provenance        jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_rrr_target ON research_replay_results (target_round);

-- 5. 지방장별 사후 검증
CREATE TABLE IF NOT EXISTS research_replay_agent_evals (
  prediction_snapshot_id text NOT NULL,
  agent_id               text NOT NULL,
  replay_run_id          text NOT NULL,
  target_round           int  NOT NULL,
  result_verified_at     timestamptz NOT NULL,
  hits_any               int NOT NULL DEFAULT 0,
  hits_first             int NOT NULL DEFAULT 0,
  expected_uniform       double precision,
  evaluation_metrics     jsonb NOT NULL DEFAULT '{}'::jsonb,  -- 순위별 적중, 이력 기준, 탐색, 확률 점수(log-loss) 등
  PRIMARY KEY (prediction_snapshot_id, agent_id)
);
CREATE INDEX IF NOT EXISTS idx_rrae_agent ON research_replay_agent_evals (agent_id, target_round);

-- 6. 중앙 엔진 사후 검증
CREATE TABLE IF NOT EXISTS research_replay_central_evals (
  prediction_snapshot_id text PRIMARY KEY,
  replay_run_id          text NOT NULL,
  target_round           int  NOT NULL,
  result_verified_at     timestamptz NOT NULL,
  evaluation_metrics     jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_rrce_target ON research_replay_central_evals (target_round);

-- 7. 가설 (현재 상태 + 실전 적용 이력 요약)
CREATE TABLE IF NOT EXISTS research_replay_hypotheses (
  replay_run_id              text NOT NULL,
  hypothesis_id              text NOT NULL,
  model_version              text NOT NULL,
  agent_id                   text NOT NULL,
  kind                       text NOT NULL,
  scope                      text NOT NULL,
  canonical_key              text NOT NULL,
  direction                  text NOT NULL,
  predictive                 boolean NOT NULL,
  source_region text, target_region text, source_store text, target_store text,
  related_regions            text[] NOT NULL DEFAULT '{}',
  related_stores             text[] NOT NULL DEFAULT '{}',
  lag                        int,
  params                     jsonb NOT NULL DEFAULT '{}'::jsonb,
  shared_from                text,
  shared_by_agent            text,
  shared_to_count            int NOT NULL DEFAULT 0,
  first_discovered_round     int NOT NULL,         -- 발견 시점 (이 회차 이하 데이터)
  discovery_significant      boolean NOT NULL DEFAULT false,
  first_applied_live_round   int,                  -- 처음 실전 추천에 반영된 목표 회차
  first_applied_explore_round int,                 -- 처음 탐색 목록에 반영된 목표 회차
  applied_live_count         int NOT NULL DEFAULT 0,
  applied_explore_count      int NOT NULL DEFAULT 0,
  train_n int, train_k int, train_expected double precision, train_p double precision, train_q double precision,
  test_n int, test_k int, test_expected double precision, k_off int, e_off double precision,
  relative_ratio double precision, test_p double precision, test_q double precision,
  status                     text NOT NULL,
  evaluated_round            int,
  summary                    text,
  evidence                   jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at                 timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (replay_run_id, hypothesis_id)
);
CREATE INDEX IF NOT EXISTS idx_rrh2_agent  ON research_replay_hypotheses (agent_id);
CREATE INDEX IF NOT EXISTS idx_rrh2_status ON research_replay_hypotheses (status);
CREATE INDEX IF NOT EXISTS idx_rrh2_kind   ON research_replay_hypotheses (kind);
CREATE INDEX IF NOT EXISTS idx_rrh2_stores ON research_replay_hypotheses USING gin (related_stores);
CREATE INDEX IF NOT EXISTS idx_rrh2_regions ON research_replay_hypotheses USING gin (related_regions);

-- 8. 가설 상태 변화 이력
CREATE TABLE IF NOT EXISTS research_replay_hypothesis_events (
  replay_run_id  text NOT NULL,
  hypothesis_id  text NOT NULL,
  round          int  NOT NULL,          -- 이 회차 결과까지 반영한 시점
  status_from    text,
  status_to      text NOT NULL,
  test_n int, test_k int, test_expected double precision, test_p double precision, relative_ratio double precision,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (replay_run_id, hypothesis_id, round)
);
CREATE INDEX IF NOT EXISTS idx_rrhe_round ON research_replay_hypothesis_events (round);

-- 9. 비서 브리핑 (사전·사후 분리)
CREATE TABLE IF NOT EXISTS research_replay_briefings (
  prediction_snapshot_id text NOT NULL,
  kind                   text NOT NULL CHECK (kind IN ('pre','post')),
  replay_run_id          text NOT NULL,
  target_round           int  NOT NULL,
  payload                jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at             timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (prediction_snapshot_id, kind)
);
CREATE INDEX IF NOT EXISTS idx_rrb_target ON research_replay_briefings (target_round);

-- 10. 단계 원장 (재개·중복 방지)
CREATE TABLE IF NOT EXISTS research_replay_checkpoints (
  replay_run_id  text NOT NULL,
  target_round   int  NOT NULL,
  stage          text NOT NULL CHECK (stage IN ('predicted','verified','updated')),
  status         text NOT NULL CHECK (status IN ('done','failed')),
  attempts       int  NOT NULL DEFAULT 1,
  error          text,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (replay_run_id, target_round, stage)
);

-- ── 불변 보호 ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION research_replay_block_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% 은(는) 불변 기록입니다 (UPDATE/DELETE 금지)', TG_TABLE_NAME;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['research_replay_predictions','research_replay_agent_predictions','research_replay_results',
                           'research_replay_agent_evals','research_replay_central_evals','research_replay_hypothesis_events',
                           'research_replay_briefings'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_immutable', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION research_replay_block_mutation()',
                   t || '_immutable', t);
  END LOOP;
END $$;

-- ── RLS: 읽기 공개, 쓰기 service_role 만 ─────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['research_replay_runs','research_replay_predictions','research_replay_agent_predictions',
                           'research_replay_results','research_replay_agent_evals','research_replay_central_evals',
                           'research_replay_hypotheses','research_replay_hypothesis_events','research_replay_briefings',
                           'research_replay_checkpoints'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO anon, authenticated USING (true)', t || '_read', t);
  END LOOP;
END $$;

-- ── DB 사용량 측정 (Worker 가 무료 한도 대비 기록, service_role 만 실행) ──
CREATE OR REPLACE FUNCTION research_db_usage() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'database_bytes', pg_database_size(current_database()),
    'tables', (SELECT jsonb_object_agg(c.relname, pg_total_relation_size(c.oid))
               FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relkind = 'r'));
$$;
REVOKE ALL ON FUNCTION research_db_usage() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION research_db_usage() TO service_role;

SELECT table_name FROM information_schema.tables
WHERE table_name LIKE 'research_replay%' ORDER BY table_name;
