-- ================================================================
-- research_v12_ledger_fix_1247.sql — 1247회 사전 등록 정정 (1회성)
-- 사고: 1246회 추첨 직후, 엔진이 1246회를 반영하기 전에 1245회까지 학습한 번호가
--       1247회 공식 번호(official_final)·비인기 추천(popularity_pick)으로 사전 등록됨.
-- 조치: 판매 마감(10/24 20:00 KST) 전이므로 두 등록을 정정한다.
--       지우기 전에 원본 전체를 research_results(ledger_correction)에 남겨 기록을 보존한다.
--       삭제 방지 트리거는 이 트랜잭션 안에서만 잠시 끄고 바로 다시 켠다.
-- 이후 서버가 1246회까지 학습한 번호로 다시 등록한다 (코드 수정: 직전 회차까지 학습한 것만 등록).
-- 크롤링 테이블은 건드리지 않는다.
-- ================================================================
BEGIN;

INSERT INTO research_results (research_type, model_version, training_end_round, target_round, payload)
SELECT 'ledger_correction', 'v1', 1245, 1247,
       jsonb_build_object(
         'reason', '1246회 결과 반영 전(1245회까지 학습) 번호가 1247회로 사전 등록됨 — 판매 마감 전 정정',
         'corrected_at', now(),
         'removed', jsonb_agg(to_jsonb(p)))
FROM research_predictions p
WHERE p.target_round = 1247 AND p.data_end_round = 1245
  AND p.algorithm IN ('official_final', 'popularity_pick')
HAVING count(*) > 0
ON CONFLICT (research_type, model_version, training_end_round, target_round) DO NOTHING;

ALTER TABLE research_predictions DISABLE TRIGGER trg_research_predictions_no_delete;
DELETE FROM research_predictions
 WHERE target_round = 1247 AND data_end_round = 1245
   AND algorithm IN ('official_final', 'popularity_pick');
ALTER TABLE research_predictions ENABLE TRIGGER trg_research_predictions_no_delete;

DELETE FROM research_results
 WHERE research_type = 'number_popularity' AND target_round = 1247 AND training_end_round = 1245;

COMMIT;

-- 확인: 1247회 등록이 비어 있고(서버가 1246회 반영 후 다시 등록), 정정 기록 1행, 삭제 방지 트리거 켜짐
SELECT 'registrations_1247' AS check, count(*)::text AS value FROM research_predictions WHERE target_round = 1247
UNION ALL
SELECT 'correction_log', count(*)::text FROM research_results WHERE research_type = 'ledger_correction' AND target_round = 1247
UNION ALL
SELECT 'no_delete_trigger', CASE tgenabled WHEN 'O' THEN 'enabled' ELSE 'DISABLED' END
  FROM pg_trigger WHERE tgname = 'trg_research_predictions_no_delete';
