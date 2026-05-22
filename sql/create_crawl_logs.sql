-- 크롤링 실행 로그 테이블
CREATE TABLE IF NOT EXISTS crawl_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  lottery_type TEXT NOT NULL,          -- 'lotto', 'pension', 'speeto'
  status TEXT NOT NULL DEFAULT 'running', -- 'running', 'success', 'failure'
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  duration_seconds INTEGER,
  rounds_processed TEXT,               -- 처리된 회차 (예: "1234", "latest")
  error_message TEXT,
  workflow_run_id TEXT,                 -- GitHub Actions run ID
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_crawl_logs_type ON crawl_logs(lottery_type);
CREATE INDEX IF NOT EXISTS idx_crawl_logs_started ON crawl_logs(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_crawl_logs_status ON crawl_logs(status);

-- RLS 정책 (anon 읽기 허용)
ALTER TABLE crawl_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon read crawl_logs"
  ON crawl_logs FOR SELECT
  TO anon
  USING (true);

CREATE POLICY "Allow anon insert crawl_logs"
  ON crawl_logs FOR INSERT
  TO anon
  WITH CHECK (true);

CREATE POLICY "Allow anon update crawl_logs"
  ON crawl_logs FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);
