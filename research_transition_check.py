"""
전이 가설 재검증 (tc-1.0) — 판매점 1등 기록 시작(262회)부터, 발견·확인 구간을 반으로 나눠 다시 검정한다

결과를 보기 전에 고정한 규칙
  A. 지역 쌍 재검정 (기존 rg-1.0 과 같은 형태: 'A 지역 1등 → h회 안에 B 지역 1등이 더 나온다')
     · 지역 = 시·군·구 (인터넷 판매 제외, 좌표 있는 로또 판매점 기준)
     · 발견 262~754회: 모든 순서쌍(A≠B) × h=1~6, A 조건 회차 15회 이상 · 기대 3 이상만
       단측 이항검정 → BH(FDR 5%) 통과 쌍 + 명목 p 상위 50쌍을 후보로
     · 확인 755~1246회: 후보만 같은 검정 → 후보끼리 BH(5%) 통과 = 재현
     · 우연 기준: 발견 검정 수 × 0.001 = 아무 관계 없어도 명목 p<0.001 로 나올 개수
     · 회귀 확인: 후보들의 발견 배수 평균 vs 확인 배수 평균 (진짜 효과면 확인에서도 1보다 커야 함)
  B. 묶음 검정 (쌍을 하나하나 안 보고 '전이라는 현상이 있나'를 통째로 — 검정 수가 적어 검정력이 크다)
     · 기대 = 회차마다 그 회차 1등 수 × 지역 몫(1·2등 사건 반감기 150회 감쇠 누적, 그 회차 직전까지)
       → 판매량·지역 성장 같은 공통 추세는 기대에 흡수
     · 조건 지역(회차 t 기준, t 직전 h회 안 사건):
         self   : 자기 지역에서 1등            (자기 반복)
         near10 : 다른 지역 1등이 중심 거리 10km 안 (자기 지역 제외)
         near30 : 다른 지역 1등이 중심 거리 30km 안 (자기 지역 제외)
         sido   : 같은 시·도 다른 지역에서 1등 (자기 지역 제외)
       × h = 1, 3, 6 → 12개 검정, BH(5%). 실제÷기대 배수와 전·후반(262~754 / 755~1246) 각각도 표시.
결과는 '경향'에 관한 것이며 복권 한 장의 1등 확률을 바꾸지 않는다.
읽기 전용: lottery_stores · winning_history (크롤링 테이블은 읽기만). DB 쓰기 없음. 외부 사이트 접속 없음.

사용: python research_transition_check.py [--out result.json]
"""

import argparse
import json
import math
import os
import sys

import numpy as np
from scipy.stats import binom

import research_review_worker as R
import research_store_hypotheses as H

VERSION = "tc-1.0"
START = 262
SPLIT = 754          # 발견 262~754 · 확인 755~
LAGS = range(1, 7)
MIN_N = 15
MIN_EXP = 3.0
TOP_NOMINAL = 50
POOL_LAGS = (1, 3, 6)


def bh(p):
    p = np.asarray(p, float)
    n = len(p)
    if n == 0:
        return p
    o = np.argsort(p)
    q = p[o] * n / np.arange(1, n + 1)
    q = np.minimum.accumulate(q[::-1])[::-1]
    out = np.empty(n)
    out[o] = np.minimum(q, 1)
    return out


def p_up(k, n, p0):
    return float(binom.sf(k - 1, n, p0)) if k > 0 else 1.0


def load(db):
    latest = db.get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})[0]["round"]
    sd = H.StoreData(db, latest)
    st = db.all("lottery_stores", {"select": "dhlottery_code,latitude,longitude", "lottery_type": "eq.lotto",
                                   "latitude": "not.is.null", "order": "dhlottery_code"}, key="dhlottery_code")
    assert [s["dhlottery_code"] for s in st] == sd.codes
    lat = np.array([s["latitude"] for s in st], float)
    lng = np.array([s["longitude"] for s in st], float)
    return latest, sd, lat, lng


def region_tables(sd, lat, lng):
    U = sd.n_regions
    reg = sd.region_of
    cnt = np.bincount(reg, minlength=U).astype(float)
    cy = np.bincount(reg, weights=lat, minlength=U) / np.maximum(cnt, 1)
    cx = np.bincount(reg, weights=lng, minlength=U) / np.maximum(cnt, 1)
    y, x = cy * 111.0, cx * 111.0 * math.cos(math.radians(36.5))
    dist = np.sqrt((y[:, None] - y[None, :]) ** 2 + (x[:, None] - x[None, :]) ** 2)
    return U, dist


def region_names(db, sd):
    st = db.all("lottery_stores", {"select": "dhlottery_code,region,address", "lottery_type": "eq.lotto",
                                   "latitude": "not.is.null", "order": "dhlottery_code"}, key="dhlottery_code")
    keys = [H.region_key(s.get("address"), s.get("region")) for s in st]
    uniq = sorted(set(keys))
    return uniq, [k.split("|")[0] if "|" in k else k for k in uniq]


def pair_test(X, rounds, lo, hi, pairs=None):
    """X: 회차×지역 1등 여부. 구간 [lo,hi] 에서 (a,b,h) → (n, k, p0, p)."""
    out = []
    idx = {r: i for i, r in enumerate(rounds)}
    sel = [i for i, r in enumerate(rounds) if lo <= r <= hi]
    pB = X[sel].mean(axis=0)
    for h in LAGS:
        src = [i for i in sel if rounds[i] + h <= hi and (rounds[i] + h) in idx]
        dst = [idx[rounds[i] + h] for i in src]
        A = X[src].astype(np.int32)
        B = X[dst].astype(np.int32)
        nA = A.sum(axis=0)
        K = A.T @ B
        if pairs is None:
            for a in np.where(nA >= MIN_N)[0]:
                for b in range(X.shape[1]):
                    if a == b or pB[b] <= 0 or nA[a] * pB[b] < MIN_EXP:
                        continue
                    out.append((int(a), int(b), h, int(nA[a]), int(K[a, b]), float(pB[b])))
        else:
            for (a, b, hh) in pairs:
                if hh == h and pB[b] > 0:
                    out.append((a, b, h, int(nA[a]), int(K[a, b]), float(pB[b])))
    return [(a, b, h, n, k, p0, p_up(k, n, p0)) for (a, b, h, n, k, p0) in out]


def part_a(sd, latest):
    rounds = list(range(max(START, sd.T0), latest + 1))
    U = sd.n_regions
    X = np.zeros((len(rounds), U), dtype=np.int8)
    for i, r in enumerate(rounds):
        w = np.nonzero(sd.first[sd.ti(r)])[0]
        X[i, sd.region_of[w]] = 1
    disc = pair_test(X, rounds, START, SPLIT)
    pv = np.array([t[6] for t in disc])
    qv = bh(pv)
    order = np.argsort(pv)
    cand = {i for i in order[:TOP_NOMINAL]} | set(np.where(qv < 0.05)[0].tolist())
    cand = sorted(cand, key=lambda i: pv[i])
    cpairs = [(disc[i][0], disc[i][1], disc[i][2]) for i in cand]
    conf = {(t[0], t[1], t[2]): t for t in pair_test(X, rounds, SPLIT + 1, latest, pairs=cpairs)}
    rows = []
    for i in cand:
        a, b, h, n, k, p0, p = disc[i]
        c = conf.get((a, b, h))
        rows.append({"a": a, "b": b, "h": h, "disc_n": n, "disc_k": k, "disc_lift": k / (n * p0), "disc_p": p,
                     "disc_q": float(qv[i]),
                     "conf_n": c[3] if c else 0, "conf_k": c[4] if c else 0, "conf_p0": c[5] if c else 0.0,
                     "conf_lift": (c[4] / (c[3] * c[5])) if c and c[3] * c[5] > 0 else None,
                     "conf_p": c[6] if c else 1.0})
    cq = bh([r["conf_p"] for r in rows])
    for r, q in zip(rows, cq):
        r["conf_q"] = float(q)
    lifts_c = [r["conf_lift"] for r in rows if r["conf_lift"] is not None]
    ok = [r for r in rows if r["conf_n"] > 0]
    return {
        "tests": len(disc), "chance_p001": round(len(disc) * 0.001, 1),
        "nominal_p001": int((pv < 0.001).sum()), "fdr_pass_discovery": int((qv < 0.05).sum()),
        "candidates": len(rows),
        "disc_lift_mean": float(np.mean([r["disc_lift"] for r in rows])) if rows else None,
        "conf_lift_mean": float(np.mean(lifts_c)) if lifts_c else None,
        "conf_lift_median": float(np.median(lifts_c)) if lifts_c else None,
        "conf_events": int(sum(r["conf_k"] for r in ok)),
        "conf_expected": float(sum(r["conf_n"] * r["conf_p0"] for r in ok)),
        "replicated_bh": int((cq < 0.05).sum()), "conf_nominal_p05": int(sum(1 for r in rows if r["conf_p"] < 0.05)),
        "rows": rows,
    }


def pooled(sd, latest, dist, sido_of):
    U = sd.n_regions
    reg = sd.region_of
    near10 = (dist <= 10) & ~np.eye(U, dtype=bool)
    near30 = (dist <= 30) & ~np.eye(U, dtype=bool)
    same_sido = (sido_of[:, None] == sido_of[None, :]) & ~np.eye(U, dtype=bool)
    lo = max(START + max(POOL_LAGS), sd.T0 + 1)
    acc = {}
    for t in range(lo, latest + 1):
        y = sd.first[sd.ti(t)].astype(bool)
        W = int(y.sum())
        if W == 0:
            continue
        b = sd.baseline(t)
        share = np.bincount(reg, weights=b, minlength=U)
        share = share / share.sum()
        obs = np.bincount(reg[y], minlength=U)
        half = 0 if t <= SPLIT else 1
        for h in POOL_LAGS:
            prev = np.zeros(U, bool)
            for tt in range(t - h, t):
                w = np.nonzero(sd.first[sd.ti(tt)])[0]
                prev[reg[w]] = True
            conds = {"self": prev,
                     "near10": (near10[:, prev].any(axis=1)) & ~prev,
                     "near30": (near30[:, prev].any(axis=1)) & ~prev,
                     "sido": (same_sido[:, prev].any(axis=1)) & ~prev}
            for name, m in conds.items():
                a = acc.setdefault((name, h), {"O": [0, 0], "E": [0.0, 0.0], "N": [0, 0]})
                a["O"][half] += int(obs[m].sum())
                a["E"][half] += W * float(share[m].sum())
                a["N"][half] += W
    out = []
    for (name, h), a in sorted(acc.items(), key=lambda kv: (kv[0][0], kv[0][1])):
        O, E, N = sum(a["O"]), sum(a["E"]), sum(a["N"])
        p = p_up(O, N, E / N) if N else 1.0
        out.append({"cond": name, "h": h, "O": O, "E": round(E, 1), "lift": round(O / E, 3) if E else None, "p": p,
                    "lift_first_half": round(a["O"][0] / a["E"][0], 3) if a["E"][0] else None,
                    "lift_second_half": round(a["O"][1] / a["E"][1], 3) if a["E"][1] else None})
    q = bh([r["p"] for r in out])
    for r, qq in zip(out, q):
        r["q"] = float(qq)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        print("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
        sys.exit(1)
    db = R.Db(url, key, dry=True)
    latest, sd, lat, lng = load(db)
    U, dist = region_tables(sd, lat, lng)
    uniq, sidos = region_names(db, sd)
    sido_idx = {s: i for i, s in enumerate(sorted(set(sidos)))}
    sido_of = np.array([sido_idx[s] for s in sidos])
    A = part_a(sd, latest)
    for r in A["rows"]:
        r["a_name"], r["b_name"] = uniq[r["a"]], uniq[r["b"]]
    B = pooled(sd, latest, dist, sido_of)
    res = {"version": VERSION, "rounds": [START, latest], "split": SPLIT, "regions": U, "pair": A, "pooled": B}
    print(f"== {VERSION} · {START}~{latest}회 · 지역 {U}곳 · 발견 {START}~{SPLIT} / 확인 {SPLIT + 1}~{latest}")
    print(f"[A] 쌍 검정 {A['tests']}개 · 우연 기준 p<0.001 {A['chance_p001']}개 · 실제 p<0.001 {A['nominal_p001']}개 · "
          f"발견 FDR 통과 {A['fdr_pass_discovery']}개")
    print(f"    후보 {A['candidates']}개: 발견 배수 평균 {A['disc_lift_mean']:.2f} → 확인 배수 평균 {A['conf_lift_mean']:.2f} "
          f"(중앙값 {A['conf_lift_median']:.2f}) · 확인 사건 {A['conf_events']} vs 기대 {A['conf_expected']:.1f}")
    print(f"    확인 재현: BH 통과 {A['replicated_bh']}개 · 명목 p<0.05 {A['conf_nominal_p05']}개 (우연이면 약 {A['candidates'] * 0.05:.1f}개)")
    for r in A["rows"][:8]:
        cl = f"{r['conf_lift']:.2f}" if r["conf_lift"] is not None else "-"
        print(f"    {r['a_name']} → {r['b_name']} (h{r['h']}): 발견 ×{r['disc_lift']:.2f} p{r['disc_p']:.1e} → 확인 ×{cl} p{r['conf_p']:.3f}")
    print("[B] 묶음 검정 (실제÷기대 · 전반/후반 · p · q)")
    for r in B:
        print(f"    {r['cond']:>6} h{r['h']}: {r['O']} vs {r['E']} ×{r['lift']} (전반 ×{r['lift_first_half']} · 후반 ×{r['lift_second_half']})"
              f" p {r['p']:.4f} q {r['q']:.4f}")
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False, indent=1, default=float)


if __name__ == "__main__":
    main()
