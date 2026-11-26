"""
GitHub Actions 워크플로 바로 실행 — 브라우저로 GitHub 에 못 들어갈 때 터미널에서

  · GitHub 로그인은 git 에 저장된 로그인 정보(git credential)를 그대로 쓴다 (화면·파일에 남기지 않음).
  · api.github.com 의 workflow_dispatch 만 호출한다 (워크플로에 workflow_dispatch 가 있어야 함).

사용: python tools/run_workflow.py crawl-speeto.yml
      python tools/run_workflow.py research-7183.yml late_sets=true     (워크플로 입력값은 이름=값 으로)
"""

import subprocess
import sys

import requests

REPO = "verca-one/Lucky-Lotto-Finder"


def git_token():
    out = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line[len("password="):]
    sys.exit("git 에 저장된 GitHub 로그인 정보가 없습니다")


def main():
    if len(sys.argv) < 2 or not sys.argv[1].endswith(".yml") or any("=" not in x for x in sys.argv[2:]):
        sys.exit("사용: python tools/run_workflow.py <워크플로 파일 이름>.yml [입력이름=값 ...]")
    wf = sys.argv[1]
    inputs = dict(x.split("=", 1) for x in sys.argv[2:])
    h = {"Authorization": f"Bearer {git_token()}", "Accept": "application/vnd.github+json",
         "X-GitHub-Api-Version": "2022-11-28"}
    r = requests.post(f"https://api.github.com/repos/{REPO}/actions/workflows/{wf}/dispatches", headers=h,
                      json={"ref": "main", **({"inputs": inputs} if inputs else {})}, timeout=30)
    if r.status_code == 204:
        print(f"실행 요청 완료: {wf} (1~2분 뒤 시작)")
    else:
        sys.exit(f"실행 요청 실패: HTTP {r.status_code} {r.text[:200]}")


if __name__ == "__main__":
    main()
