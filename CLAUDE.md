# 복권명당 프로젝트 작업 지침

## 최우선 원칙 — 기존 크롤링 시스템 절대 보호

기존 크롤링 시스템은 **수정 금지 영역**이다. 새로운 기능이 기존 크롤링에 영향을 주어서는 안 된다.

1. 기존 크롤링 코드 수정·삭제·교체 금지.
2. 기존 API 호출 방식, URL, 세션, 인증, 헤더, 파싱 방식 변경 금지.
3. 기존 크롤링 실행 주기, 스케줄러, 자동화 작업 변경 금지.
4. 기존 크롤링 DB 스키마, 저장 경로, 데이터 구조 변경 금지.
5. 기존 크롤링의 동작을 우회하거나 새로운 수집 방식으로 대체하지 말 것.
6. 기존 크롤링 파일에 신규 기능을 끼워 넣지 말 것.
7. 기존 크롤링을 테스트 목적으로도 임의 실행하지 말 것.
8. 기존 크롤링 결과를 삭제하거나 재수집하거나 덮어쓰지 말 것.

### 보호 대상 파일
- 루트 `*.py` 전체 (`lotto_verca_crawler.py`, `lotto_verca_winning_numbers.py`, `lotto_verca_uploader.py`,
  `lotto_verca_geocoder.py`, `recalculate_badges.py`, `recalculate_store_counts.py`, `update_stats_home.py`,
  `verify_crawl_result.py`, `crawl_log_writer.py`, `lotto_winning_upload.py`, `crawl_lotto_stores_*.py`,
  `*upload_to_supabase.py`, `supabase_config.py` 등)
- `.github/workflows/crawl-*.yml`
- `gooddear/data/crawling/`
- 크롤러가 쓰는 Supabase 테이블: `lottery_stores`, `winning_history`, `lotto_winning_numbers`,
  `pension_winning_numbers`, `crawl_logs`, `round_crawl_status`, `store_badges`, `lottery_rounds`

## 신규 연구 기능 개발 원칙 (추첨예측·구매예측·판매점 분석 등)

- 기존 DB에 이미 저장된 데이터를 **읽기 전용**으로 활용한다.
- 기존 크롤링과 독립된 별도 파일·모듈에서만 개발한다.
- 필요한 데이터가 기존 DB에 없으면 **'데이터 미확보'**로 보고한다. 추정값을 실제 측정값처럼 저장하지 않는다.
- 추가 데이터 수집이 필요하면 목적과 수집 방법을 먼저 보고하고 **승인을 기다린다**.
- 외부 사이트 접속, 신규 크롤러 생성 및 실행(임시 probe 스크립트 포함)도 **사전 승인 없이 진행하지 않는다**.
- 기존 크롤링과 연결된 코드가 수정 대상에 포함되면 즉시 작업을 멈추고 보고한다.

## 기타
- API 키·비밀키 값은 채팅에 출력하지 않는다. 환경변수는 이름만 확인한다.
- 기존 엔진(Number/Store/Joint/MND)과 기존 추천번호 결과는 삭제·임의 변경하지 않는다.
