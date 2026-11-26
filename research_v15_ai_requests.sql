-- ================================================================
-- research_v15_ai_requests.sql — 앱 연구소 [AI 부서 새로고침] 요청
-- 관리자가 연구소 › AI 부서에서 새로고침을 누르면 이 테이블에 요청 1행이 생기고,
-- 서버(research_request_poll.py, 10분마다)가 research-strategy.yml(7183 · 브리핑전담부서 · 전략기획부 · 연금 · 스피또)을 바로 실행시킨다.
-- 진행 상태(pending → dispatched → done)를 여기에 남겨, 앱을 닫았다 열어도 어디까지 왔는지 보인다.
-- 앱(anon)은 새 요청만 넣을 수 있고(수정·삭제 불가), 진행 중인 요청이 있거나 20분 안에 요청했으면 막힌다.
-- 크롤링 테이블은 건드리지 않는다.
-- ================================================================
CREATE TABLE IF NOT EXISTS research_ai_requests (
  id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  requested_at  timestamptz NOT NULL DEFAULT now(),
  source        text        NOT NULL DEFAULT 'app_manual',
  status        text        NOT NULL DEFAULT 'pending',   -- pending | dispatched | done
  dispatched_at timestamptz,
  done_at       timestamptz,
  conclusion    text,                                     -- success | failure | cancelled | timeout | dispatch_failed
  run_url       text,
  run_started_at timestamptz,                             -- GitHub 실행이 실제로 시작 · 끝난 시각 (실행 시간 표시)
  run_ended_at   timestamptz
);
-- 이미 표를 만든 뒤라면 칸만 추가
ALTER TABLE research_ai_requests ADD COLUMN IF NOT EXISTS run_started_at timestamptz;
ALTER TABLE research_ai_requests ADD COLUMN IF NOT EXISTS run_ended_at timestamptz;
-- 단계별 [재시도] — 어느 몫을 다시 돌릴지 (a7183 | review | direction | pension | speetto). 비어 있으면 '이번 주 실패 · 빠진 것 모두'
ALTER TABLE research_ai_requests ADD COLUMN IF NOT EXISTS parts text;

ALTER TABLE research_ai_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_requests_read" ON research_ai_requests;
CREATE POLICY "ai_requests_read" ON research_ai_requests
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "ai_requests_insert" ON research_ai_requests;
CREATE POLICY "ai_requests_insert" ON research_ai_requests
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    status = 'pending' AND source = 'app_manual'
    AND dispatched_at IS NULL AND done_at IS NULL AND conclusion IS NULL AND run_url IS NULL
    AND run_started_at IS NULL AND run_ended_at IS NULL
    AND (parts IS NULL OR parts ~ '^(a7183|review|direction|pension|speetto)$')
    -- 같은 몫의 요청이 진행 중이거나 10분 안에 있었으면 막는다 (다른 몫은 이어서 누를 수 있음)
    AND NOT EXISTS (
      SELECT 1 FROM research_ai_requests r
      WHERE r.parts IS NOT DISTINCT FROM research_ai_requests.parts
        AND (r.status <> 'done' OR r.requested_at > now() - interval '10 minutes')
    )
  );

REVOKE UPDATE, DELETE, TRUNCATE ON research_ai_requests FROM anon, authenticated;
GRANT SELECT, INSERT ON research_ai_requests TO anon, authenticated;
GRANT ALL ON research_ai_requests TO service_role;

-- 확인
SELECT 'ai_requests_table' AS check, (to_regclass('public.research_ai_requests') IS NOT NULL)::text AS value
UNION ALL
SELECT 'policies', count(*)::text FROM pg_policies WHERE tablename = 'research_ai_requests';
