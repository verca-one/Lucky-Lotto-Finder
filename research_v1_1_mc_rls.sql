-- ================================================================
-- research_v1_1_mc_rls.sql — Monte Carlo 테이블 RLS 정책 (멱등)
-- rpa_mc_jobs / rpa_mc_baseline 은 supabase_migration_mc_system.sql 에서 생성됐으나
-- RLS 정책이 없어 앱(anon)이 insert/update 하지 못할 수 있음 → 다른 rpa_* 테이블과 동일 정책 부여
-- ================================================================
ALTER TABLE rpa_mc_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rpa_mc_jobs_all" ON rpa_mc_jobs;
CREATE POLICY "rpa_mc_jobs_all" ON rpa_mc_jobs
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

ALTER TABLE rpa_mc_baseline ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rpa_mc_baseline_all" ON rpa_mc_baseline;
CREATE POLICY "rpa_mc_baseline_all" ON rpa_mc_baseline
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

SELECT tablename, policyname FROM pg_policies WHERE tablename IN ('rpa_mc_jobs', 'rpa_mc_baseline');
