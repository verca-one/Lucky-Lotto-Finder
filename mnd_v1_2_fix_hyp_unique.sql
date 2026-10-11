-- ================================================================
-- mnd_v1_2_fix_hyp_unique.sql
-- 가설 테이블 UNIQUE 제약 수정: (hypothesis_id, model_version)
-- 선행: mnd_v1_schema.sql, mnd_v1_1_sessions.sql 이미 적용됨
-- ================================================================

-- 1. 각 hypothesis_id+model_version 조합에서 최신 training_end_round만 남기고 삭제
DELETE FROM mnd_hypotheses h1
WHERE h1.training_end_round < (
  SELECT MAX(h2.training_end_round)
  FROM mnd_hypotheses h2
  WHERE h2.hypothesis_id = h1.hypothesis_id
    AND h2.model_version = h1.model_version
);

-- 2. 기존 3-컬럼 UNIQUE 제약 제거
ALTER TABLE mnd_hypotheses DROP CONSTRAINT IF EXISTS uq_mnd_hypothesis;

-- 3. 새 2-컬럼 UNIQUE 제약 추가 (lifecycle 데이터 보존용)
ALTER TABLE mnd_hypotheses
  ADD CONSTRAINT uq_mnd_hypothesis_canonical UNIQUE (hypothesis_id, model_version);

-- 4. WF 결과 테이블도 동일하게 정리 (hypothesis_id+target_round+model_version)
-- 기존 constraint는 이미 올바름

-- 확인
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'mnd_hypotheses'
  AND constraint_type = 'UNIQUE';
