"""
일반 사용자 공개 Worker — 구매예측번호 3세트 + 공개 연구 1개 요약 (research_v8_public.sql)

* 읽기: research_results (research_type = purchase_model), lotto_winning_numbers — 읽기 전용, 수정·삭제 없음
* 쓰기: research_public_purchase, research_public_study 만 (service_role 키, GitHub Actions 에서만)
* 공개 행에는 요약만 넣는다: 번호·판매 비율·상태·짧은 설명. 모델 계수·내부 로그·전체 연구 데이터는 넣지 않는다.
* 외부 사이트 접속 없음 (Supabase REST 만 사용).

공개 연구 선정
  후보 = 원본 구매예측 결과 안의 연구 과제(empirical / volume / popularity) 중 상태가 '연구 중'·'검증 중'인 것
    - gate_pass            → 검증 완료 (후보 아님)
    - '표본 부족' 미통과    → 연구 중  (데이터 축적 중)
    - 표본 충족 후 미통과   → 검증 실패 (후보 아님)
  같은 목표 회차에는 이미 공개된 연구를 유지하고(상태만 동기화), 새 회차에는 직전 회차 공개 연구가
  여전히 후보이면 그대로 이어 간다. 후보가 없으면 공개 연구를 만들지 않는다(앱: '현재 공개 중인 연구가 없습니다').

사용
  python research_public_worker.py            # 서버 (SUPABASE_URL, SUPABASE_KEY = service_role)
  python research_public_worker.py --dry-run  # 쓰기 없이 공개될 내용만 출력 (anon 키로도 가능)
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

import requests

PUBLIC_STATUSES = ("연구 중", "검증 중")
MAX_SETS = 3

STUDY_TEXT = {
    "popularity": {
        "title": "번호 인기도 연구 (4등 당첨자 수 기반)",
        "purpose": "사람들이 어떤 번호를 많이 사고 적게 사는지 추정할 수 있는지 확인합니다.",
        "method": "회차별 4등 당첨자 수를 기대값과 비교해 번호별 판매 경향을 학습하고, 이후 회차에서 맞는지 순서대로 검증합니다.",
    },
    "empirical": {
        "title": "수동 선택 비율 연구",
        "purpose": "사람이 직접 고른 번호 조합에 공통된 특징이 있는지 확인합니다.",
        "method": "당첨 조합의 특징과 1등 당첨자 중 수동 선택 비율을 비교합니다 (앞 회차로 학습, 뒤 회차로 검증).",
    },
    "volume": {
        "title": "판매량 보정 1등 당첨자 수 연구",
        "purpose": "번호 조합의 특징이 1등 당첨자 수와 관련이 있는지 확인합니다.",
        "method": "회차별 판매량을 감안한 기대 1등 당첨자 수와 실제 1등 당첨자 수를 비교합니다.",
    },
}


class Db:
    def __init__(self, url, key, dry_run=False):
        self.base = url.rstrip("/") + "/rest/v1/"
        self.h = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        self.dry = dry_run

    def get(self, table, params):
        r = requests.get(self.base + table, params=params, headers=self.h, timeout=60)
        if r.status_code != 200:
            raise RuntimeError(f"select {table} {r.status_code} {r.text[:200]}")
        return r.json()

    def upsert(self, table, row, on_conflict):
        if self.dry:
            print(f"[dry-run] upsert {table}: {json.dumps(row, ensure_ascii=False)[:600]}")
            return
        h = dict(self.h, Prefer="resolution=merge-duplicates,return=minimal")
        r = requests.post(self.base + table, params={"on_conflict": on_conflict}, headers=h, json=row, timeout=60)
        if r.status_code not in (200, 201, 204):
            raise RuntimeError(f"upsert {table} {r.status_code} {r.text[:300]}")

    def patch(self, table, params, row):
        if self.dry:
            print(f"[dry-run] patch {table} {params}: {row}")
            return
        h = dict(self.h, Prefer="return=minimal")
        r = requests.patch(self.base + table, params=params, headers=h, json=row, timeout=60)
        if r.status_code not in (200, 204):
            raise RuntimeError(f"patch {table} {r.status_code} {r.text[:300]}")


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def version_key(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")) or (0,)


def study_status(m):
    """원본 연구 과제(payload 하위 보고) → 실제 상태. 데이터가 없으면 None."""
    if not m or not m.get("available"):
        return None
    if m.get("gate_pass"):
        return "검증 완료"
    if str(m.get("gate_reason", "")).startswith("표본 부족"):
        return "연구 중"
    return "검증 실패"


def _rounds(m, key):
    r = m.get(key) or []
    return (r[0], r[1]) if len(r) == 2 and r[0] and r[1] else None


def study_summary(key, m, payload):
    """일반 사용자용 요약 (실제 값만, 없으면 해당 항목 생략)"""
    status = study_status(m)
    text = STUDY_TEXT[key]
    n_train, n_test = m.get("n_train") or 0, m.get("n_test") or 0
    tr = _rounds(m, "test_rounds")
    unit = "건" if key == "empirical" else "회차"
    progress = None
    if n_train or n_test:
        progress = f"학습 {n_train:,}{unit} · 검증 {n_test:,}{unit}" + (f" (검증 {tr[0]}~{tr[1]}회)" if tr else "")
    observation = None
    if key == "popularity" and m.get("h1_corr") is not None and status == "검증 완료":
        observation = f"검증 구간에서 예측한 번호 인기도와 실제 4등 판매 경향의 상관이 {m['h1_corr']:.2f}로 나타났습니다."
    elif status == "검증 실패":
        observation = "검증 구간에서 기준보다 나아졌다고 볼 근거가 부족해, 효과를 확인하지 못했습니다."
    elif status == "연구 중":
        observation = "검증에 필요한 표본이 아직 모자라 데이터를 모으는 중입니다."
    applied = key == "popularity" and payload.get("ranking_source") == "popularity"
    limitation = ("추천번호 순위에 적용 중입니다. 당첨 확률을 높이지는 않으며, 실전 회차 성과는 아직 쌓이는 중입니다."
                  if applied else "추천번호에는 적용하지 않습니다. 검증을 통과하기 전까지 결과로 쓰지 않습니다.")
    return {
        "title": text["title"], "purpose": text["purpose"], "method": text["method"],
        "progress": progress, "observation": observation, "status": status,
        "applied_to_numbers": applied, "limitation": limitation,
    }


def purchase_row(src, target):
    p = src["payload"]
    pop = p.get("popularity") or {}
    passed = bool(pop.get("gate_pass")) and p.get("ranking_source") == "popularity"
    sets = []
    if passed:
        for rec in (p.get("recommendations") or [])[:MAX_SETS]:
            nums = rec.get("numbers") or []
            if len(nums) != 6:
                continue
            ratio = rec.get("popularity_index")
            sets.append({"numbers": sorted(int(n) for n in nums),
                         "sales_ratio": round(float(ratio), 2) if isinstance(ratio, (int, float)) else None})
    tr = _rounds(pop, "test_rounds")
    if passed and sets:
        status = "검증 통과"
        summary = ("다른 구매자들이 상대적으로 덜 사는 번호 조합을 고른 추천입니다. "
                   "모든 조합의 1등 확률(1/8,145,060)은 같고, 1등이 됐을 때 당첨금을 나눌 사람이 줄어드는 것을 노립니다."
                   + (f" 지난 {tr[0]}~{tr[1]}회 데이터로 순서대로 검증해 통과했습니다." if tr else ""))
    else:
        status = "검증 실패"
        summary = "이번 회차 구매예측 모델이 검증을 통과하지 못해 번호를 제공하지 않습니다."
        sets = []
    return {
        "target_round": target, "training_end_round": src["training_end_round"],
        "model_version": src["model_version"], "source_research_id": src["id"],
        "validation_status": status, "validation_summary": summary, "sets": sets,
        "is_public_approved": True, "research_updated_at": src["created_at"], "updated_at": now_iso(),
    }


def choose_study(payload, keep_key=None):
    """공개 후보 중 1개. keep_key 가 여전히 후보면 유지, 아니면 검증 진행도(검증 표본 수)가 큰 것."""
    cands = []
    for key in ("popularity", "empirical", "volume"):
        m = payload.get(key) or {}
        if study_status(m) in PUBLIC_STATUSES:
            cands.append((key, m))
    if not cands:
        return None
    for key, m in cands:
        if key == keep_key:
            return key
    cands.sort(key=lambda km: (km[1].get("n_test") or 0, km[1].get("n_train") or 0), reverse=True)
    return cands[0][0]


def run(db):
    latest = db.get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})
    if not latest:
        print("당첨번호 데이터 없음 — 종료")
        return
    target = int(latest[0]["round"]) + 1
    rows = db.get("research_results", {
        "select": "id,model_version,training_end_round,target_round,created_at,payload",
        "research_type": "eq.purchase_model", "target_round": f"eq.{target}",
        "order": "created_at.desc", "limit": "20"})
    if not rows:
        print(f"{target}회 구매예측 원본 결과 없음 — 공개 행을 만들지 않음 (앱: 준비 중)")
        return
    src = max(rows, key=lambda r: (version_key(r["model_version"]), r["created_at"]))
    payload = src["payload"]
    print(f"원본 연구 결과 {src['id']} ({src['model_version']}, 학습 ~{src['training_end_round']}회 → {target}회)")

    prow = purchase_row(src, target)
    db.upsert("research_public_purchase", prow, "target_round")
    print(f"  구매예측번호: {prow['validation_status']} · {len(prow['sets'])}세트")

    # 공개 연구: 같은 회차 → 유지·동기화 / 새 회차 → 직전 공개 연구 이어 가기 / 없으면 생략
    current = [] if db.dry else db.get("research_public_study", {
        "select": "study_key", "target_round": f"eq.{target}", "is_active": "is.true"})
    keep = current[0]["study_key"] if current else None
    if keep is None and not db.dry:
        prev = db.get("research_public_study", {
            "select": "study_key", "target_round": f"lt.{target}", "is_active": "is.true",
            "order": "target_round.desc", "limit": "1"})
        keep = prev[0]["study_key"] if prev else None

    if current:
        # 이미 공개 중인 연구는 상태가 바뀌어도 같은 연구로 유지하고 내용만 동기화
        key = current[0]["study_key"]
    else:
        key = choose_study(payload, keep)
    if key is None:
        print("  공개 연구: 후보 없음 ('연구 중' 상태 연구 없음) — 공개 연구를 만들지 않음")
        return
    s = study_summary(key, payload.get(key) or {}, payload)
    db.patch("research_public_study", {"target_round": f"eq.{target}", "study_key": f"neq.{key}"}, {"is_active": False})
    db.upsert("research_public_study", dict(s, target_round=target, source_research_id=src["id"], study_key=key,
                                             research_updated_at=src["created_at"], is_public_approved=True,
                                             is_active=True, updated_at=now_iso()),
              "target_round,study_key")
    print(f"  공개 연구: {key} · {s['status']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        print("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
        sys.exit(1)
    run(Db(url, key, dry_run=a.dry_run))


if __name__ == "__main__":
    main()
