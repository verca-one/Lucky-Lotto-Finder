-- ══════════════════════════════════════════════════════════════
-- research_v8_public.sql — 일반 사용자 공개 전용 테이블 (구매예측번호 3세트 + 공개 연구 1개)
--
-- 원칙
--  * 기존 연구 테이블(research_results 등)은 수정·삭제하지 않는다. 이 파일은 새 테이블 2개만 만든다.
--  * 쓰기는 GitHub Actions 서버 Worker(research_public_worker.py)가 service_role 키로만 한다.
--    service_role 은 RLS 를 우회하므로 별도 쓰기 정책을 두지 않는다.
--  * anon / authenticated 는 '공개 승인된 행'만 SELECT 가능. INSERT·UPDATE·DELETE 는 정책 없음 + 권한 회수로 이중 차단.
--  * 공개 행에는 요약만 저장한다 (모델 계수·내부 로그·전체 연구 데이터 없음).
--
-- 적용: Supabase 대시보드 → SQL Editor → 이 파일 전체 붙여넣기 → Run (1회, 다시 실행해도 안전)
-- ══════════════════════════════════════════════════════════════

-- 1. 구매예측번호 공개 (목표 회차당 1행)
CREATE TABLE IF NOT EXISTS research_public_purchase (
  target_round        integer PRIMARY KEY,
  training_end_round  integer NOT NULL,
  model_version       text    NOT NULL,
  source_research_id  uuid    NOT NULL,          -- research_results.id (원본 연구 결과)
  validation_status   text    NOT NULL,          -- '검증 통과' / '검증 실패'
  validation_summary  text    NOT NULL,          -- 일반 사용자용 2~4문장 요약
  sets                jsonb   NOT NULL DEFAULT '[]'::jsonb,  -- [{numbers:[6], sales_ratio}] 최대 3세트
  is_public_approved  boolean NOT NULL DEFAULT false,
  research_updated_at timestamptz,               -- 원본 연구 결과 생성 시각
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_public_purchase_sets CHECK (jsonb_typeof(sets) = 'array' AND jsonb_array_length(sets) <= 3)
);

-- 2. 공개 연구 (목표 회차당 활성 1개)
CREATE TABLE IF NOT EXISTS research_public_study (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_round        integer NOT NULL,
  source_research_id  uuid    NOT NULL,          -- research_results.id (원본 연구 결과)
  study_key           text    NOT NULL,          -- 원본 결과 안의 연구 과제 키 (empirical / volume / popularity)
  title               text    NOT NULL,
  purpose             text,
  method              text,
  progress            text,
  observation         text,
  status              text    NOT NULL,          -- 연구 중 / 검증 중 / 검증 완료 / 검증 실패
  applied_to_numbers  boolean NOT NULL DEFAULT false,
  limitation          text,
  research_updated_at timestamptz,
  is_public_approved  boolean NOT NULL DEFAULT false,
  is_active           boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_public_study_status CHECK (status IN ('연구 중', '검증 중', '검증 완료', '검증 실패')),
  CONSTRAINT uq_public_study_round_key UNIQUE (target_round, study_key)
);

-- 같은 목표 회차에 활성 공개 연구는 정확히 1개
CREATE UNIQUE INDEX IF NOT EXISTS uq_public_study_one_active
  ON research_public_study (target_round) WHERE is_active;

-- 3. RLS — 공개 승인된 행만 SELECT
ALTER TABLE research_public_purchase ENABLE ROW LEVEL SECURITY;
ALTER TABLE research_public_study    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_purchase_read" ON research_public_purchase;
CREATE POLICY "public_purchase_read" ON research_public_purchase
  FOR SELECT TO anon, authenticated USING (is_public_approved);

DROP POLICY IF EXISTS "public_study_read" ON research_public_study;
CREATE POLICY "public_study_read" ON research_public_study
  FOR SELECT TO anon, authenticated USING (is_public_approved AND is_active);

-- 4. 쓰기 권한 회수 (정책이 없어도 거부되지만 이중 차단)
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON research_public_purchase FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON research_public_study    FROM anon, authenticated;
GRANT SELECT ON research_public_purchase TO anon, authenticated;
GRANT SELECT ON research_public_study    TO anon, authenticated;
GRANT ALL ON research_public_purchase TO service_role;
GRANT ALL ON research_public_study    TO service_role;

-- 확인용 (실행 결과에 두 테이블 모두 rowsecurity = true 가 나와야 함)
SELECT tablename, rowsecurity FROM pg_tables
 WHERE tablename IN ('research_public_purchase', 'research_public_study');
