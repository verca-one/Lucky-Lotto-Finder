"""
GitHub Actions 비밀값(Secrets) 등록 — 브라우저로 GitHub 에 못 들어갈 때 터미널에서 등록

  · 비밀값은 화면에 보이지 않게 입력받는다 (getpass). 파일·로그·화면 어디에도 남기지 않는다.
  · GitHub 로그인은 git 에 저장된 로그인 정보(git credential)를 그대로 쓴다.
  · GitHub 가 준 공개키로 암호화해서 보낸다 (GitHub 공식 방식, PyNaCl 필요: pip install pynacl).
  · api.github.com 만 사용한다.

사용: python tools/set_github_secret.py GEMINI_API_KEY
"""

import base64
import getpass
import subprocess
import sys

import requests
from nacl import encoding, public

REPO = "verca-one/Lucky-Lotto-Finder"


def git_token():
    out = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line[len("password="):]
    sys.exit("git 에 저장된 GitHub 로그인 정보가 없습니다")


def main():
    if len(sys.argv) != 2:
        sys.exit("사용: python tools/set_github_secret.py 비밀값이름  (예: GEMINI_API_KEY)")
    name = sys.argv[1]
    value = getpass.getpass(f"{name} 값을 붙여넣고 Enter (화면에 표시되지 않음): ").strip()
    if not value:
        sys.exit("입력이 비어 있습니다")
    h = {"Authorization": f"Bearer {git_token()}", "Accept": "application/vnd.github+json"}
    r = requests.get(f"https://api.github.com/repos/{REPO}/actions/secrets/public-key", headers=h, timeout=30)
    if r.status_code != 200:
        sys.exit(f"공개키 조회 실패 ({r.status_code}) — 저장소 관리자 권한이 필요합니다")
    pk = r.json()
    box = public.SealedBox(public.PublicKey(pk["key"].encode(), encoding.Base64Encoder()))
    enc = base64.b64encode(box.encrypt(value.encode())).decode()
    r = requests.put(f"https://api.github.com/repos/{REPO}/actions/secrets/{name}", headers=h, timeout=30,
                     json={"encrypted_value": enc, "key_id": pk["key_id"]})
    if r.status_code in (201, 204):
        print(f"{name} 등록 완료 ({'새로 만듦' if r.status_code == 201 else '바꿈'})")
    else:
        sys.exit(f"등록 실패 ({r.status_code})")


if __name__ == "__main__":
    main()
