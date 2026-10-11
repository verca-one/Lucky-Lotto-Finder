-- ================================================================
-- research_v4_regions.sql — 전국 시·군·구 지역 연구 (신규·독립)
-- 작성: 2026-10-11. 기존 크롤링·엔진 테이블은 읽기 전용, 이 파일은 신규 테이블만 생성한다.
-- 생산자: research_region_worker.py (GitHub Actions 'Research Worker' 또는 수동 실행)
-- 소비자: Flutter 관리자 화면(지역 연구·지역 추천·현 위치 추천·경로 추천·연구 비서)
--
-- region_id 규칙 (행정구역 공식 코드 미확보 → 정규화된 이름 키):
--   광역시·특별시: '서울|노원구', '인천|강화군'   (구·군 단위)
--   도:           '경기|수원시', '충남|천안시'    (시·군 단위, 하위 구는 sub_units)
--   세종:         '세종|세종시'
--   시·도 상위:   '서울', '경기' (level='sido')
--   인터넷 판매:  'internet' (지역 연구에서 제외, 별도 집계)
-- ================================================================

-- 1. 지역 단위
CREATE TABLE IF NOT EXISTS research_region_units (
  region_id          text PRIMARY KEY,
  sido               text NOT NULL,
  unit_name          text NOT NULL,
  level              text NOT NULL CHECK (level IN ('sido','sigungu','internet')),
  parent_id          text,
  sub_units          jsonb NOT NULL DEFAULT '[]'::jsonb,   -- 시 하위 구/읍면동 이름 목록
  store_count        int   NOT NULL DEFAULT 0,             -- lottery_stores(lotto) 판매점 수
  geo_store_count    int   NOT NULL DEFAULT 0,             -- 좌표 확인된 판매점 수
  lat                double precision,                     -- 판매점 좌표 중심
  lng                double precision,
  neighbors          jsonb NOT NULL DEFAULT '[]'::jsonb,   -- 인접 생활권 [{region_id, km}] (중심 거리 기준)
  model_version      text  NOT NULL,
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rru_sido ON research_region_units (sido);

-- 2. 지역별 통계 스냅샷 (체크포인트 회차별, 덮어쓰지 않음)
CREATE TABLE IF NOT EXISTS research_region_stats (
  region_id            text NOT NULL,
  model_version        text NOT NULL,
  training_end_round   int  NOT NULL,      -- 이 회차까지의 데이터만 사용
  first_wins           int  NOT NULL DEFAULT 0,
  second_wins          int  NOT NULL DEFAULT 0,
  rounds_observed      int  NOT NULL DEFAULT 0,
  rounds_with_first    int  NOT NULL DEFAULT 0,
  win_round_rate       double precision,   -- 1등이 나온 회차 비율 (원시)
  baseline_rate        double precision,   -- 판매점 수 비례 무작위 기준 (판매량 미보정)
  shrunk_rate          double precision,   -- 계층적 축소추정 (전국→시도→지역)
  recent50_rate        double precision,
  trend_z              double precision,   -- 최근 100회 vs 이전 비율 차이 z
  last_first_round     int,
  dormant_rounds       int,                -- 마지막 1등 이후 경과 회차
  top_stores           jsonb NOT NULL DEFAULT '[]'::jsonb,  -- [{code,name,first,second}]
  concentration_hhi    double precision,   -- 지역 내 1등 판매점 집중도
  purchase_methods     jsonb NOT NULL DEFAULT '{}'::jsonb,  -- {자동,수동,반자동,미기재}
  difficulty           jsonb NOT NULL DEFAULT '{}'::jsonb,  -- 예측 난이도 (최신 회차 행에만)
  created_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (region_id, model_version, training_end_round)
);

-- 3. 지역·판매점 가설 (자동 발굴 + 순방향 검증)
CREATE TABLE IF NOT EXISTS research_region_hypotheses (
  hypothesis_id      text NOT NULL,
  model_version      text NOT NULL,
  kind               text NOT NULL,   -- transition_up | transition_down | self_repeat | chain | distance_band | store_cycle | emerging_store | dormant_rebound
  from_region        text,
  to_region          text,
  via_region         text,
  store_code         text,
  horizon            int,
  distance_km        int,
  discovered_round   int  NOT NULL,   -- 발견 체크포인트 (이 회차 이하 데이터만 사용)
  condition          jsonb NOT NULL DEFAULT '{}'::jsonb,
  train_n int, train_k int, train_rate double precision, train_base double precision,
  train_p double precision, train_q double precision,
  test_n  int, test_k  int, test_rate  double precision, test_base  double precision,
  test_p  double precision,
  status             text NOT NULL CHECK (status IN ('discovered','researching','passed','weakened','rejected','combined')),
  live_eligible      boolean NOT NULL DEFAULT false,  -- 실전 추천 반영 가능 (검증 통과 + 판매량 무관 유형)
  evidence           jsonb NOT NULL DEFAULT '{}'::jsonb,
  evaluated_round    int,             -- 순방향 검증에 사용한 마지막 회차
  updated_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (hypothesis_id, model_version)
);
CREATE INDEX IF NOT EXISTS idx_rrh_from ON research_region_hypotheses (from_region);
CREATE INDEX IF NOT EXISTS idx_rrh_to   ON research_region_hypotheses (to_region);
CREATE INDEX IF NOT EXISTS idx_rrh_store ON research_region_hypotheses (store_code);
CREATE INDEX IF NOT EXISTS idx_rrh_status ON research_region_hypotheses (status);

-- 4. 판매점 주기 연구 (최신 회차 기준 스냅샷)
CREATE TABLE IF NOT EXISTS research_store_cycles (
  store_code         text NOT NULL,
  model_version      text NOT NULL,
  training_end_round int  NOT NULL,
  store_name         text,
  region_id          text,
  lat double precision, lng double precision,
  first_count        int NOT NULL DEFAULT 0,
  second_count       int NOT NULL DEFAULT 0,
  first_rounds       jsonb NOT NULL DEFAULT '[]'::jsonb,
  gap_mean double precision, gap_median double precision, gap_var double precision, gap_cv double precision,
  rounds_since_last  int,
  recent100_first    int,
  prior_rate double precision, recent_rate double precision,
  emerging_p         double precision,   -- 최근 증가 포아송 단측 p
  class              text,               -- famous | emerging | regular | sparse
  purchase_methods   jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (store_code, model_version, training_end_round)
);
CREATE INDEX IF NOT EXISTS idx_rsc_region ON research_store_cycles (region_id);
CREATE INDEX IF NOT EXISTS idx_rsc_class ON research_store_cycles (class);

-- 5. 실행 기록 (체크포인트·중복 실행 방지·재시도)
CREATE TABLE IF NOT EXISTS research_region_runs (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_version      text NOT NULL,
  training_end_round int  NOT NULL,
  status             text NOT NULL CHECK (status IN ('running','completed','failed')),
  runner             text,               -- github-actions | local
  stats              jsonb NOT NULL DEFAULT '{}'::jsonb,
  error              text,
  started_at         timestamptz NOT NULL DEFAULT now(),
  completed_at       timestamptz,
  CONSTRAINT uq_rrr UNIQUE (model_version, training_end_round)
);

-- RLS: 다른 연구 테이블과 동일 (앱은 anon 키 사용, 관리자 인증 체계 없음 → DB 수준 관리자 전용 보호 불가)
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['research_region_units','research_region_stats','research_region_hypotheses','research_store_cycles','research_region_runs'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_all', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)', t || '_all', t);
  END LOOP;
END $$;

SELECT table_name FROM information_schema.tables
WHERE table_name IN ('research_region_units','research_region_stats','research_region_hypotheses','research_store_cycles','research_region_runs');
