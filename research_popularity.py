"""
번호 인기도 연구 (pop-1.0) — 1등 확률은 같아도 '덜 겹치는 번호'로 당첨금 기대값을 올릴 수 있는가

배경
  · 로또 1등은 당첨자끼리 나눠 갖는다(패리뮤추얼). 한 장의 1등 확률(1/8,145,060)은 바꿀 수 없지만,
    사람들이 많이 고르는 번호를 피하면 당첨 시 나눠 가질 사람이 줄어 받는 돈이 커질 수 있다.
  · 측정: 회차별 등수 당첨자 수 ÷ (판매 게임 수 × 그 등수 확률) = 인기도 비율 R.
    모두가 무작위로 샀다면 R≈1. R>1 이면 그 회차 당첨번호(의 부분 조합)를 사람들이 많이 골랐다는 뜻.
    4등(4개 일치)은 회차당 수십만 명이라 우연 오차가 작아 주 지표로 쓴다. 3등은 보조, 1등은 최종 확인.

사전 고정 프로토콜 (결과를 보기 전에 정함)
  · 학습: 269~1000회 / 확인: 1001~1245회 (확인 구간은 학습·선택에 쓰지 않음)
  · 특징(당첨번호 6개 + 직전 회차 번호만 사용, 아래 FEATURES 고정): 생일 범위(≤31)·월 범위(≤12)·연속 쌍·
    용지 같은 세로줄/가로줄/대각선 최대 개수·끝수 같은 최대 개수·5의 배수·등차 최대 길이·직전 회차와 겹침·
    40 이상 개수·합계 치우침·홀짝 치우침·서로 다른 10단위 수
  · 모델: 표준화 특징의 릿지 선형회귀, 목표 log R4
  · 통과 기준: ① 확인 구간 Spearman(예측, log R4) 부트스트랩 95% 하한 > 0
              ② 확인 구간 Spearman(예측, log R3) > 0
              ③ 확인 구간 Spearman(예측, 1등 R1) > 0 (1등은 회차당 평균 10여 명이라 우연 오차가 커 방향만 요구)
    셋 다 만족하면 '통과' — 그때만 인기도 점수를 번호 선택(당첨금 기대값)에 쓰는 것을 제안한다.

결과는 당첨 확률이 아니라 '당첨됐을 때 나눠 가질 사람 수'에 관한 것이다. 확률이 올라간다고 표현하지 않는다.
외부 사이트 접속 없음 — DB에 저장된 research_prize_stats·lotto_winning_numbers(읽기 전용)만 사용.

브리핑 게시 (--publish, 서버 GitHub Actions 전용)
  · 실전 모델: 같은 특징·릿지 회귀를 저장된 전체 회차로 다시 학습 (검증 결과는 위 프로토콜 값을 그대로 함께 저장)
  · 공식 최종 추천번호(fr-1.0) 5세트의 인기도 백분위·예상 1등 몫을 research_results(number_popularity)에 저장
  · 비인기 추천 5세트: 목표 회차로 고정한 난수 조합 중 학습 범위 안(특징별 1~99% 구간)에서 인기도 하위 5% →
    서로 3개 이상 겹치지 않게, 과거 1등 조합 제외하고 낮은 순으로 5세트.
    판매 마감(토 20:00 KST) 전에만 사전 등록 장부(research_predictions, popularity_pick)에 올린다 — 등록 후 변경 불가.
  · 검증이 통과하지 않으면 추천 5세트를 만들지 않는다.
  · 최신 추첨 회차의 당첨자 수(research_prize_stats)가 들어오기 전에는 아무것도 저장·등록하지 않는다.
  · 다음 회차 예측 시점(수요일 0시 KST 또는 앱 수동 추천 요청, research_release.py) 전에는 만들지 않는다.
    공식 5세트 인기도도 직전 회차까지 학습한 공식 스냅샷만 대상으로 한다.

사용: python research_popularity.py [--out result.json] [--sets '[[1,2,3,4,5,6]]']   (검증 · DB 쓰기 없음)
      python research_popularity.py --publish [--dry-run]                         (브리핑 게시 · 서버 전용)
      환경변수 SUPABASE_URL, SUPABASE_KEY
"""

import argparse
import json
import math
import os
import sys
from datetime import datetime, timedelta, timezone
from itertools import combinations

import requests

import numpy as np

from research_region_worker import Db

VERSION = "pop-1.0"
TRAIN = (269, 1000)
TEST = (1001, 1245)
RIDGE = 1.0
BOOT = 2000
SEED = 20261016

TOTAL = 8145060
P = {1: 1 / TOTAL, 3: 228 / TOTAL, 4: 11115 / TOTAL, 5: 182780 / TOTAL}

FEATURES = [
    "le31", "le12", "consec", "col_max", "row_max", "diag_max", "digit_max",
    "mult5", "ap_max", "prev_overlap", "ge40", "sum_dev", "odd_dev", "decades",
]


def _ap_max(ns):
    s, best = set(ns), 1
    for a, b in combinations(sorted(ns), 2):
        d, k, x = b - a, 2, b + (b - a)
        while x in s:
            k, x = k + 1, x + d
        best = max(best, k)
    return best


def features(ns, prev):
    """당첨번호 6개(보너스 제외)와 직전 회차 6개 → 특징 딕셔너리. 용지는 한 줄에 7칸(1~7, 8~14, …)."""
    ns = sorted(ns)
    col = [(n - 1) % 7 for n in ns]
    row = [(n - 1) // 7 for n in ns]
    cnt = lambda xs: max(xs.count(v) for v in set(xs))
    odd = sum(n % 2 for n in ns)
    return {
        "le31": sum(n <= 31 for n in ns),
        "le12": sum(n <= 12 for n in ns),
        "consec": sum(b - a == 1 for a, b in zip(ns, ns[1:])),
        "col_max": cnt(col),
        "row_max": cnt(row),
        "diag_max": max(cnt([r - c for r, c in zip(row, col)]), cnt([r + c for r, c in zip(row, col)])),
        "digit_max": cnt([n % 10 for n in ns]),
        "mult5": sum(n % 5 == 0 for n in ns),
        "ap_max": _ap_max(ns),
        "prev_overlap": len(set(ns) & set(prev or [])),
        "ge40": sum(n >= 40 for n in ns),
        "sum_dev": abs(sum(ns) - 138),
        "odd_dev": abs(odd - 3),
        "decades": len({n // 10 for n in ns}),
    }


def load_rounds(db):
    rows = db.select_all("research_prize_stats", {
        "select": "round,num1,num2,num3,num4,num5,num6,rank1_winners,rank3_winners,rank4_winners,"
                  "rank5_winners,rank1_amount,total_sales_amount,auto_winners,manual_winners,semi_auto_winners,official",
        "official": "eq.true", "order": "round.asc"})
    out, prev = [], None
    for r in rows:
        ns = [r[f"num{i}"] for i in range(1, 7)]
        games = (r["total_sales_amount"] or 0) / 1000
        if games <= 0 or r["rank4_winners"] is None:
            prev = ns
            continue
        e = {k: games * p for k, p in P.items()}
        out.append({
            "round": r["round"], "nums": ns, "games": games,
            "r1": r["rank1_winners"], "e1": e[1],
            "R1": r["rank1_winners"] / e[1], "R3": r["rank3_winners"] / e[3],
            "R4": r["rank4_winners"] / e[4], "R5": r["rank5_winners"] / e[5],
            "manual1": (r["manual_winners"] or 0) + (r["semi_auto_winners"] or 0),
            "amount1": r["rank1_amount"],
            "f": features(ns, prev),
        })
        prev = ns
    return out


def spearman(a, b):
    ra = np.argsort(np.argsort(a)).astype(float)
    rb = np.argsort(np.argsort(b)).astype(float)
    return float(np.corrcoef(ra, rb)[0, 1])


def boot_ci(a, b, rng):
    n, vals = len(a), []
    for _ in range(BOOT):
        i = rng.integers(0, n, n)
        vals.append(spearman(a[i], b[i]))
    return float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5))


class Model:
    def fit(self, X, y):
        self.mu, self.sd = X.mean(0), X.std(0) + 1e-9
        Z = (X - self.mu) / self.sd
        self.b0 = float(y.mean())
        A = Z.T @ Z + RIDGE * np.eye(Z.shape[1])
        self.w = np.linalg.solve(A, Z.T @ (y - self.b0))
        return self

    def predict(self, X):
        return self.b0 + ((X - self.mu) / self.sd) @ self.w


def mat(rows):
    return np.array([[r["f"][k] for k in FEATURES] for r in rows], dtype=float)


def share_multiplier(f, lam):
    """내가 1등일 때 받는 몫의 기대값 E[1/(1+X)], X~Poisson(f·λ) (다른 당첨자 수). 닫힌식 (1-e^-m)/m."""
    m = max(f * lam, 1e-12)
    return (1 - math.exp(-m)) / m


def run(db, out_path=None, sets=None):
    data = load_rounds(db)
    tr = [r for r in data if TRAIN[0] <= r["round"] <= TRAIN[1]]
    te = [r for r in data if TEST[0] <= r["round"] <= TEST[1]]
    Xtr, Xte = mat(tr), mat(te)
    y4tr = np.log([r["R4"] for r in tr])
    model = Model().fit(Xtr, y4tr)
    pte = model.predict(Xte)
    rng = np.random.default_rng(SEED)

    y4 = np.log([r["R4"] for r in te])
    y3 = np.log([r["R3"] for r in te])
    y5 = np.log([r["R5"] for r in te])
    r1 = np.array([r["R1"] for r in te])
    s4, s3, s5, s1 = spearman(pte, y4), spearman(pte, y3), spearman(pte, y5), spearman(pte, r1)
    ci4, ci1 = boot_ci(pte, y4, rng), boot_ci(pte, r1, rng)
    gates = {"①_R4_하한>0": ci4[0] > 0, "②_R3>0": s3 > 0, "③_R1>0": s1 > 0}
    passed = all(gates.values())

    # 1등: 예측 인기도 하위 1/3 vs 상위 1/3 회차의 실제 1등 당첨자/기대
    q = np.quantile(pte, [1 / 3, 2 / 3])
    low = [r for r, p in zip(te, pte) if p <= q[0]]
    high = [r for r, p in zip(te, pte) if p >= q[1]]
    ratio = lambda rs: sum(r["r1"] for r in rs) / sum(r["e1"] for r in rs)

    # 1등 인기도 ↔ 4등 인기도 관계 (학습 구간): log R1 ≈ a + b·log R4 (1등 0명 회차 보정 +0.5)
    lr1 = np.log([(r["r1"] + 0.5) / r["e1"] for r in tr])
    b, a = np.polyfit(y4tr, lr1, 1)

    # 무작위 조합 대비: 예측 인기도 하위 10% 조합을 골랐을 때 예상 1등 몫
    gen = np.random.default_rng(SEED + 1)
    last = data[-1]["nums"]
    sample = [sorted(gen.choice(np.arange(1, 46), 6, replace=False).tolist()) for _ in range(20000)]
    ps = Model.predict(model, np.array([[features(s, last)[k] for k in FEATURES] for s in sample], float))
    lam = float(np.mean([r["e1"] for r in te]))  # 회차당 기대 1등 수 (무작위 구매 가정)
    to_f = lambda p: math.exp(a + b * p) / math.exp(a + b * float(np.mean(ps)))
    cut = np.quantile(ps, 0.10)
    m_rand = float(np.mean([share_multiplier(to_f(p), lam) for p in ps]))
    m_low = float(np.mean([share_multiplier(to_f(p), lam) for p in ps if p <= cut]))

    coef = sorted(zip(FEATURES, model.w.tolist()), key=lambda x: -abs(x[1]))
    res = {
        "version": VERSION, "train": TRAIN, "test": TEST,
        "n_train": len(tr), "n_test": len(te),
        "coef_std": [{"feature": k, "w": round(w, 4)} for k, w in coef],
        "test_spearman": {"R4": round(s4, 4), "R3": round(s3, 4), "R5": round(s5, 4), "R1": round(s1, 4)},
        "test_ci95": {"R4": [round(x, 4) for x in ci4], "R1": [round(x, 4) for x in ci1]},
        "gates": gates, "passed": passed,
        "rank1_actual_over_expected": {"pred_low_third": round(ratio(low), 3),
                                       "pred_high_third": round(ratio(high), 3), "all": round(ratio(te), 3)},
        "r1_from_r4": {"a": round(float(a), 4), "b": round(float(b), 4)},
        "lambda_rank1": round(lam, 2),
        "share_multiplier": {"random_combo": round(m_rand, 4), "low10pct_combo": round(m_low, 4),
                             "gain": round(m_low / m_rand, 3)},
        "manual_share_rank1_test": round(sum(r["manual1"] for r in te) / max(1, sum(r["r1"] for r in te)), 3),
    }
    if sets:
        # 주어진 조합의 인기도 백분위(낮을수록 덜 겹침)와 무작위 조합 대비 예상 1등 몫
        sp = np.sort(ps)
        res["sets"] = []
        for st in sets:
            p = float(model.predict(np.array([[features(st, last)[k] for k in FEATURES]], float))[0])
            res["sets"].append({"set": sorted(st), "popularity_pct": round(100 * np.searchsorted(sp, p) / len(sp), 1),
                                "share_vs_random": round(share_multiplier(to_f(p), lam) / m_rand, 3)})
    print(json.dumps(res, ensure_ascii=False, indent=1))
    if out_path:
        with open(out_path, "w", encoding="utf-8") as fp:
            json.dump(res, fp, ensure_ascii=False, indent=1)
    return res


# ── 브리핑 게시 (서버 전용) ─────────────────────────────────────────────

RESULT_TYPE = "number_popularity"
ALGO = "popularity_pick"
PICK_SAMPLE = 200000
PICK_POOL_PCT = 5          # 인기도 하위 5% 안에서 고른다
PICK_MAX_OVERLAP = 2       # 추천 세트끼리 겹치는 번호 최대 개수
OFFICIAL_VERSION = "fr-1.0"


class Scorer:
    """저장된 전체 회차로 학습한 실전 인기도 점수기. 백분위·예상 1등 몫은 무작위 조합 기준."""

    def __init__(self, data, prev, seed):
        X = mat(data)
        y4 = np.log([r["R4"] for r in data])
        self.model = Model().fit(X, y4)
        lr1 = np.log([(r["r1"] + 0.5) / r["e1"] for r in data])
        self.b, self.a = (float(v) for v in np.polyfit(y4, lr1, 1))
        self.prev = prev
        self.lo, self.hi = np.quantile(X, 0.01, axis=0), np.quantile(X, 0.99, axis=0)
        self.lam = float(np.mean([r["e1"] for r in data[-52:]]))   # 최근 1년 회차당 기대 1등 수
        gen = np.random.default_rng(seed)
        self.sample = [sorted(int(v) for v in gen.choice(np.arange(1, 46), 6, replace=False)) for _ in range(PICK_SAMPLE)]
        self.sx = np.array([[features(c, prev)[k] for k in FEATURES] for c in self.sample], float)
        self.sp = self.model.predict(self.sx)
        self.sorted = np.sort(self.sp)
        self.mean = float(np.mean(self.sp))
        self.m_rand = float(np.mean([self._share(p) for p in self.sp[:20000]]))

    def _share(self, p):
        return share_multiplier(math.exp(self.b * (p - self.mean)), self.lam)

    def score(self, st):
        p = float(self.model.predict(np.array([[features(st, self.prev)[k] for k in FEATURES]], float))[0])
        pct = 100.0 * float(np.searchsorted(self.sorted, p)) / len(self.sorted)
        return {"set": sorted(int(n) for n in st), "popularity_pct": round(pct, 1),
                "share_vs_random": round(self._share(p) / self.m_rand, 3)}

    def picks(self, past_combos, n=5):
        inside = np.all((self.sx >= self.lo) & (self.sx <= self.hi), axis=1)
        cut = np.percentile(self.sp, PICK_POOL_PCT)
        order = [i for i in np.argsort(self.sp) if inside[i] and self.sp[i] <= cut]
        out, seen = [], set()
        for i in order:
            c = tuple(self.sample[i])
            if c in seen or c in past_combos:
                continue
            seen.add(c)
            if all(len(set(c) & set(o)) <= PICK_MAX_OVERLAP for o in out):
                out.append(list(c))
            if len(out) == n:
                break
        return out


def sales_deadline(draw_date, rnd):
    try:
        d = datetime.strptime(str(draw_date)[:10].replace(".", "-"), "%Y-%m-%d")
    except ValueError:
        d = datetime(2002, 12, 7) + timedelta(days=7 * (rnd - 1))
    d = d + timedelta(days=7)
    return datetime(d.year, d.month, d.day, 11, tzinfo=timezone.utc)   # 토 20:00 KST


def publish(url, key, dry_run=False):
    db = Db(url, key)
    base = url.rstrip("/") + "/rest/v1/"

    def get(t, params):
        r = requests.get(base + t, params=params, headers=db.h, timeout=60)
        r.raise_for_status()
        return r.json()

    validation = run(db)
    data = load_rounds(db)
    wins = db.select_all("lotto_winning_numbers", {"select": "round,draw_date,num1,num2,num3,num4,num5,num6", "order": "round.asc"})
    w = wins[-1]
    target = w["round"] + 1
    prev = [w[f"num{i}"] for i in range(1, 7)]
    past = {tuple(sorted(x[f"num{i}"] for i in range(1, 7))) for x in wins}
    deadline = sales_deadline(w["draw_date"], w["round"])
    now = datetime.now(timezone.utc)
    if data[-1]["round"] != w["round"]:
        print(f"{target}회 대기 — {w['round']}회 당첨자 수 미수집 (저장된 최신 {data[-1]['round']}회). 저장·등록하지 않음")
        return None
    from research_release import prediction_allowed
    ok, reason, _ = prediction_allowed(get, target, w["draw_date"], w["round"])
    if not ok:
        print(f"{target}회 {reason} — 저장·등록하지 않음")
        return None
    sc = Scorer(data, prev, seed=SEED + target)

    off = get("research_results", {"select": "training_end_round,payload->sets", "research_type": "eq.final_recommendation",
                                   "model_version": f"eq.{OFFICIAL_VERSION}", "target_round": f"eq.{target}",
                                   "training_end_round": f"eq.{w['round']}", "limit": "1"})
    official = [sc.score(st) for st in (off[0].get("sets") or [])] if off else []

    reg = get("research_predictions", {"select": "sets", "algorithm": f"eq.{ALGO}", "version": f"eq.{VERSION}",
                                       "target_round": f"eq.{target}"})
    registered = bool(reg)
    if registered:
        picks_sets = reg[0]["sets"]
    elif validation["passed"]:
        picks_sets = sc.picks(past)
    else:
        picks_sets = []
    status = "registered" if registered else ("none" if not picks_sets else ("pending" if now < deadline else "late"))

    if not dry_run and not registered and picks_sets and now < deadline:
        db.upsert("research_predictions", [{
            "algorithm": ALGO, "version": VERSION, "target_round": target, "data_end_round": data[-1]["round"],
            "sets": picks_sets, "generated_at": now.isoformat(), "deadline_at": deadline.isoformat(),
            "pre_deadline": True, "locked": True, "status": "pending"}],
            on_conflict="algorithm,version,target_round", ignore_duplicates=True)
        reg = get("research_predictions", {"select": "sets", "algorithm": f"eq.{ALGO}", "version": f"eq.{VERSION}",
                                           "target_round": f"eq.{target}"})
        if reg:
            picks_sets, status = reg[0]["sets"], "registered"

    payload = {
        "version": VERSION, "target_round": target, "training": [data[0]["round"], data[-1]["round"]],
        "validation": {k: validation[k] for k in ("train", "test", "n_test", "test_spearman", "test_ci95", "gates",
                                                  "passed", "rank1_actual_over_expected", "share_multiplier")},
        "official": official,
        "official_training_end": off[0]["training_end_round"] if off else None,
        "picks": [sc.score(st) for st in picks_sets],
        "picks_status": status,   # registered | pending(드라이런) | late(마감 후 — 등록 안 함) | none(검증 미통과)
        "pick_rule": f"무작위 {PICK_SAMPLE:,}개 중 학습 범위 안 · 인기도 하위 {PICK_POOL_PCT}% · "
                     f"서로 {PICK_MAX_OVERLAP + 1}개 이상 겹침 금지 · 과거 1등 조합 제외",
        "lambda_rank1": round(sc.lam, 2),
        "deadline_at": deadline.isoformat(),
        "generated_at": now.isoformat(),
    }
    print(json.dumps({k: payload[k] for k in ("target_round", "training", "official", "picks", "picks_status")},
                     ensure_ascii=False))
    if dry_run:
        print("드라이런 — DB에 쓰지 않음")
        return payload
    db.upsert("research_results", [{"research_type": RESULT_TYPE, "model_version": VERSION,
                                    "training_end_round": data[-1]["round"], "target_round": target, "payload": payload}],
              on_conflict="research_type,model_version,training_end_round,target_round")
    print(f"{target}회 인기도 브리핑 저장 · 추천 5세트 {status}")
    return payload


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    ap.add_argument("--sets", help='점수를 볼 조합 JSON, 예: "[[1,2,3,4,5,6]]"')
    ap.add_argument("--publish", action="store_true", help="브리핑 게시 (서버 전용)")
    ap.add_argument("--dry-run", action="store_true", help="--publish 계산만, DB 쓰기 없음")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다")
    if a.publish:
        if not a.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
            sys.exit("--publish 는 서버(GitHub Actions)에서만 저장합니다. 로컬은 --dry-run 만 허용")
        publish(url, key, a.dry_run)
        return
    run(Db(url, key), a.out, json.loads(a.sets) if a.sets else None)


if __name__ == "__main__":
    main()
