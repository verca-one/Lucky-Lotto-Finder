-- ══════════════════════════════════════════════════════════════
-- research_v11_lock.sql — 예측 기록 DB 잠금 (공정성 증명)
--
--  1. 공식 최종 추천번호(final_recommendation)·구매예측(purchase_model) 저장 행: 수정·삭제 불가
--  2. 사전 등록 장부(research_predictions): 삭제 불가 (세트·생성 시각 수정 불가는 기존 잠금 유지,
--     추첨 후 채점 결과 기록만 허용)
--  3. 두 테이블은 서버(service_role)만 쓸 수 있다. 앱 공개 키(anon)는 읽기만.
--     (이전 버전 앱이 사용자 기기에서 연구 결과를 쓰던 경로 차단 — 서버 파이프라인이 유일한 작성자)
--
-- 크롤링 테이블(lottery_stores, winning_history, lotto_winning_numbers 등)은 건드리지 않는다.
-- 적용: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run (다시 실행해도 안전)
-- ══════════════════════════════════════════════════════════════

-- 1. 공식 최종 추천·구매예측 행 잠금
CREATE OR REPLACE FUNCTION research_results_prediction_lock() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '예측 기록(%)은 수정·삭제할 수 없습니다', OLD.research_type;
END $$;
DROP TRIGGER IF EXISTS trg_research_results_prediction_lock ON research_results;
CREATE TRIGGER trg_research_results_prediction_lock
  BEFORE UPDATE OR DELETE ON research_results
  FOR EACH ROW
  WHEN (OLD.research_type IN ('final_recommendation', 'purchase_model'))
  EXECUTE FUNCTION research_results_prediction_lock();

-- 2. 사전 등록 장부 삭제 금지
CREATE OR REPLACE FUNCTION research_predictions_no_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '사전 등록 예측은 삭제할 수 없습니다';
END $$;
DROP TRIGGER IF EXISTS trg_research_predictions_no_delete ON research_predictions;
CREATE TRIGGER trg_research_predictions_no_delete
  BEFORE DELETE ON research_predictions
  FOR EACH ROW EXECUTE FUNCTION research_predictions_no_delete();

-- 3. 앱(anon) 쓰기 차단 — 읽기만 허용
DROP POLICY IF EXISTS "research_results_all" ON research_results;
DROP POLICY IF EXISTS "research_results_read" ON research_results;
CREATE POLICY "research_results_read" ON research_results FOR SELECT TO anon, authenticated USING (true);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON research_results FROM anon, authenticated;
GRANT SELECT ON research_results TO anon, authenticated;
GRANT ALL ON research_results TO service_role;

DROP POLICY IF EXISTS "research_predictions_all" ON research_predictions;
DROP POLICY IF EXISTS "research_predictions_read" ON research_predictions;
CREATE POLICY "research_predictions_read" ON research_predictions FOR SELECT TO anon, authenticated USING (true);
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON research_predictions FROM anon, authenticated;
GRANT SELECT ON research_predictions TO anon, authenticated;
GRANT ALL ON research_predictions TO service_role;

-- 확인용: 트리거 3개(기존 잠금 포함)와 정책
SELECT event_object_table AS "table", trigger_name, event_manipulation
  FROM information_schema.triggers
 WHERE event_object_table IN ('research_results', 'research_predictions')
 ORDER BY 1, 2, 3;
