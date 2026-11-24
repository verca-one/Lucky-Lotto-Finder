# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

### 절대 금지 — 당첨판매점 크롤링 · 당첨번호 크롤링 (2026-11-20 사용자 지시)

무슨 일이 있어도 당첨판매점 크롤링과 당첨번호 크롤링은 건드리지 않는다. 코드 · 워크플로 · 실행 일정 · 실행 자체 모두.
문제가 보여도 고치지 말고 **보고만** 한다. 다른 기능을 고치다가 이쪽이 수정 대상에 들어가면 즉시 멈추고 보고한다.
- 당첨판매점: `lotto_verca_crawler.py`, `lotto_verca_uploader.py`, `recalculate_*.py`, `update_stats_home.py`,
  `verify_crawl_result.py`, `crawl_log_writer.py`, `.github/workflows/crawl-*.yml`
- 당첨번호: `lotto_verca_winning_numbers.py`, `lotto_numbers_collector.py`, `pension_numbers_collector.py`,
  `.github/workflows/collect-lotto-numbers.yml`, `.github/workflows/collect-pension-numbers.yml`

### 보호 대상 파일
- 루트 `*.py` 전체 (`lotto_verca_crawler.py`, `lotto_verca_winning_numbers.py`, `lotto_verca_uploader.py`,
  `lotto_verca_geocoder.py`, `recalculate_badges.py`, `recalculate_store_counts.py`, `update_stats_home.py`,
  `verify_crawl_result.py`, `crawl_log_writer.py`, `lotto_winning_upload.py`, `crawl_lotto_stores_*.py`,
  `*upload_to_supabase.py`, `supabase_config.py` 등)
- `.github/workflows/crawl-*.yml`
- `gooddear/data/crawling/`
- 크롤러가 쓰는 Supabase 테이블: `lottery_stores`, `winning_history`, `lotto_winning_numbers`,
  `pension_winning_numbers`, `crawl_logs`, `round_crawl_status`, `store_badges`, `lottery_rounds`

## PC에서 동행복권 접속 금지 (2026-10-11)

- 이 PC(로컬)에서 동행복권(dhlottery.co.kr)에 접속하는 작업을 하지 않는다. 수집기·probe·curl·테스트 스크립트 모두 포함.
- 로컬에서는 DB에 이미 저장된 데이터(`research_prize_stats` 등)만 사용한다.
- 서버(GitHub Actions)·휴대폰 앱에서의 접속은 이 금지 대상이 아니다. 단 기존 크롤링 시스템은 위 보호 원칙을 따른다.
- `research_prize_stats_collector.py` 는 GitHub Actions 환경이 아니면 수집을 거부한다(`--upload-only` 만 허용).

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
- **비인기 추천조합(②, `popularity_pick pop-1.0`, `research_popularity*.py`)은 절대 수정하지 않는다** (2026-11-24 사용자 지시). 다른 추천번호(① 공식 · ③ 구매예측 · ④ 가설 트랙)를 고칠 때도 이쪽 코드 · 규칙 · 결과는 그대로 둔다.

---

## 저장소 구성

- `flutter_app/` — 실제 앱(복권명당, 패키지 `com.luckylotto.finder`). 일반 모드 + 관리자 모드(브리핑 · 연구소 · 엔진). 대부분의 작업은 여기.
- 루트 `research_*.py` — 연구 워커. GitHub Actions(`research-*.yml`)에서만 저장한다. 크롤러(`lotto_verca_*.py` 등, 보호 대상)와 별개.
- 루트 `research_vNN_*.sql` · `rpa_*.sql` — Supabase 스키마. 사용자가 Supabase SQL 편집기에서 직접 실행한다(자동 적용 없음). 새 테이블이 필요하면 SQL 파일을 만들고 실행을 요청한다.
- 루트 Next.js(`package.json`, `pages/`)는 별도 웹.

## 데이터 흐름 (여러 파일을 봐야 보이는 큰 그림)

```
크롤러(crawl-*.yml, 보호) → lotto_winning_numbers · lottery_stores · winning_history …
수집기(collect-*.yml) → 당첨번호 / Research Worker → research_prize_stats(당첨자 수)
        ↓ 읽기 전용
연구 워커(research-*.yml) → research_results(분석) · research_predictions(사전 등록 장부)
        ↓ 읽기 전용
앱 — 저장본만 표시. 앱은 연구 계산·저장을 하지 않는다. 쓰기는 요청 테이블 insert 뿐
     (research_engine_requests: 엔진 바로 시작 · research_weekly_requests: 예전 '토요일 최종본 지금 반영' — 2026-11-25 부터 앱에서 요청하지 않음)
```

- **사전 등록 장부** `research_predictions` (algorithm · version · target_round, 마감 전 등록 후 고정): `official_final fr-1.0`(①엔진) · `popularity_pick pop-1.0`(②비인기) · `purchase_prediction pp-0.x`(③구매예측) · `hypothesis_track ht-1.0`(④제미나이 가설). `ht-1.0-sat`(토요일 최종본)은 1251회까지의 과거 기록 — 새로 만들지 않는다.
- **추천번호는 월요일 최초 생성본으로 확정** (2026-11-25 사용자 정책): 토요일에 다시 뽑거나 덮어쓰지 않는다. 주중에 생긴 가설 · 복기 규칙은 다음 회차부터. 다시 만들어야 하면 덮어쓰지 말고 별도 버전으로 저장. 알고리즘은 확률이 높아진다는 근거 없이 바꾸지 않는다(진단 먼저 → 승인 후 수정).
- **회차 흐름(KST)**: 토 20:35 추첨 → 당첨번호·판매점 수집 → 월 0시 다음 회차 번호 공개(`research_release.RELEASE_DAYS = 2`, 앱 `RecommendRelease`) → 매일 17시 전략 (토 08:00 에는 가설 공장 · 판매점 가설 · 복기만 최신으로, 번호는 그대로).
- **워크플로 역할**
  - `research-engine.yml` (2시간마다 gate): `research_pipeline_gate.py` 준비 판단 → Dart 엔진을 `flutter test tool/server/research_pipeline_test.dart` 로 헤드리스 실행 → publish(공식 등록 · 비인기 · 복기 · 가설 트랙 · 회차 검증 · 월요일 취합 · 공개 요약).
  - `research-worker.yml` (Crawl Lotto 직후): 당첨자 수 수집 · 지역 연구 · 지방장 238명(`research_agent_worker.py`).
  - `research-strategy.yml` (매일 17시): AI 브리핑전담부서(`research_set_review.py`, 제미나이) → AI 전략기획부(`research_strategy_ai.py`) → 가설 공장 → 판매점 가설 → 가설 트랙 → 연금 · 스피또.
  - `research-weekly.yml` (토 08:00): 가설 공장 · 판매점 가설 · 추천번호 복기만. `research_hypothesis_track.py --final` · `research_weekly_digest.py --stage sat|preview` 는 코드만 남아 있고 호출하지 않는다.
  - `research-request-poll.yml` (10분마다): 앱 요청 테이블을 보고 engine / weekly 워크플로를 실행.
- **"성공"으로 찍혀도 막힐 수 있다**: 대부분 단계가 `continue-on-error`. 당첨자 수가 비면 가설 트랙 · 비인기가 조용히 대기한다. 앱 브리핑의 '제미나이 · 연구 흐름 경고' 상자(`PipelineAlertReport`)가 이를 드러낸다.

## 반드시 짝으로 바꿔야 하는 규칙 (앱 ↔ 서버)

회차 검증(`research_debrief_worker.py`)은 브리핑이 보여준 것을 서버에서 **재현**해서 채점한다. 한쪽만 바꾸면 채점이 어긋난다.
- 브리핑 '이번 주 엔진 추천 명당': 앱 `master_briefing_service.dart` `selectAgentPicks` · `hitAgentPicks`(`kHitRuleFrom`) ↔ 서버 `briefing_picks` · `hit_picks`(`HIT_RULE_FROM`).
- 회차별 등록본 고르기: 앱 `briefing_hit_check.dart` `pickRegistration` ↔ 서버 `research_set_review.pick`.
- 1등 기록 준비 판단: `research_pipeline_gate.need_first` ↔ `research_agent_worker.ready_latest`.
- 엔진 공개 요일: `research_release.RELEASE_DAYS` ↔ 앱 `recommend_release.dart`.

## 앱 구조 핵심

- 관리자 브리핑: `lib/screens/admin_screen.dart` `BriefingDetailScreen` — '회차 상황판'(상단 보고 묶음) + '본 브리핑'(`MasterBriefingSection` → 지방장 연구 → 엔진 복기). 자동 새로고침 없음(앱바 ↻ 만), 탭은 keep-alive.
- 연구 서비스: `lib/services/research/` (저장본 읽기 모델 · 리포지토리). 연구소 메뉴 순서는 `admin_research_lab_screen.dart` `kResearchLabEntries`.
- 광고: `lib/services/ad_service.dart` — debug 빌드는 `kDebugMode` 로 Google 테스트 광고 ID, 관리자 폰은 광고 안 받음. 실광고 노출로 AdMob 무효 트래픽 제한을 받은 적 있으니 유지.
- **로그인 = 프로필 아이디** (설정에서 저장한 SharedPreferences `userId`). 관리자 모드(`isAdmin`)는 별개의 폰 안 표시 — 서버 쪽 관리자 인증은 없다.
  로그인 · 로그아웃은 `loginNotifier`(`lib/services/favorites_notifier.dart`)로 홈 · 지역 · 주변 화면에 바로 반영한다.
- **판매점 카드**는 홈 · 지역 · 주변 모두 `RankingStoreCard` — 순위 배지 아래 승인 사진 · 카메라(`onPhotoTap`, 로그인 시만), 맨 아래 줄 [산 번호 QR](`onQrTap`).
  `showStoreDetailPopup`(store_detail_popup.dart)은 **어디서도 열리지 않는 화면**이다. 기능을 거기 달지 말 것.
- **구입한 기록** (즐겨찾기 › 나의 번호): 폰 안 `my_purchases` 에만 저장. 로또 용지 QR 은 폰 안에서 글자만 해석(`parseLottoQr`, 동행복권 접속 없음).
  추천 메뉴의 '저장한 번호'(`my_lotto_numbers`)와 따로다. 당첨번호가 들어오면 등수를 자동으로 맞춰 본다.
- **판매점 사진**: 사용자(로그인) 올리기 → '승인 대기' → 관리자 메뉴 '판매점 사진 승인'에서 승인한 것만 표시(로그인 무관).
  표 · 함수 `store_photos.sql` · `store_photos_delete.sql`. 승인 · 목록 · 삭제는 서버 함수 + **승인 키**(DB `store_photo_admin` 에만, 앱 · 채팅에 쓰지 않음).
  삭제는 목록에서만 지우고 Storage 파일은 남긴다(앱에 파일 삭제 권한을 열지 않으려고).

## 명령어

```bash
# 앱 (flutter_app/ 에서)
flutter test                                              # 전체
flutter test test/widgets/briefing_desk_test.dart         # 파일 하나
flutter test test/widgets/x_test.dart --plain-name "이름 일부"   # 테스트 하나
flutter analyze lib/screens/admin_screen.dart             # 바꾼 파일만 (기존 경고 다수)
flutter build apk --debug

# 폰 설치 — adb 는 PATH 에 없음 (PowerShell)
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-debug.apk

# 서버 워크플로 수동 실행 (루트에서)
python tools/run_workflow.py research-strategy.yml
```

- 커밋은 전체 테스트 통과일 때만: `flutter test 2>&1 | tail -1 | tee /dev/stderr | grep -q "All tests passed" && git commit ...` (`tail` 만 쓰면 실패해도 커밋된다).
- 연구 워커를 로컬에서 돌릴 땐 `--dry-run` 만 (저장은 `GITHUB_ACTIONS=true` 에서만). 읽기용 접속값은 `supabase_config._FALLBACK_URL` / `_FALLBACK_KEY` 를 환경변수로 넘겨 쓰고 값은 출력하지 않는다.
- 폰에는 debug 서명 앱이 깔려 있다. `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 이면 사용자에게 앱 삭제를 요청한다(`adb uninstall` 은 막혀 있음).
- 푸쉬는 사용자가 한다. 커밋 후 `git push` 를 요청한다.
- Bash heredoc 으로 큰 Python 패치를 넘기면 따옴표 때문에 깨진다 → 패치 스크립트를 파일로 써서 실행한다.
  CRLF 파일(`pubspec.yaml` 등)은 읽을 때 줄바꿈을 바꾸면 파일 전체가 바뀐 것처럼 보이니, 바이트로 읽고 원래 줄바꿈으로 되돌려 쓴다.
- `pubspec.yaml` 의 `version:` 줄은 사용자가 스토어 올릴 때 직접 바꾼다(미커밋 유지). 의존성 · 에셋을 추가하면 그 hunk 만 골라 커밋한다:
  `git diff pubspec.yaml` 에서 `+version:` hunk 를 뺀 패치를 만들어 `git apply --cached`.
- 폰 상태 확인(디버그 빌드만): `adb shell run-as com.luckylotto.finder cat shared_prefs/FlutterSharedPreferences.xml` — 값은 출력하지 말고 있음/길이만.
- `supabase_config.py` 는 커밋하지 않는다(미추적 유지). 사용자의 미커밋 수정분(크롤러 · `pubspec.yaml` · 미추적 SQL/로그 등)은 건드리지도 커밋하지도 않는다.
