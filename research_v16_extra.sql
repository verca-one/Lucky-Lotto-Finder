-- ══════════════════════════════════════════════════════════════
-- research_v16_extra.sql — 연금복권 · 스피또 공개 요약 테이블 (일반 모드 추천 '연금' · '스피또' 탭)
--
--  * 새 테이블 1개만 만든다. 기존 테이블(크롤링 · 연구)은 건드리지 않는다.
--  * 쓰기는 GitHub Actions 서버 Worker(research_pension.py 등)가 service_role 키로만 한다.
--  * anon / authenticated 는 공개 승인된 행만 SELECT. INSERT·UPDATE·DELETE 는 권한 회수.
--  * 공개 행에는 요약만 저장한다 (추천 번호 · 명당 이름/지역 · 가설 문장 · 안내문).
--
-- 적용: Supabase 대시보드 → SQL Editor → 이 파일 전체 붙여넣기 → Run (다시 실행해도 안전)
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS research_public_extra (
  lottery             text        NOT NULL,          -- pension | speetto
  target_round        integer     NOT NULL,
  payload             jsonb       NOT NULL DEFAULT '{}'::jsonb,
  is_public_approved  boolean     NOT NULL DEFAULT false,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (lottery, target_round),
  CONSTRAINT chk_public_extra_lottery CHECK (lottery IN ('pension', 'speetto'))
);

ALTER TABLE research_public_extra ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_extra_read" ON research_public_extra;
CREATE POLICY "public_extra_read" ON research_public_extra
  FOR SELECT TO anon, authenticated USING (is_public_approved);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON research_public_extra FROM anon, authenticated;
GRANT SELECT ON research_public_extra TO anon, authenticated;

-- 확인
SELECT 'research_public_extra' AS check,
       (SELECT count(*) FROM information_schema.tables WHERE table_name = 'research_public_extra')::text AS value;
