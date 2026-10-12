-- ══════════════════════════════════════════════════════════════
-- research_v9_pipeline.sql — 서버 연구 파이프라인 실행 기록 (research-engine.yml)
--
--  * 회차마다 서버(GitHub Actions)가 엔진·연구를 실행하고 단계별 성공·실패를 남긴다.
--  * 같은 (파이프라인 버전, 목표 회차)의 성공 기록은 1개만 → 중복 실행 방지
--  * 동시에 실행 중인 기록은 1개만 → 겹쳐 돌지 않음 (3시간 넘은 running 은 Worker 가 timeout 처리)
--  * 쓰기는 service_role(서버)만. anon/authenticated 는 SELECT 만 (관리자 화면이 같은 앱 키로 실행 상태를 본다).
--    저장 내용은 단계 이름·상태·짧은 오류 문구·결과 행 id 뿐이며 비밀키·원본 데이터는 넣지 않는다.
--  * 기존 테이블은 수정하지 않는다.
--
-- 적용: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run (다시 실행해도 안전)
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS research_pipeline_runs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pipeline_version  text    NOT NULL,
  latest_round      integer NOT NULL,      -- 실행 기준 최신 당첨 회차
  target_round      integer NOT NULL,      -- 예측 목표 회차 (latest + 1)
  status            text    NOT NULL,
  trigger           text,                  -- workflow_run / schedule / workflow_dispatch / push
  runner            text,                  -- github-actions run id
  attempt           integer NOT NULL DEFAULT 1,
  steps             jsonb   NOT NULL DEFAULT '[]'::jsonb,   -- [{name, ok, error, at}]
  outputs           jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 저장된 결과 행 id·모델 버전
  error             text,
  started_at        timestamptz NOT NULL DEFAULT now(),
  finished_at       timestamptz,
  CONSTRAINT chk_pipeline_status CHECK (status IN ('waiting', 'running', 'success', 'partial', 'failed'))
);

-- 목표 회차당 성공 1개
CREATE UNIQUE INDEX IF NOT EXISTS uq_pipeline_success
  ON research_pipeline_runs (pipeline_version, target_round) WHERE status = 'success';
-- 동시에 running 1개
CREATE UNIQUE INDEX IF NOT EXISTS uq_pipeline_running
  ON research_pipeline_runs (pipeline_version) WHERE status = 'running';
CREATE INDEX IF NOT EXISTS idx_pipeline_runs_target
  ON research_pipeline_runs (target_round DESC, started_at DESC);

ALTER TABLE research_pipeline_runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pipeline_runs_read" ON research_pipeline_runs;
CREATE POLICY "pipeline_runs_read" ON research_pipeline_runs
  FOR SELECT TO anon, authenticated USING (true);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON research_pipeline_runs FROM anon, authenticated;
GRANT SELECT ON research_pipeline_runs TO anon, authenticated;
GRANT ALL ON research_pipeline_runs TO service_role;

-- 확인용 (rowsecurity = true)
SELECT tablename, rowsecurity FROM pg_tables WHERE tablename = 'research_pipeline_runs';
