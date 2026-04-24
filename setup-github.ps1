# GitHub 저장소 푸시 스크립트 (PowerShell)
# 실행 방법: powershell -ExecutionPolicy Bypass -File setup-github.ps1

Write-Host "🚀 Lucky Lotto Finder GitHub 설정 시작" -ForegroundColor Green
Write-Host "=" * 70

# 1. Git 설정 확인
Write-Host "`n1️⃣ Git 설정 확인..." -ForegroundColor Cyan
git --version
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Git이 설치되지 않았습니다." -ForegroundColor Red
    exit 1
}

# 2. Git 초기화
Write-Host "`n2️⃣ Git 저장소 초기화..." -ForegroundColor Cyan
git init
git add .
git commit -m "Initial commit: Lucky Lotto Finder App"

# 3. 원격 저장소 설정
Write-Host "`n3️⃣ GitHub 원격 저장소 연결..." -ForegroundColor Cyan
$repoUrl = "https://github.com/verca-one/Lucky-Lotto-Finder.git"
Write-Host "저장소 URL: $repoUrl"

git remote add origin $repoUrl
git branch -M main

# 4. GitHub 인증 확인
Write-Host "`n4️⃣ GitHub 인증 확인..." -ForegroundColor Cyan
gh auth status

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ GitHub CLI 로그인이 필요합니다." -ForegroundColor Red
    Write-Host "다음 명령어 실행: gh auth login" -ForegroundColor Yellow
    exit 1
}

# 5. 코드 푸시
Write-Host "`n5️⃣ 코드를 GitHub로 푸시 중..." -ForegroundColor Cyan
git push -u origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ GitHub 푸시 완료!" -ForegroundColor Green
} else {
    Write-Host "`n❌ GitHub 푸시 실패" -ForegroundColor Red
    exit 1
}

# 6. GitHub Secrets 설정 가이드
Write-Host "`n6️⃣ GitHub Secrets 설정 필요" -ForegroundColor Cyan
Write-Host "다음 링크에서 설정하세요:" -ForegroundColor Yellow
Write-Host "https://github.com/verca-one/Lucky-Lotto-Finder/settings/secrets/actions" -ForegroundColor Blue

Write-Host "`n필요한 비밀:" -ForegroundColor Yellow
Write-Host "  1. FIREBASE_CREDENTIALS: Firebase 서비스 계정 JSON" -ForegroundColor Gray
Write-Host "  2. FIREBASE_PROJECT_ID: Firebase 프로젝트 ID" -ForegroundColor Gray

Write-Host "`n설정 후 GitHub Actions 확인:" -ForegroundColor Yellow
Write-Host "https://github.com/verca-one/Lucky-Lotto-Finder/actions" -ForegroundColor Blue

Write-Host "`n" + "=" * 70
Write-Host "✅ GitHub 설정 완료!" -ForegroundColor Green
