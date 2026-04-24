# GitHub 저장소 설정 가이드

## 1. 로컬 Git 설정

```bash
# Lucky Lotto Finder 디렉토리로 이동
cd S:\next leval\Lucky Lotto Finder

# Git 초기화
git init

# 사용자 정보 설정
git config user.name "Your Name"
git config user.email "your-email@example.com"

# 모든 파일 추가
git add .

# 초기 커밋
git commit -m "Initial commit: Lucky Lotto Finder App"
```

## 2. GitHub 원격 저장소 연결

```bash
# 원격 저장소 추가 (verca-one/Lucky-Lotto-Finder로 변경)
git remote add origin https://github.com/verca-one/Lucky-Lotto-Finder.git

# 기본 브랜치를 main으로 설정
git branch -M main

# 코드 푸시
git push -u origin main
```

## 3. GitHub Actions 비밀 설정

GitHub 저장소 Settings → Secrets and variables → Actions에서 추가:

### Firebase 자격증명
1. **FIREBASE_CREDENTIALS**: Firebase 서비스 계정 JSON 전체 내용
   - Firebase Console → 프로젝트 설정 → 서비스 계정
   - JSON 파일 전체를 복사하여 붙여넣기

2. **FIREBASE_PROJECT_ID**: Firebase 프로젝트 ID
   - 예: "lucky-lotto-finder"

```bash
# 예시 (CLI를 사용하는 경우)
gh secret set FIREBASE_CREDENTIALS < firebase-key.json
gh secret set FIREBASE_PROJECT_ID -b "your-project-id"
```

## 4. GitHub Actions 테스트

```bash
# 로컬에서 가능한지 확인
cd data/crawling
python -m pip install -r requirements.txt
python scrape_lotto_numbers.py
python crawl_all_lottery.py
```

## 5. 자동 스케줄 확인

### 연금복권 (Pension Lottery)
- **실행 시간**: 매주 목요일 19:30 KST (10:30 UTC)
- **워크플로우**: `.github/workflows/crawl-pension.yml`
- **수동 실행**: GitHub 저장소 → Actions → "Crawl Pension Lottery" → "Run workflow"

### 로또 (Lotto)
- **실행 시간**: 매주 토요일 21:30 KST (12:30 UTC)
- **워크플로우**: `.github/workflows/crawl-lotto.yml`
- **수동 실행**: GitHub 저장소 → Actions → "Crawl Lotto" → "Run workflow"

### 스피또 (Speeto) - 별도 설정
- **워크플로우**: `.github/workflows/crawl-speeto.yml`
- **상태**: 아직 스케줄 미설정 (스피또 크롤링 스크립트 구현 후 설정 필요)

## 트러블슈팅

### Selenium Chrome 드라이버 오류
```bash
# GitHub Actions 환경에는 headless-chrome이 포함되어 있습니다
# 로컬 테스트 시 chromedriver 필요:
pip install webdriver-manager
```

### Firebase 인증 오류
- FIREBASE_CREDENTIALS가 올바른 JSON 형식인지 확인
- 개행 문자가 포함되어 있는지 확인

### 데이터 푸시 실패
```bash
# GitHub 토큰 확인
gh auth status

# 토큰 재생성
gh auth refresh
```

## 파일 구조

```
Lucky Lotto Finder/
├── .github/
│   └── workflows/
│       └── crawl-lottery.yml
├── data/
│   └── crawling/
│       ├── scrape_lotto_numbers.py (Selenium - 당첨번호)
│       ├── crawl_all_lottery.py (당첨지점)
│       ├── crawl_pension_stores.py (연금복권 지점)
│       ├── upload_to_firebase.py (Firebase 업로드)
│       └── requirements.txt
├── app/
├── .gitignore
└── GITHUB_SETUP.md
```
