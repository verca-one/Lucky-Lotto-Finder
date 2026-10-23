-- ══════════════════════════════════════════════════════════════
-- research_v17_speetto_status.sql — 스피또 판매 현황 (게임·차수별 출고율 · 남은 1·2·3등 매수) 날짜별 기록
--
--  * 새 테이블 1개만 만든다. 기존 테이블(크롤링 · 연구)은 건드리지 않는다.
--  * 쓰기는 GitHub Actions 수집기(speetto_status_collector.py)가 service_role 키로만 한다.
--  * 동행복권이 공개하는 판매 현황이라 anon / authenticated 는 읽기만 (쓰기 권한 회수).
--
-- 적용: Supabase 대시보드 → SQL Editor → 이 파일 전체 붙여넣기 → Run (다시 실행해도 안전)
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS research_speetto_status (
  snap_date     date        NOT NULL,             -- 수집한 날 (KST)
  game          text        NOT NULL,             -- SP500 | SP1000 | SP2000
  edition       integer     NOT NULL,             -- 차수 (stEpsd)
  price         integer,                          -- 한 장 가격
  sale_start    timestamptz,
  sale_end      timestamptz,
  ship_rate     numeric,                          -- 출고율 % (stSpmtRt)
  rnk1_total    integer, rnk1_left integer,       -- 1등 전체 · 남은 매수
  rnk2_total    integer, rnk2_left integer,
  rnk3_total    integer, rnk3_left integer,
  prize1        text, prize2 text, prize3 text,   -- 등위별 당첨금 표기 (예: 5억원)
  odds          text,                             -- 전체 당첨 확률 표기 (stSumWnPbltNm)
  site_changed  text,                             -- 동행복권 자료 갱신일 (dataChgDt)
  raw           jsonb       NOT NULL DEFAULT '{}'::jsonb,
  collected_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (snap_date, game, edition)
);

ALTER TABLE research_speetto_status ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "speetto_status_read" ON research_speetto_status;
CREATE POLICY "speetto_status_read" ON research_speetto_status
  FOR SELECT TO anon, authenticated USING (true);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON research_speetto_status FROM anon, authenticated;
GRANT SELECT ON research_speetto_status TO anon, authenticated;

-- 확인
SELECT 'research_speetto_status' AS check,
       (SELECT count(*) FROM information_schema.tables WHERE table_name = 'research_speetto_status')::text AS value;
