-- ══════════════════════════════════════════════════════════════
-- research_v10_review.sql — 엔진 복기 연구소 (중앙 엔진 · 전국 지방장 회차별 복기, 보정 이력, 비서 복기 브리핑)
--
-- 기존 테이블은 수정하지 않는다. 사전 예측 원본(research_replay_*, research_agent_*, research_results 등)은 그대로 두고
-- 복기 결과만 별도 버전(review_version)으로 저장한다.
--
--  research_review_agent_rounds  회차 1행 = 지방장 전원(배열) 복기. 한 번 쓰면 수정·삭제 불가 (용량 절감: 회차당 1행)
--  research_review_agent_cards   지방장별 누적 성적표 (최근 10·30·100회·전체) — 매 회차 갱신
--  research_review_rounds        회차별 중앙 엔진 복기 + 비서 복기 브리핑 — 확정(final) 후에는 갱신하지 않음
--  research_review_runs          복기 실행 기록 (과거 순차 복기·실전 회차)
--
-- 쓰기: GitHub Actions 서버 Worker(service_role)만. anon/authenticated 는 SELECT 만 (관리자 화면 조회용).
-- 적용: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run (다시 실행해도 안전)
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS research_review_agent_rounds (
  review_version          text    NOT NULL,
  target_round            integer NOT NULL,
  prediction_snapshot_id  text    NOT NULL,      -- 원본 사전 예측 (research_replay_predictions)
  prediction_mode         text,                  -- live(추첨 전 실전 동결) / sequential_replay(과거 순차 재현)
  data_through_round      integer NOT NULL,      -- 예측에 쓴 데이터 마지막 회차 (= target - 1)
  round_valid             boolean NOT NULL DEFAULT true,
  agent_ids               text[]  NOT NULL,      -- entries 순서
  entries                 jsonb   NOT NULL,      -- 지방장별 복기 (agent_ids 와 같은 순서)
  spatial                 jsonb   NOT NULL DEFAULT '{}'::jsonb,  -- 가설 종류별 발화·적중·기대 (공간전이·동시 당첨·주기)
  summary                 jsonb   NOT NULL DEFAULT '{}'::jsonb,
  integrity               jsonb   NOT NULL DEFAULT '{}'::jsonb,  -- 재계산 목록 = 동결 목록 여부 등
  created_at              timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (review_version, target_round)
);

CREATE TABLE IF NOT EXISTS research_review_agent_cards (
  review_version  text    NOT NULL,
  agent_id        text    NOT NULL,
  agent_index     integer NOT NULL,
  sido            text,
  unit_name       text,
  through_round   integer NOT NULL,
  n_stores        integer,
  cards           jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- {"10","30","100","all": 성적}
  hypotheses      jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 판정별 가설 수
  corrections     jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 누적 보정 (적용·미적용)
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (review_version, agent_id)
);

CREATE TABLE IF NOT EXISTS research_review_rounds (
  review_version  text    NOT NULL,
  target_round    integer NOT NULL,
  status          text    NOT NULL,          -- final / partial(일부 입력 미확보)
  prediction_mode text,
  numbers         jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 번호: 공식 5세트·구매예측 5세트·공개 3세트·번호 엔진·무작위 대조군
  regions         jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 추천 지역 TOP vs 실제 1등 지역
  stores          jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 추천 판매점 TOP vs 실제 1등 판매점
  agents          jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 지방장 복기 요약
  spatial         jsonb   NOT NULL DEFAULT '{}'::jsonb,
  corrections     jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 이번 회차 보정 (가설 판정 변화·적용 여부·전후 배수)
  signals         jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 적용 신호 vs 연구용 신호
  briefing        jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- 비서 복기 브리핑 (저장 수치로 생성)
  data_status     jsonb   NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_review_status CHECK (status IN ('final', 'partial')),
  PRIMARY KEY (review_version, target_round)
);

CREATE TABLE IF NOT EXISTS research_review_runs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_version  text NOT NULL,
  kind            text NOT NULL,             -- backfill / live / central
  status          text NOT NULL,             -- running / success / partial / failed
  from_round      integer,
  to_round        integer,
  stats           jsonb NOT NULL DEFAULT '{}'::jsonb,
  error           text,
  runner          text,
  started_at      timestamptz NOT NULL DEFAULT now(),
  finished_at     timestamptz
);
CREATE INDEX IF NOT EXISTS idx_review_runs_started ON research_review_runs (started_at DESC);

-- 지방장 회차 복기는 불변 (한 번 쓰면 수정·삭제 불가)
CREATE OR REPLACE FUNCTION research_review_block_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '복기 원본 기록은 수정·삭제할 수 없습니다 (%)', TG_TABLE_NAME;
END $$;
DROP TRIGGER IF EXISTS trg_review_agent_rounds_immutable ON research_review_agent_rounds;
CREATE TRIGGER trg_review_agent_rounds_immutable BEFORE UPDATE OR DELETE ON research_review_agent_rounds
  FOR EACH ROW EXECUTE FUNCTION research_review_block_mutation();

-- RLS: 읽기만 공개(관리자 화면), 쓰기는 service_role
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['research_review_agent_rounds','research_review_agent_cards','research_review_rounds','research_review_runs'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO anon, authenticated USING (true)', t || '_read', t);
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON %I FROM anon, authenticated', t);
    EXECUTE format('GRANT SELECT ON %I TO anon, authenticated', t);
    EXECUTE format('GRANT ALL ON %I TO service_role', t);
  END LOOP;
END $$;

-- 확인용 (4개 모두 rowsecurity = true)
SELECT tablename, rowsecurity FROM pg_tables WHERE tablename LIKE 'research_review_%' ORDER BY tablename;
