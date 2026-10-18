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
import re
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


KEY_PATTERNS = {  # 알려진 키 형식 — 붙여넣기 때 섞여 들어온 보이지 않는 문자·중복을 걸러낸다
    "GEMINI_API_KEY": r"AIza[0-9A-Za-z_\-]{35}",
    "ANTHROPIC_API_KEY": r"sk-ant-[0-9A-Za-z_\-]+",
}


def clean(name, raw):
    """보이지 않는 문자(터미널 붙여넣기 표시 등) 제거, 키 형식이면 키 부분만. 값 자체는 출력하지 않는다."""
    no_ctrl = re.sub(r"\x1b\[[0-9;]*[~A-Za-z]", "", raw)          # 터미널 붙여넣기 표시(ESC[200~ 등)
    no_ctrl = "".join(ch for ch in no_ctrl if ch.isprintable()).strip()
    removed = len(raw) - len(no_ctrl)
    pat = KEY_PATTERNS.get(name)
    if pat:
        found = re.findall(pat, no_ctrl)
        if not found:
            sys.exit(f"{name} 형식의 키를 찾지 못했습니다 (입력 {len(no_ctrl)}자). 키를 다시 복사해 주세요")
        if len(set(found)) > 1:
            sys.exit(f"서로 다른 키가 {len(set(found))}개 들어왔습니다. 키 하나만 붙여넣어 주세요")
        value = found[0]
        print(f"확인: 키 형식 맞음 ({len(value)}자)"
              + (f" · 중복 {len(found)}번 → 1개만 사용" if len(found) > 1 else "")
              + (f" · 보이지 않는 문자 {removed}개 제거" if removed else ""))
        return value
    if removed:
        print(f"보이지 않는 문자 {removed}개 제거")
    return no_ctrl


def main():
    if len(sys.argv) != 2:
        sys.exit("사용: python tools/set_github_secret.py 비밀값이름  (예: GEMINI_API_KEY)")
    name = sys.argv[1]
    raw = getpass.getpass(f"{name} 값을 붙여넣고 Enter (화면에 표시되지 않음): ")
    value = clean(name, raw)
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
