-- 잘못된 연금복권 데이터 정리 (로또 데이터가 pension으로 잘못 저장됨)
-- 크롤러가 selectLtWnShp.do (로또 전용)를 연금에도 사용해서 발생

-- 1. winning_history에서 잘못된 pension 이력 삭제
DELETE FROM winning_history WHERE lottery_type = 'pension';

-- 2. stores 테이블에서 pension 관련 카운트 초기화
UPDATE stores SET
  pension_first_count = 0,
  pension_second_count = 0,
  pension_total_count = 0,
  pension_latest_first_win = NULL,
  pension_latest_second_win = NULL
WHERE pension_total_count > 0;

-- 3. 배지도 연금 관련 재계산 필요 (recalculate_badges.py pension 재실행)
