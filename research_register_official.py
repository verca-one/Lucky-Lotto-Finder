"""
공식 최종 추천번호(fr-1.0) 5세트를 사전 등록 장부(research_predictions)에 등록 — 서버(service_role) 전용

  · 대상: 다음 추첨 회차(최신 당첨 회차 + 1)
  · 등록 내용: 목표 회차의 직전 회차(최신 추첨 회차)까지 학습한 스냅샷(관리자·브리핑 화면의 공식 5세트와 같은 행)
    — 엔진이 최신 회차를 아직 반영하지 않았으면 등록하지 않고 기다린다 (이전 학습 번호로 대신 등록 금지)
  · 판매 마감(토 20:00 KST) 전에만 등록한다. 마감 후에는 등록하지 않는다 (사후 등록 금지).
  · 이미 등록돼 있으면 아무것도 하지 않는다 (DB 잠금: 세트·생성 시각 수정 불가, 삭제 불가)
  · 추첨 후 채점은 서버 파이프라인의 verifyPending 이 다른 등록 예측과 같은 방식으로 한다.
외부 사이트 접속 없음. 크롤링 테이블은 읽기만 한다.
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone

import requests

ALGO = "official_final"
VERSION = "fr-1.0"


def main():
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        print("SUPABASE_URL / SUPABASE_KEY 환경변수 필요"); sys.exit(1)
    base = url.rstrip("/") + "/rest/v1/"
    h = {"apikey": key, "Content-Type": "application/json"}
    if not key.startswith("sb_"):
        h["Authorization"] = f"Bearer {key}"

    def get(t, p):
        r = requests.get(base + t, params=p, headers=h, timeout=60)
        r.raise_for_status()
        return r.json()

    w = get("lotto_winning_numbers", {"select": "round,draw_date", "order": "round.desc", "limit": "1"})[0]
    target = w["round"] + 1
    try:
        d = datetime.strptime(str(w["draw_date"])[:10].replace(".", "-"), "%Y-%m-%d")
    except ValueError:
        d = datetime(2002, 12, 7) + timedelta(days=7 * (w["round"] - 1))
    d = d + timedelta(days=7)
    deadline = datetime(d.year, d.month, d.day, 11, tzinfo=timezone.utc)   # 토 20:00 KST
    now = datetime.now(timezone.utc)

    if get("research_predictions", {"select": "id", "algorithm": f"eq.{ALGO}", "version": f"eq.{VERSION}",
                                    "target_round": f"eq.{target}"}):
        print(f"{target}회 공식 5세트 이미 등록됨 — 변경 없음"); return
    if now >= deadline:
        print(f"{target}회 판매 마감 후 — 사후 등록하지 않음"); return
    fr = get("research_results", {"select": "id,training_end_round,payload->sets,payload->generated_at",
                                  "research_type": "eq.final_recommendation", "model_version": f"eq.{VERSION}",
                                  "target_round": f"eq.{target}", "training_end_round": f"eq.{w['round']}", "limit": "1"})
    if not fr or not fr[0].get("sets") or len(fr[0]["sets"]) != 5:
        print(f"{target}회 공식 최종 추천번호({w['round']}회까지 학습) 저장본 없음 — 엔진 반영 후 등록 (대기)"); return
    f = fr[0]
    row = {"algorithm": ALGO, "version": VERSION, "target_round": target, "data_end_round": f["training_end_round"],
           "sets": f["sets"], "generated_at": now.isoformat(), "deadline_at": deadline.isoformat(),
           "pre_deadline": True, "locked": True, "status": "pending"}
    r = requests.post(base + "research_predictions", params={"on_conflict": "algorithm,version,target_round"},
                      headers=dict(h, Prefer="resolution=ignore-duplicates,return=minimal"),
                      data=json.dumps([row], ensure_ascii=False).encode("utf-8"), timeout=60)
    if r.status_code not in (200, 201, 204):
        print(f"등록 실패 {r.status_code} {r.text[:200]}"); sys.exit(1)
    print(f"{target}회 공식 5세트 사전 등록 (스냅샷 {f['id'][:8]} · 학습 ~{f['training_end_round']}회 · "
          f"생성 {f.get('generated_at')} · 마감 {deadline.isoformat()})")


if __name__ == "__main__":
    main()
