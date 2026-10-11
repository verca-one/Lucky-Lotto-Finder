-- ================================================================
-- research_v5_agents.sql — 전국 지방장 에이전트 v1.0 (신규·독립, 재실행 가능)
-- 작성: 2026-10-11. 기존 크롤링·엔진·연구 테이블은 읽기 전용, 이 파일은 신규 테이블만 만든다.
-- 생산자: research_agent_worker.py (GitHub Actions 'Research Worker', service_role 키)
-- 소비자: Flutter 관리자 화면 (엔진추천명당 지역/내 주변/경로, 지방장 연구소, 연구 비서 브리핑)
--
-- 지방장(agent_id) = research_region_units 의 시·군·구 region_id ('서울|노원구', '경기|수원시', '제주|서귀포시')
--   + 'internet'(인터넷 판매). 행정구역 공식 코드는 DB 에 없어 정규화 이름 키를 쓴다.
-- 쓰기 권한: anon/authenticated 는 SELECT 만. INSERT/UPDATE/DELETE 정책 없음 → service_role(Worker)만 기록.
-- 불변 스냅샷: 납품·중앙 결과·평가·가설 이벤트 테이블은 UPDATE/DELETE 를 트리거로 차단한다.
-- ================================================================

-- 1. 지방장 등록 및 연구 상태
CREATE TABLE IF NOT EXISTS research_agents (
  agent_id              text NOT NULL,
  model_version         text NOT NULL,
  level                 text NOT NULL,          -- sigungu | internet
  sido                  text NOT NULL,
  unit_name             text NOT NULL,
  sub_units             jsonb NOT NULL DEFAULT '[]'::jsonb,  -- 하위 구·읍·면·동 연구 [{name, stores, events, first}]
  store_count           int  NOT NULL DEFAULT 0,
  active_store_count    int  NOT NULL DEFAULT 0,             -- 최근 200회 1·2등 기록 판매점
  geo_store_count       int  NOT NULL DEFAULT 0,
  duplicate_groups      int  NOT NULL DEFAULT 0,             -- 이름·주소 동일 다중 코드 묶음 수
  status                text NOT NULL DEFAULT 'idle' CHECK (status IN ('idle','running','completed','failed')),
  last_processed_round  int,                                 -- 실제 결과로 평가까지 끝난 마지막 회차
  last_target_round     int,                                 -- 마지막 납품 목표 회차
  hypothesis_counts     jsonb NOT NULL DEFAULT '{}'::jsonb,  -- {discovered, researching, passed, ...}
  delivery_count        int  NOT NULL DEFAULT 0,             -- 누적 납품 건수 (backtest + live)
  performance           jsonb NOT NULL DEFAULT '{}'::jsonb,  -- 순차 검증 성능 요약
  error                 text,
  last_run_at           timestamptz,
  updated_at            timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (agent_id, model_version)
);
CREATE INDEX IF NOT EXISTS idx_ra_sido ON research_agents (sido);

-- 2. 공유 가설 저장소 (발견 지방장·관련 지역/판매점·시차·과거/미래 검증·상태)
CREATE TABLE IF NOT EXISTS research_agent_hypotheses (
  hypothesis_id      text NOT NULL,
  model_version      text NOT NULL,
  agent_id           text NOT NULL,            -- 발견(소유) 지방장
  kind               text NOT NULL,            -- store_lead | store_cowin | region_store_lead | region_lead | region_cowin
                                               -- | self_repeat | store_cycle | cycle_pooled | neighbor_spill
                                               -- | region_trend_up | region_trend_down | region_dormant | composite | multi_condition
  scope              text NOT NULL,            -- store_pair | region_store | region_pair | store | agent_pooled | region | composite | national
  canonical_key      text NOT NULL,            -- 중복 제거 키
  direction          text NOT NULL DEFAULT 'up' CHECK (direction IN ('up','down')),
  predictive         boolean NOT NULL DEFAULT true,   -- false = 동시 당첨(같은 회차) 연관, 다음 회차 예측 불가
  source_region      text,
  target_region      text,
  source_store       text,
  target_store       text,
  related_regions    text[] NOT NULL DEFAULT '{}',
  related_stores     text[] NOT NULL DEFAULT '{}',
  lag                int,
  params             jsonb NOT NULL DEFAULT '{}'::jsonb,
  shared_from        text,                     -- 다른 지방장에게서 공유받은 경우 원 가설 id
  shared_by_agent    text,
  shared_to_count    int NOT NULL DEFAULT 0,   -- 이 가설(템플릿)을 공유받은 지방장 수
  discovered_round   int NOT NULL,             -- 발견 체크포인트 (이 회차 이하 데이터만 사용)
  discovery_significant boolean NOT NULL DEFAULT false,  -- BH-FDR q<0.10 (false = 탐색적 상위 후보)
  train_n int, train_k int, train_expected double precision, train_p double precision, train_q double precision,
  test_n  int, test_k  int, test_expected  double precision, test_p  double precision, test_q double precision,
  status             text NOT NULL CHECK (status IN ('discovered','researching','passed','weakened','rejected','combined')),
  live_eligible      boolean NOT NULL DEFAULT false,
  rec_state          text NOT NULL DEFAULT 'exploratory' CHECK (rec_state IN ('live','exploratory','none')),
  evidence           jsonb NOT NULL DEFAULT '{}'::jsonb,
  evaluated_round    int,
  updated_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (hypothesis_id, model_version)
);
CREATE INDEX IF NOT EXISTS idx_rah_agent  ON research_agent_hypotheses (agent_id);
CREATE INDEX IF NOT EXISTS idx_rah_status ON research_agent_hypotheses (status);
CREATE INDEX IF NOT EXISTS idx_rah_kind   ON research_agent_hypotheses (kind);
CREATE INDEX IF NOT EXISTS idx_rah_stores ON research_agent_hypotheses USING gin (related_stores);
CREATE INDEX IF NOT EXISTS idx_rah_regions ON research_agent_hypotheses USING gin (related_regions);

-- 3. 가설 상태 변화 이력 (불변)
CREATE TABLE IF NOT EXISTS research_agent_hypothesis_events (
  hypothesis_id  text NOT NULL,
  model_version  text NOT NULL,
  round          int  NOT NULL,       -- 이 회차 결과까지 반영한 시점
  status_from    text,
  status_to      text NOT NULL,
  test_n int, test_k int, test_expected double precision, test_p double precision,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (hypothesis_id, model_version, round)
);

-- 4. 지역·판매점 관계 그래프 (체크포인트별 상위 관계, 유의성 무관 기록)
CREATE TABLE IF NOT EXISTS research_agent_relations (
  model_version      text NOT NULL,
  training_end_round int  NOT NULL,
  kind               text NOT NULL,      -- store_cowin | store_lead | region_cowin | region_lead
  src_id             text NOT NULL,
  dst_id             text NOT NULL,
  lag                int  NOT NULL DEFAULT 0,
  src_region         text,
  dst_region         text,
  n int, k int, expected double precision, ratio double precision, p double precision, q double precision,
  PRIMARY KEY (model_version, training_end_round, kind, src_id, dst_id, lag)
);
CREATE INDEX IF NOT EXISTS idx_rar_src ON research_agent_relations (src_id);
CREATE INDEX IF NOT EXISTS idx_rar_dst ON research_agent_relations (dst_id);

-- 5. 지방장 → 중앙 엔진 납품 (실전 목표 회차, 불변 스냅샷)
CREATE TABLE IF NOT EXISTS research_agent_deliveries (
  model_version   text NOT NULL,
  target_round    int  NOT NULL,
  agent_id        text NOT NULL,
  store_code      text NOT NULL,
  mode            text NOT NULL DEFAULT 'live' CHECK (mode IN ('live','backtest')),
  rank            int  NOT NULL,          -- 지역 내 후보 순위
  score           double precision NOT NULL,  -- 연구 기반 후보 점수 (회차당 1·2등 기대 빈도, 판매량 미보정)
  p_first         double precision,       -- 회차당 1등 기대 빈도 (판매량 미보정, 한 장당 확률 아님)
  store_name      text,
  address         text,
  lat double precision, lng double precision,
  history         jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {first, second, last_event_round, gaps}
  components      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {base, region_prior, live_factor, explore_factor}
  hypotheses      jsonb NOT NULL DEFAULT '[]'::jsonb,   -- 적용·관련 가설 [{id, kind, status, factor, applied}]
  verification    text NOT NULL,          -- 검증 가설 반영 | 이력 기반(검증 가설 없음)
  data_quality    jsonb NOT NULL DEFAULT '{}'::jsonb,
  training_end_round int NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (model_version, target_round, agent_id, store_code, mode)
);
CREATE INDEX IF NOT EXISTS idx_rad_target ON research_agent_deliveries (target_round, agent_id);
CREATE INDEX IF NOT EXISTS idx_rad_store ON research_agent_deliveries (store_code);

-- 6. 판매점별 지방장 점수 (목표 회차 전체 판매점, 불변 스냅샷 — 내 주변·경로·지역 화면에서 사용)
CREATE TABLE IF NOT EXISTS research_agent_store_scores (
  model_version   text NOT NULL,
  target_round    int  NOT NULL,
  store_code      text NOT NULL,
  agent_id        text NOT NULL,
  agent_rank      int  NOT NULL,
  agent_size      int  NOT NULL,
  score           double precision NOT NULL,
  p_first         double precision,
  live_factor     double precision NOT NULL DEFAULT 1,
  explore_factor  double precision NOT NULL DEFAULT 1,
  hyp_count       int NOT NULL DEFAULT 0,
  training_end_round int NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (model_version, target_round, store_code)
);
CREATE INDEX IF NOT EXISTS idx_rass_agent ON research_agent_store_scores (target_round, agent_id, agent_rank);

-- 7. 지방장별 회차 평가 (backtest = 사후 순차 재현, live = 추첨 전 저장 납품의 평가) — 불변
CREATE TABLE IF NOT EXISTS research_agent_round_evals (
  model_version   text NOT NULL,
  target_round    int  NOT NULL,
  agent_id        text NOT NULL,
  mode            text NOT NULL CHECK (mode IN ('live','backtest')),
  delivered       text[] NOT NULL DEFAULT '{}',   -- 실전 목록 (검증 통과 가설만 반영)
  explored        text[] NOT NULL DEFAULT '{}',   -- 탐색 목록 (연구 중 가설까지 반영)
  history_only    text[] NOT NULL DEFAULT '{}',   -- 이력만 사용한 기준 목록
  hits_first      int NOT NULL DEFAULT 0,         -- 실전 목록 1등 적중
  hits_any        int NOT NULL DEFAULT 0,         -- 실전 목록 1·2등 적중
  explore_hits_any int NOT NULL DEFAULT 0,
  history_hits_any int NOT NULL DEFAULT 0,
  region_events   int NOT NULL DEFAULT 0,         -- 해당 지역 실제 1·2등 판매점 수
  region_first    int NOT NULL DEFAULT 0,
  expected_uniform double precision,              -- 무작위 K곳 기대 적중
  n_stores        int,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (model_version, target_round, agent_id, mode)
);
CREATE INDEX IF NOT EXISTS idx_rare_agent ON research_agent_round_evals (agent_id);

-- 8. 중앙 엔진 통합 결과 (지역 후보 평가와 판매점 후보 평가 분리, 불변)
CREATE TABLE IF NOT EXISTS research_agent_central (
  model_version   text NOT NULL,
  target_round    int  NOT NULL,
  mode            text NOT NULL CHECK (mode IN ('live','backtest')),
  training_end_round int NOT NULL,
  focus_regions   jsonb NOT NULL DEFAULT '[]'::jsonb,  -- [{region_id, p, base, ratio, factor, rank}]
  store_top       jsonb NOT NULL DEFAULT '[]'::jsonb,  -- [{store_code, agent_id, name, score, p_first, agent_rank, verification}]
  live_hypotheses int NOT NULL DEFAULT 0,               -- 이번 회차 실전 반영된 검증 통과 가설 수
  agents_delivered int NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (model_version, target_round, mode)
);

-- 9. 중앙 엔진 평가 (불변)
CREATE TABLE IF NOT EXISTS research_agent_central_evals (
  model_version   text NOT NULL,
  target_round    int  NOT NULL,
  mode            text NOT NULL CHECK (mode IN ('live','backtest')),
  metrics         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (model_version, target_round, mode)
);

-- 10. 비서 브리핑 근거 (Worker 가 DB 결과로 생성)
CREATE TABLE IF NOT EXISTS research_agent_briefings (
  model_version      text NOT NULL,
  target_round       int  NOT NULL,
  training_end_round int  NOT NULL,
  payload            jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at         timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (model_version, target_round, training_end_round)
);

-- 11. 실행 기록 (체크포인트·오류·사용량)
CREATE TABLE IF NOT EXISTS research_agent_runs (
  model_version      text NOT NULL,
  training_end_round int  NOT NULL,
  status             text NOT NULL CHECK (status IN ('running','completed','failed')),
  runner             text,
  stats              jsonb NOT NULL DEFAULT '{}'::jsonb,
  error              text,
  started_at         timestamptz NOT NULL DEFAULT now(),
  completed_at       timestamptz,
  PRIMARY KEY (model_version, training_end_round)
);

-- 12. 작업 큐 (회차 스냅샷 저장 원장 — 완료분은 다시 쓰지 않음)
CREATE TABLE IF NOT EXISTS research_agent_jobs (
  model_version  text NOT NULL,
  job_type       text NOT NULL,      -- backtest_round | live_delivery | live_eval
  job_key        int  NOT NULL,      -- 목표 회차
  status         text NOT NULL CHECK (status IN ('pending','done','failed')),
  attempts       int  NOT NULL DEFAULT 0,
  error          text,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (model_version, job_type, job_key)
);

-- ── 불변 스냅샷 보호 ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION research_agent_block_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% 은(는) 불변 스냅샷입니다 (UPDATE/DELETE 금지)', TG_TABLE_NAME;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['research_agent_deliveries','research_agent_store_scores','research_agent_round_evals',
                           'research_agent_central','research_agent_central_evals','research_agent_hypothesis_events'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_immutable', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION research_agent_block_mutation()',
                   t || '_immutable', t);
  END LOOP;
END $$;

-- ── RLS: 읽기 전용 공개, 쓰기는 service_role(Worker)만 ─────────────
-- 앱은 Supabase 인증 없이 anon 키를 쓰고 관리자 여부는 기기 로컬 플래그라서, DB 수준의 '관리자 전용 읽기'는 불가능하다.
-- 대신 익명 사용자의 INSERT/UPDATE/DELETE 는 정책이 없으므로 모두 거부된다.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['research_agents','research_agent_hypotheses','research_agent_hypothesis_events',
                           'research_agent_relations','research_agent_deliveries','research_agent_store_scores',
                           'research_agent_round_evals','research_agent_central','research_agent_central_evals',
                           'research_agent_briefings','research_agent_runs','research_agent_jobs'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t || '_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO anon, authenticated USING (true)', t || '_read', t);
  END LOOP;
END $$;

SELECT table_name FROM information_schema.tables
WHERE table_name LIKE 'research_agent%' ORDER BY table_name;
