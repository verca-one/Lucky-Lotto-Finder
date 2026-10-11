-- ================================================================
-- mnd_v1_schema.sql
-- 명당 가설 연구소 DB 스키마 v1.0
--
-- Supabase SQL Editor에서 전체 실행 (재실행 안전)
-- 선행: rpa_v11_unified_prediction.sql (이미 적용됨)
-- ================================================================

-- 1. 판매점 이상 감지 (Theory A Poisson + Theory D Bayesian)
CREATE TABLE IF NOT EXISTS mnd_store_anomalies (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  dhlottery_code      text        NOT NULL,
  store_name          text,
  sido                text,
  sigungu             text,
  total_wins          int         NOT NULL DEFAULT 0,
  expected_wins       double precision,
  poisson_z_score     double precision,
  bayesian_rate       double precision,
  bayesian_lower      double precision,
  bayesian_upper      double precision,
  volume_adjusted     boolean     NOT NULL DEFAULT false,
  anomaly_status      text        NOT NULL DEFAULT 'normal'
                        CHECK (anomaly_status IN ('normal','anomalous','research')),
  last_win_round      int,
  model_version       text        NOT NULL DEFAULT '1.0',
  training_end_round  int         NOT NULL,
  computed_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mnd_store_anomaly UNIQUE (dhlottery_code, model_version, training_end_round)
);
CREATE INDEX IF NOT EXISTS idx_mnd_store_version ON mnd_store_anomalies (model_version, training_end_round);
CREATE INDEX IF NOT EXISTS idx_mnd_store_anomaly_status ON mnd_store_anomalies (anomaly_status, training_end_round);
ALTER TABLE mnd_store_anomalies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mnd_sa_all" ON mnd_store_anomalies;
CREATE POLICY "mnd_sa_all" ON mnd_store_anomalies FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 2. 지역 전이 행렬 (Theory C Markov)
CREATE TABLE IF NOT EXISTS mnd_regional_transitions (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  from_sido           text        NOT NULL,
  to_sido             text        NOT NULL,
  horizon             int         NOT NULL CHECK (horizon BETWEEN 1 AND 6),
  observed_count      int         NOT NULL DEFAULT 0,
  total_from          int         NOT NULL DEFAULT 0,
  observed_rate       double precision,
  baseline_rate       double precision,
  lift                double precision,
  p_value             double precision,
  sample_size         int         NOT NULL DEFAULT 0,
  model_version       text        NOT NULL DEFAULT '1.0',
  training_end_round  int         NOT NULL,
  computed_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mnd_transition UNIQUE (from_sido, to_sido, horizon, model_version, training_end_round)
);
CREATE INDEX IF NOT EXISTS idx_mnd_transition_lift ON mnd_regional_transitions (lift DESC, training_end_round);
ALTER TABLE mnd_regional_transitions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mnd_rt_all" ON mnd_regional_transitions;
CREATE POLICY "mnd_rt_all" ON mnd_regional_transitions FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 3. 가설 테이블
CREATE TABLE IF NOT EXISTS mnd_hypotheses (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  hypothesis_id         text        NOT NULL,
  hypothesis_type       text        NOT NULL
                          CHECK (hypothesis_type IN ('persistence','spatial_cluster','transition','emerging','combined')),
  theory_sources        text[]      NOT NULL DEFAULT '{}',
  subject_type          text        NOT NULL
                          CHECK (subject_type IN ('store','sido','sigungu','national')),
  subject_id            text        NOT NULL,
  subject_name          text,
  condition_json        jsonb       NOT NULL DEFAULT '{}',
  horizon               int,
  evidence_json         jsonb       NOT NULL DEFAULT '{}',
  sample_size           int         NOT NULL DEFAULT 0,
  effect_size           double precision,
  p_value               double precision,
  uncertainty_lower     double precision,
  uncertainty_upper     double precision,
  status                text        NOT NULL DEFAULT 'discovered'
                          CHECK (status IN ('discovered','observing','validating','developing',
                                            'accepted','weakened','combined','rejected')),
  wf_rounds             int         NOT NULL DEFAULT 0,
  wf_successes          int         NOT NULL DEFAULT 0,
  wf_success_rate       double precision,
  wf_baseline_rate      double precision,
  wf_improvement        double precision,
  gate_status           text        NOT NULL DEFAULT 'not_evaluated'
                          CHECK (gate_status IN ('pass','fail','not_evaluated')),
  gate_reason           text,
  live_prediction_active boolean    NOT NULL DEFAULT false,
  model_version         text        NOT NULL DEFAULT '1.0',
  discovered_round      int,
  last_updated_round    int,
  training_end_round    int         NOT NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mnd_hypothesis UNIQUE (hypothesis_id, model_version, training_end_round)
);
CREATE INDEX IF NOT EXISTS idx_mnd_hyp_status ON mnd_hypotheses (status, training_end_round);
CREATE INDEX IF NOT EXISTS idx_mnd_hyp_gate ON mnd_hypotheses (gate_status, training_end_round);
ALTER TABLE mnd_hypotheses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mnd_hyp_all" ON mnd_hypotheses;
CREATE POLICY "mnd_hyp_all" ON mnd_hypotheses FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 4. Walk-Forward 결과
CREATE TABLE IF NOT EXISTS mnd_wf_results (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  hypothesis_id   text        NOT NULL,
  target_round    int         NOT NULL,
  prediction_json jsonb       NOT NULL DEFAULT '{}',
  actual_json     jsonb       NOT NULL DEFAULT '{}',
  success         boolean     NOT NULL,
  score           double precision,
  model_version   text        NOT NULL DEFAULT '1.0',
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mnd_wf UNIQUE (hypothesis_id, target_round, model_version)
);
CREATE INDEX IF NOT EXISTS idx_mnd_wf_hyp ON mnd_wf_results (hypothesis_id, model_version);
ALTER TABLE mnd_wf_results ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mnd_wf_all" ON mnd_wf_results;
CREATE POLICY "mnd_wf_all" ON mnd_wf_results FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 5. 공간 자기상관 (Theory B Moran's I)
CREATE TABLE IF NOT EXISTS mnd_spatial_autocorr (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  scope               text        NOT NULL DEFAULT 'national',
  morans_i            double precision,
  morans_z            double precision,
  morans_p            double precision,
  hotspot_sidos       text[]      DEFAULT '{}',
  coldspot_sidos      text[]      DEFAULT '{}',
  cluster_json        jsonb       DEFAULT '{}',
  model_version       text        NOT NULL DEFAULT '1.0',
  training_end_round  int         NOT NULL,
  computed_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mnd_spatial UNIQUE (scope, model_version, training_end_round)
);
ALTER TABLE mnd_spatial_autocorr ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mnd_spatial_all" ON mnd_spatial_autocorr;
CREATE POLICY "mnd_spatial_all" ON mnd_spatial_autocorr FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 6. 변화점 감지 (Theory F CUSUM)
CREATE TABLE IF NOT EXISTS mnd_change_points (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type        text        NOT NULL CHECK (subject_type IN ('store','sido')),
  subject_id          text        NOT NULL,
  change_point_round  int         NOT NULL,
  direction           text        NOT NULL CHECK (direction IN ('increase','decrease')),
  pre_rate            double precision,
  post_rate           double precision,
  cusum_value         double precision,
  confidence          double precision,
  interpretation      text,
  model_version       text        NOT NULL DEFAULT '1.0',
  training_end_round  int         NOT NULL,
  detected_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mnd_cp UNIQUE (subject_type, subject_id, change_point_round, model_version, training_end_round)
);
CREATE INDEX IF NOT EXISTS idx_mnd_cp_recent ON mnd_change_points (change_point_round DESC, training_end_round);
ALTER TABLE mnd_change_points ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mnd_cp_all" ON mnd_change_points;
CREATE POLICY "mnd_cp_all" ON mnd_change_points FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 7. 연구소장 브리핑
CREATE TABLE IF NOT EXISTS mnd_briefings (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  round           int         NOT NULL,
  briefing_text   text        NOT NULL,
  highlights      jsonb       DEFAULT '[]'::jsonb,
  hypothesis_ids  text[]      DEFAULT '{}',
  model_version   text        NOT NULL DEFAULT '1.0',
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_mnd_briefing UNIQUE (round, model_version)
);
ALTER TABLE mnd_briefings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mnd_brief_all" ON mnd_briefings;
CREATE POLICY "mnd_brief_all" ON mnd_briefings FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- 확인 쿼리
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'mnd_store_anomalies', 'mnd_regional_transitions', 'mnd_hypotheses',
    'mnd_wf_results', 'mnd_spatial_autocorr', 'mnd_change_points', 'mnd_briefings'
  )
ORDER BY table_name;
