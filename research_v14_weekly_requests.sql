-- ================================================================
-- research_v14_weekly_requests.sql — 앱 [토요일 최종본 지금 반영] 요청
-- 평소 토요일 최종 점검은 토 08:00 KST 에 자동 실행된다 (research-weekly.yml).
-- 관리자가 앱에서 변경점 미리보기를 확인하고 [지금 반영]을 누르면 이 테이블에 요청 1행이 생기고,
-- 서버(research_request_poll.py, 10분마다)가 Research Weekly Check 를 바로 실행시킨다.
-- 앱(anon)은 '현재 목표 회차'에 대한 새 요청만 넣을 수 있다 (회차당 1번, 수정·삭제 불가).
-- 크롤링 테이블은 lotto_winning_numbers 를 정책 조건에서 읽기만 한다.
-- ================================================================
CREATE TABLE IF NOT EXISTS research_weekly_requests (
  target_round  integer     PRIMARY KEY,
  requested_at  timestamptz NOT NULL DEFAULT now(),
  source        text        NOT NULL DEFAULT 'app_manual',
  status        text        NOT NULL DEFAULT 'pending',   -- pending | dispatched | done
  dispatched_at timestamptz,
  done_at       timestamptz
);

ALTER TABLE research_weekly_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "weekly_requests_read" ON research_weekly_requests;
CREATE POLICY "weekly_requests_read" ON research_weekly_requests
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "weekly_requests_insert" ON research_weekly_requests;
CREATE POLICY "weekly_requests_insert" ON research_weekly_requests
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    status = 'pending' AND source = 'app_manual' AND dispatched_at IS NULL AND done_at IS NULL
    AND target_round = (SELECT max(round) + 1 FROM lotto_winning_numbers)
  );

REVOKE UPDATE, DELETE, TRUNCATE ON research_weekly_requests FROM anon, authenticated;
GRANT SELECT, INSERT ON research_weekly_requests TO anon, authenticated;
GRANT ALL ON research_weekly_requests TO service_role;

-- 확인
SELECT 'weekly_requests_table' AS check, (to_regclass('public.research_weekly_requests') IS NOT NULL)::text AS value
UNION ALL
SELECT 'policies', count(*)::text FROM pg_policies WHERE tablename = 'research_weekly_requests';
