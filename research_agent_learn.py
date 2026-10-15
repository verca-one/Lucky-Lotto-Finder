"""
지방장 판매점 보정 학습 (ag-1.2-learn) — 과거 빈도 대비 개선을 직접 목표로 학습하는 판매점 1등 예측 모델

설계
  · 지방장 238명의 데이터를 하나로 모아(교류) 전국 공통 보정 모델을 학습한다. 지역별로 따로 하지 않는다.
  · 대상: 회차 t 에 판매점 s 에서 1등이 나왔는가 (판매점 단위)
  · 특징 (모두 t-1 회차까지의 정보만 사용):
      과거 1·2등 감쇠 빈도(장기·단기) · 마지막 1등 이후 경과 · 평균 당첨 간격 대비 현재 위치(주기)
      · 직전/최근 5회 본인 1·2등 · 인접(1km/3km) 판매점 최근 1·2등(공간전이) · 같은 지역 최근 1등·추세
      · 같은 시·도 직전 1등 · 지역 내 판매점 수
  · 순방향(walk-forward): 회차 t 예측 모델은 t-1 까지로만 학습. 10회차마다 다시 학습(확장 창).
  · 평가: 각 지방장이 자기 지역 판매점을 모델 점수로 순위 → TOP1/3/5 1등 적중
           vs 현재 실전 예측(ag-1.1 동결 TOP5 = 과거 빈도) vs 지역 내 무작위 기대
  · 실전 반영 기준(평가 전 고정): 1000~1245회 TOP5 적중 차이(모델 − ag-1.1)의 부트스트랩 95% 하한 > 0,
    전·후반 모두 차이 ≥ 0, 예측 로그손실이 기준 모델보다 낮음. 미달이면 실전 예측은 그대로(과거 빈도).

판매량 분모가 없으므로 판매점별 한 장당 당첨확률 우위를 주장하지 않는다 (순위 적중 개선만 평가).
외부 사이트 접속 없음 — DB 저장 데이터만 읽는다.

사용: python research_agent_learn.py [--from 1000] [--to 1245] [--out result.json]
"""

import argparse
import json
import math
import os
import sys
import time
from collections import defaultdict

import numpy as np

import research_agent_worker as W
from research_agent_worker import Universe, load, NEIGH_KM
from research_region_worker import Db, log

MODEL = "ag-1.2-learn"
REFIT_EVERY = 10
NEG_RATE = 0.02            # 학습 음성 표본 비율 (가중치로 보정)
L2 = 1.0
TRAIN_FROM_ROW = 60        # 데이터 시작 후 60회차부터 학습 행으로 사용
SEED = 20261015
H_LONG, H_SHORT, H_VLONG = 150.0, 30.0, 600.0

FEATURES = [
    "log_first_long", "log_first_short", "log_event_long", "log_second_short", "first_total_log",
    "never_first", "since_first_log", "cycle_pos", "cycle_known",
    "self_event_1", "self_event_5",
    "near1_event_1", "near1_event_5", "near3_event_1", "near3_event_5",
    "region_first_1", "region_first_10", "region_trend", "sido_first_1",
    "log_region_stores",
]
BASE_FEATURES = ["log_first_long", "log_event_long", "log_region_stores"]
# 빈도 확장 특징 (변형 시험용)
FREQ_EXTRA = ["log_first_vlong", "log_event_vlong", "event_total_log", "log_second_long"]
ALL_FEATURES = FEATURES + FREQ_EXTRA

# ── 변형 시험 (평가 전에 고정, 2026-10-15) ─────────────────────────
#  선택: 1000~1122회 TOP5 적중(모델 − ag-1.1)이 가장 큰 변형 (동률이면 로그손실)
#  확인: 선택한 변형 하나만 1123~1245회에서 1회 확인 — 부트스트랩 95% 하한 > 0 · 로그손실 개선
FREQ_SET = ["log_first_long", "log_first_short", "log_event_long", "log_second_short", "first_total_log",
            "log_region_stores"] + FREQ_EXTRA
VARIANTS = {
    "V0_all_signals": {"cols": FEATURES, "inter": [], "small": []},
    "V1_frequency": {"cols": FREQ_SET, "inter": [], "small": []},
    "V2_frequency_interactions": {"cols": FREQ_SET + ["cycle_pos", "near3_event_5", "region_first_10"],
                                  "inter": [("cycle_pos", "first_total_log"), ("near3_event_5", "log_event_long"),
                                            ("region_first_10", "log_event_long")], "small": []},
    "V3_frequency_small_region": {"cols": FREQ_SET, "inter": [],
                                  "small": ["log_first_long", "log_event_long", "log_event_vlong", "event_total_log"]},
    "V4_frequency_all_signals": {"cols": FEATURES + FREQ_EXTRA, "inter": [], "small": []},
}
SMALL_REGION_LOG = math.log(30)   # 판매점 30곳 미만 지역


def design(Xall, variant):
    """변형별 설계 행렬 (열 선택 + 곱 조합 + 소규모 지역 보정)"""
    v = VARIANTS[variant]
    idx = {f: i for i, f in enumerate(ALL_FEATURES)}
    parts = [Xall[:, [idx[c] for c in v["cols"]]]]
    for a, b in v["inter"]:
        parts.append((Xall[:, idx[a]] * Xall[:, idx[b]])[:, None])
    if v["small"]:
        small = (Xall[:, idx["log_region_stores"]] < SMALL_REGION_LOG).astype(np.float32)
        parts.append(np.column_stack([Xall[:, idx[c]] * small for c in v["small"]] + [small]))
    return np.hstack(parts).astype(np.float32)


def design_names(variant):
    v = VARIANTS[variant]
    names = list(v["cols"]) + [f"{a}×{b}" for a, b in v["inter"]]
    if v["small"]:
        names += [f"{c}×소규모지역" for c in v["small"]] + ["소규모지역"]
    return names


class FeatureBuilder:
    """회차 행 ti 직전까지의 누적 상태를 순차로 갱신하며 특징 행렬을 만든다"""

    def __init__(self, u):
        self.u = u
        S = u.S
        self.gl, self.gs = 0.5 ** (1 / H_LONG), 0.5 ** (1 / H_SHORT)
        self.df_l = np.zeros(S); self.df_s = np.zeros(S)
        self.de_l = np.zeros(S); self.d2_s = np.zeros(S)
        self.cnt_first = np.zeros(S)
        self.gv = 0.5 ** (1 / H_VLONG)
        self.df_v = np.zeros(S); self.de_v = np.zeros(S); self.d2_l = np.zeros(S); self.cnt_event = np.zeros(S)
        self.first_row = np.full(S, -1)
        self.last_row = np.full(S, -1)
        self.reg_dl = np.zeros(u.U); self.reg_ds = np.zeros(u.U)
        self.ti = 0
        # 지역·시도 매핑
        self.st_reg = u.st_reg
        sidos = sorted({a.split("|")[0] for a in u.reg_ids})
        self.sido_idx = {s: i for i, s in enumerate(sidos)}
        self.reg_sido = np.array([self.sido_idx[a.split("|")[0]] for a in u.reg_ids])
        self.n_reg_stores = np.array([len(u.members[u.aidx[r]]) for r in u.reg_ids], float)

    def advance_to(self, ti):
        """상태를 회차 행 ti 직전(= ti-1 까지 반영)으로 진행"""
        u = self.u
        while self.ti < ti:
            r = self.ti
            F, E = u.F[r].astype(float), u.E[r].astype(float)
            self.df_l = self.df_l * self.gl + F
            self.df_s = self.df_s * self.gs + F
            self.de_l = self.de_l * self.gl + E
            self.d2_s = self.d2_s * self.gs + (E - F).clip(0)
            self.cnt_first += F
            self.df_v = self.df_v * self.gv + F
            self.de_v = self.de_v * self.gv + E
            self.d2_l = self.d2_l * self.gl + (E - F).clip(0)
            self.cnt_event += E
            hit = F > 0
            self.first_row[hit & (self.first_row < 0)] = r
            self.last_row[hit] = r
            rf = u.RFc[r].astype(float)
            self.reg_dl = self.reg_dl * self.gl + rf
            self.reg_ds = self.reg_ds * self.gs + rf
            self.ti += 1

    def features(self, ti):
        """회차 행 ti 예측용 특징 (모든 판매점)"""
        self.advance_to(ti)
        u = self.u
        S = u.S
        X = np.zeros((S, len(ALL_FEATURES)), np.float32)
        since = np.where(self.last_row >= 0, ti - self.last_row, 0).astype(float)
        never = self.last_row < 0
        gaps_known = self.cnt_first >= 3
        mean_gap = np.where(gaps_known, (self.last_row - self.first_row) / np.maximum(self.cnt_first - 1, 1), 1.0)
        cyc = np.where(gaps_known, np.clip(since / np.maximum(mean_gap, 1.0), 0, 5), 0.0)
        lo, hi1 = max(ti - 5, 0), ti
        e1 = u.E[ti - 1].astype(float) if ti >= 1 else np.zeros(S)
        e5 = u.E[lo:hi1].sum(0).astype(float)
        reg = self.st_reg
        has_reg = reg >= 0
        rr = np.clip(reg, 0, u.U - 1)
        rf1 = u.RFc[ti - 1].astype(float) if ti >= 1 else np.zeros(u.U)
        rf10 = u.RFc[max(ti - 10, 0):ti].sum(0).astype(float)
        trend = np.log1p(self.reg_ds * (H_LONG / H_SHORT)) - np.log1p(self.reg_dl)
        sido_rf1 = np.zeros(len(self.sido_idx))
        np.add.at(sido_rf1, self.reg_sido, (rf1 > 0).astype(float))
        cols = {
            "log_first_long": np.log1p(self.df_l), "log_first_short": np.log1p(self.df_s),
            "log_event_long": np.log1p(self.de_l), "log_second_short": np.log1p(self.d2_s),
            "first_total_log": np.log1p(self.cnt_first), "never_first": never.astype(float),
            "since_first_log": np.where(never, 0.0, np.log1p(since)), "cycle_pos": cyc, "cycle_known": gaps_known.astype(float),
            "self_event_1": e1, "self_event_5": np.minimum(e5, 3),
            "region_first_1": np.where(has_reg, (rf1[rr] > 0).astype(float), 0),
            "region_first_10": np.where(has_reg, np.log1p(rf10[rr]), 0),
            "region_trend": np.where(has_reg, trend[rr], 0),
            "sido_first_1": np.where(has_reg, np.log1p(sido_rf1[self.reg_sido[rr]]), 0),
            "log_region_stores": np.where(has_reg, np.log(np.maximum(self.n_reg_stores[rr], 1)), 0),
            "log_first_vlong": np.log1p(self.df_v), "log_event_vlong": np.log1p(self.de_v),
            "event_total_log": np.log1p(self.cnt_event), "log_second_long": np.log1p(self.d2_l),
        }
        for d in NEIGH_KM:
            key = f"near{int(d)}"
            if f"{key}_event_1" in FEATURES:
                ne = u.NE[d]
                cols[f"{key}_event_1"] = ne[ti - 1].astype(float) if ti >= 1 else np.zeros(S)
                cols[f"{key}_event_5"] = np.minimum(ne[lo:hi1].sum(0), 3).astype(float)
        for j, f in enumerate(ALL_FEATURES):
            X[:, j] = cols.get(f, 0.0)
        return X


def fit_logistic(X, y, w, l2=L2, iters=50):
    """가중 L2 로지스틱 회귀 (뉴턴법 + 단계 축소 선탐색). 절편 포함, 특징은 표준화해서 학습.
    가중치는 평균 1로 정규화해 수치 안정성을 확보한다 (음성 표본 보정 비율은 유지)."""
    mu, sd = X.mean(0), X.std(0)
    sd[sd < 1e-6] = 1.0
    Z = np.hstack([np.ones((len(X), 1)), (X - mu) / sd])
    w = w / w.mean()
    reg = np.full(Z.shape[1], l2); reg[0] = 0
    pbar = float(np.clip(np.average(y, weights=w), 1e-6, 1 - 1e-6))
    beta = np.zeros(Z.shape[1]); beta[0] = math.log(pbar / (1 - pbar))

    def loss(b):
        eta = Z @ b
        return float(np.sum(w * (np.logaddexp(0, eta) - y * eta)) + 0.5 * np.sum(reg * b * b))

    cur = loss(beta)
    converged = False
    for _ in range(iters):
        p = 1 / (1 + np.exp(-np.clip(Z @ beta, -35, 35)))
        g = Z.T @ (w * (p - y)) + reg * beta
        Hm = (Z * (w * p * (1 - p))[:, None]).T @ Z + np.diag(reg) + 1e-8 * np.eye(Z.shape[1])
        step = np.linalg.solve(Hm, g)
        t = 1.0
        while t > 1e-6:
            nb = beta - t * step
            nl = loss(nb)
            if nl <= cur:
                break
            t *= 0.5
        if t <= 1e-6:
            break
        beta, prev, cur = nb, cur, nl
        if prev - cur < 1e-9 * max(1.0, abs(prev)):
            converged = True
            break
    p = 1 / (1 + np.exp(-np.clip(Z @ beta, -35, 35)))
    Hm = (Z * (w * p * (1 - p))[:, None]).T @ Z + np.diag(reg)
    cov = np.linalg.pinv(Hm)
    return {"beta": beta, "mu": mu, "sd": sd, "se": np.sqrt(np.maximum(np.diag(cov), 0)), "converged": converged}


def score(m, X):
    Z = np.hstack([np.ones((len(X), 1)), (X - m["mu"]) / m["sd"]])
    return Z @ m["beta"]


def run(db, a):
    t0 = time.time()
    raw = load(db)
    ready, _ = W.ready_latest(raw)
    latest = min(ready, a.to)
    u = Universe(raw, latest)
    log(f"[learn] 판매점 {u.S} · 지방장 {len(u.agent_ids)} · 회차 행 {u.R} ({u.r0}~{latest})")
    fb = FeatureBuilder(u)
    rng = np.random.default_rng(SEED)
    reg_agents = [a_ for a_ in range(len(u.agent_ids)) if u.agent_ids[a_] != "internet"]
    cols = [ALL_FEATURES.index(f) for f in BASE_FEATURES]
    variant = getattr(a, "variant", "V0_all_signals")
    eval_to = getattr(a, "eval_to", None) or 10 ** 6

    # ag-1.1 실전 예측(동결 TOP5) 적중 — 복기 기록에서 지방장별 h=[TOP1,TOP3,TOP5]
    ag11 = {}
    for r in db.select_all("research_review_agent_rounds", {"select": "target_round,agent_ids,entries",
                                                            "review_version": "eq.rv-1.0", "order": "target_round"}, page=25):
        ag11[r["target_round"]] = {ag: e.get("h", [0, 0, 0]) for ag, e in zip(r["agent_ids"], r["entries"])}
    log(f"[learn] ag-1.1 복기 {len(ag11)}회차 로드")

    Xs, XBs, ys, ws = [], [], [], []          # 학습 표본 (회차별 누적)
    first_eval = u.row(a.frm)
    model = base = None
    per_round = []
    coef_hist = []
    for ti in range(TRAIN_FROM_ROW, u.R):
        t = int(u.rounds[ti])
        if t > eval_to:
            break
        Xall = fb.features(ti)
        X = design(Xall, variant)
        y = u.F[ti].astype(float)
        if ti >= first_eval and u.valid[ti]:
            if model is None or (ti - first_eval) % REFIT_EVERY == 0:
                Xa, ya, wa = np.vstack(Xs), np.concatenate(ys), np.concatenate(ws)
                model = fit_logistic(Xa, ya, wa)
                base = fit_logistic(XBa := np.vstack(XBs), ya, wa)
                coef_hist.append({"refit_round": t, "train_rows": int(len(ya)), "train_pos": int(ya.sum()), "converged": bool(model["converged"] and base["converged"])})
            s_m = score(model, X)
            s_b = score(base, Xall[:, cols])
            # 로그손실 (지역 배정 판매점)
            mask = u.st_agent >= 0
            pm = 1 / (1 + np.exp(-s_m[mask])); pb = 1 / (1 + np.exp(-s_b[mask])); yy = y[mask]
            llm = float(-np.sum(yy * np.log(pm + 1e-12) + (1 - yy) * np.log(1 - pm + 1e-12)))
            llb = float(-np.sum(yy * np.log(pb + 1e-12) + (1 - yy) * np.log(1 - pb + 1e-12)))
            hm = np.zeros(3); hb = np.zeros(3); h11 = np.zeros(3); ex = np.zeros(3)
            for a_ in reg_agents:
                mem = u.members[a_]
                n = len(mem)
                if n == 0:
                    continue
                wins = y[mem]
                if wins.sum() == 0:
                    pass
                om = mem[np.lexsort((-s_b[mem], -s_m[mem]))]
                ob = mem[np.argsort(-s_b[mem], kind="stable")]
                for j, k in enumerate((1, 3, 5)):
                    hm[j] += y[om[:k]].sum(); hb[j] += y[ob[:k]].sum()
                    ex[j] += min(k, n) / n * wins.sum()
                h = ag11.get(t, {}).get(u.agent_ids[a_])
                if h:
                    h11 += np.array(h)
            per_round.append({"t": t, "model": hm.tolist(), "base": hb.tolist(), "ag11": h11.tolist(), "uniform": ex.tolist(),
                              "ll_model": llm, "ll_base": llb, "has_ag11": t in ag11})
        # 학습 표본 추가 (예측 후 → 다음 회차 학습에만 쓰임: 미래 정보 유입 없음)
        if u.valid[ti]:
            pos = np.where(y == 1)[0]
            neg = np.where((y == 0) & (rng.random(u.S) < NEG_RATE))[0]
            idx = np.concatenate([pos, neg])
            Xs.append(X[idx]); XBs.append(Xall[idx][:, cols]); ys.append(y[idx])
            ws.append(np.concatenate([np.ones(len(pos)), np.full(len(neg), 1 / NEG_RATE)]))
    # 최종 계수 (전체 학습)
    Xa, ya, wa = np.vstack(Xs), np.concatenate(ys), np.concatenate(ws)
    final = fit_logistic(Xa, ya, wa)
    out = summarize(per_round, final, coef_hist, latest, time.time() - t0, design_names(variant))
    out["variant"] = variant
    return out


def summarize(per_round, final, coef_hist, latest, elapsed, names=FEATURES):
    R = [p for p in per_round if p["has_ag11"]]
    M = np.array([p["model"] for p in R]); B = np.array([p["base"] for p in R]); A = np.array([p["ag11"] for p in R])
    U = np.array([p["uniform"] for p in R])
    diff5 = M[:, 2] - A[:, 2]
    rng = np.random.default_rng(SEED)
    boots = [diff5[rng.integers(0, len(diff5), len(diff5))].sum() for _ in range(2000)]
    lo, hi = np.percentile(boots, [2.5, 97.5])
    half = len(R) // 2
    llm = sum(p["ll_model"] for p in R); llb = sum(p["ll_base"] for p in R)
    gate = bool(lo > 0 and diff5[:half].sum() >= 0 and diff5[half:].sum() >= 0 and llm < llb)
    coefs = [{"feature": f, "coef": float(final["beta"][j + 1]), "se": float(final["se"][j + 1]),
              "z": float(final["beta"][j + 1] / final["se"][j + 1]) if final["se"][j + 1] > 0 else None}
             for j, f in enumerate(names)]
    coefs.sort(key=lambda c: -abs(c["z"] or 0))
    return {
        "model": MODEL, "rounds": [R[0]["t"], R[-1]["t"]] if R else None, "n_rounds": len(R), "latest": latest,
        "hits": {"model": M.sum(0).tolist(), "ag11_live": A.sum(0).tolist(), "frequency_baseline": B.sum(0).tolist(),
                 "uniform_expected": [round(x, 1) for x in U.sum(0).tolist()]},
        "top5_diff_vs_ag11": {"total": int(diff5.sum()), "ci95": [float(lo), float(hi)],
                              "first_half": int(diff5[:half].sum()), "second_half": int(diff5[half:].sum())},
        "logloss": {"model": round(llm, 2), "base": round(llb, 2), "improvement": round(llb - llm, 2)},
        "gate_pass": gate,
        "gate_rule": "TOP5 적중 차이(모델−ag-1.1) 부트스트랩 95% 하한 > 0 · 전반·후반 차이 ≥ 0 · 로그손실 개선",
        "coefficients": coefs, "refits": len(coef_hist), "refits_converged": sum(1 for c in coef_hist if c["converged"]), "elapsed_sec": round(elapsed, 1),
        "per_round_tail": per_round[-5:],
    }


def protocol(db, out_path=None):
    """변형 선택(1000~1122) → 선택 변형 1개만 확인(1123~1245)"""
    sel = {}
    for v in VARIANTS:
        r = run(db, argparse.Namespace(frm=1000, to=10 ** 6, eval_to=1122, variant=v))
        sel[v] = {"top5_diff": r["top5_diff_vs_ag11"]["total"], "hits": r["hits"]["model"],
                  "ag11": r["hits"]["ag11_live"], "logloss_gain": r["logloss"]["improvement"], "converged": r["refits_converged"],
                  "refits": r["refits"]}
        log(f"[select] {v}: TOP5 차이 {sel[v]['top5_diff']} · 로그손실 개선 {sel[v]['logloss_gain']}")
    best = max(sel, key=lambda v: (sel[v]["top5_diff"], sel[v]["logloss_gain"]))
    conf = run(db, argparse.Namespace(frm=1123, to=10 ** 6, eval_to=10 ** 6, variant=best))
    report = {"protocol": "선택 1000~1122회 → 확인 1123~1245회 (선택 변형 1개만, 사전 고정 규칙)",
              "selection": sel, "chosen": best,
              "confirmation": {k: conf[k] for k in ("rounds", "n_rounds", "hits", "top5_diff_vs_ag11", "logloss", "gate_pass",
                                                     "coefficients", "refits", "refits_converged")}}
    if out_path:
        json.dump(report, open(out_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="frm", type=int, default=1000)
    ap.add_argument("--to", type=int, default=10 ** 6)
    ap.add_argument("--variant", default="V0_all_signals", choices=list(VARIANTS))
    ap.add_argument("--protocol", action="store_true", help="변형 선택(1000~1122) → 1개 확인(1123~1245)")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    a.eval_to = None
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        print("SUPABASE_URL / SUPABASE_KEY 환경변수 필요"); sys.exit(1)
    db = Db(url, key)
    if key.startswith("sb_"):
        db.h.pop("Authorization", None)
    if a.protocol:
        rep_ = protocol(db, a.out)
        print(json.dumps({k: v for k, v in rep_.items()}, ensure_ascii=False, indent=1))
        return
    res = run(db, a)
    out = {k: v for k, v in res.items() if k != "per_round_tail"}
    print(json.dumps(out, ensure_ascii=False, indent=1))
    if a.out:
        json.dump(res, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
