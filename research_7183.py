"""
7183 에이전트 (a7183-1.0) — 세는 쪽 · 조수(서버 계산) + 꿈꾸는 쪽(제미나이, 회차당 1번) + 번호 5세트(브리핑 ④)

  사장님 구상: 법칙은 한동안 유효하다가 몇 회차 뒤 다른 법칙으로 넘어간다(생태계). 목표는 하나 — 다음 회차 당첨.
  · 법칙(7183 본체가 꿈꾸는 것): 회차마다 숫자 하나를 내는 식 = [기본 값] · [회차 사이 계산] · [마무리].
      그 값이 일정 주기로 되풀이되거나(주기 1~5회), 정해 둔 순환(7→3→8→1 …)을 따라가면 '살아 있다'.
      살아 있는 법칙은 다음 회차 값(예: 맨 앞번호 끝수 = 7)을 예상한다.
  · 조수: 특정 숫자의 회차 간 패턴 — 'X 가 나오면 1~3회 뒤 Y 가 나온다'(넘어오는 숫자 · 이웃 숫자 포함) ·
      'Y 가 g 회 간격으로 나온다'. 지금 살아 있는 패턴이 가리키는 다음 회차 후보 숫자를 올린다.
      확실한 패턴(황금): 지금 연속 적중 중 + 과거 적중 30번 이상 · 우연의 2배 이상 + 숨겨 둔 최근 구간에서도 2배 이상.
  · 번호 5세트: 살아 있는 법칙의 예상 · 조수 후보를 가장 많이 만족하는 조합 (세트 간 2개까지 겹침 · 과거 1등 조합 제외).
  · 채점은 하나 — 다음 회차에 실제로 맞았는가. 우연이면 얼마나 맞았을지와 나란히 본다.
  · 꿈꾸는 쪽(2단계): 회차당 한 번 제미나이가 세는 쪽의 표를 읽고 ① 생태계 추리 ② 새 순환(숫자열) 최대 3개
      ③ 지금 살아 있는 법칙 중 믿는 것 최대 3개 ④ 다음 주의 자신에게 남기는 연구 노트를 낸다.
      새 순환은 순환 사전에 쌓여 다음 실행부터 서버가 전 회차에서 센다. 믿은 법칙은 다음 회차에 채점한다.
      제미나이가 실패한 날은 계산값만 저장하고(source = rule) 다음 실행에서 다시 시도. 판매 마감 뒤에는 만들지 않는다.
  · 법칙 완성: 순환이 과거 복기에서 30번 이상 예상해 우연의 1.5배 이상 맞히고(z ≥ 3), 등록 뒤 새 회차 10번 이상에서도
      우연보다 많이 맞히면 '완성' — 브리핑 알림용으로 저장한다.
  · 번호 5세트(3단계): 월요일 공개 시점(research_release) 이후 첫 실행에서 한 번 뽑아 사전 등록 장부에 올리고 고정한다
      (research_predictions · hypothesis_track · 7183-1.0 — 브리핑 ④ 제미나이 추천번호 자리를 대체, 회차 검증도 이 번호로 채점).
      그때까지 제미나이가 답했으면 믿는 법칙에 힘을 더 주고, 못 했으면 계산값으로 뽑는다. 등록 뒤에는 바꾸지 않는다 —
      제미나이가 주중에 늦게 답하면 추리 글만 더해지고, 새 순환은 다음 회차 번호부터 반영된다.
  읽기: lotto_winning_numbers (읽기 전용). 쓰기: research_results (agent_7183, 회차당 1건) · research_predictions (위 1건) — 서버만.
  비인기 · 공식 엔진 · 가설 트랙과 무관한 별도 파일.

사용: python research_7183.py [--from 1001] [--out 결과.json]     복기 표만 (저장 없음)
      python research_7183.py --dry-run                          이번 회차 흐름 전체 (저장 없음)
      python research_7183.py --publish [--force]                서버(GitHub Actions) 전용 — 저장
      환경변수 SUPABASE_URL, SUPABASE_KEY, (선택) GEMINI_API_KEY
"""

import argparse
import json
import math
import os
import re
import sys
import time
from datetime import date, datetime, timedelta, timezone

import numpy as np

import research_review_worker as R

VERSION = "a7183-1.0"
RESULT_TYPE = "agent_7183"
ROW_VERSION = "a7183"                     # 저장 행 키 (코드 버전이 올라가도 회차당 한 행을 유지)
REG_ALGO, REG_VERSION = "hypothesis_track", "7183-1.0"   # 브리핑 ④ 자리 — 회차 검증 · 당첨확인이 이 버전을 먼저 고른다
# 늦은 제미나이 번호(--late-sets) 장부 버전 — '7183' 으로 시작하지 않게 해서 회차 검증(pick_reg) · 앱 당첨확인이 월요일 등록본을 그대로 고른다
LATE_VERSION = "late-7183-1.0"
TRUST_BOOST = 2.0                         # 제미나이가 믿는다고 고른 법칙의 힘
DREAM_DEADLINE = 300                      # 초 — 제미나이 한 번 시도에 주는 시간
TEST_FROM = 1001           # 복기 시작 회차 (그 앞 회차는 기준값 계산에만 씀)
ALIVE_P = 1e-3             # 우연히 이만큼 이어질 확률이 이보다 작아야 '살아 있다'
MIN_RUN = 3
PERIODS = (1, 2, 3, 4, 5)
# 순환 사전의 씨앗 — 사장님의 7381 법칙. 7183 이 꿈꾼 순환이 여기에 쌓인다 (저장본 payload.cycles)
SEED_CYCLES = [{"name": "7381", "digits": [7, 3, 8, 1], "by": "seed", "registered_round": 0, "why": "사장님의 7381 법칙"}]
MAX_CYCLES, NEW_CYCLES, MAX_TRUST, SHOW_ALIVE = 30, 3, 3, 12
DONE_MIN_N, DONE_RATIO, DONE_Z, DONE_SINCE = 30, 1.5, 3.0, 10   # 법칙 완성 기준 (미리 고정)
KST = timezone(timedelta(hours=9))
SAMPLE = 20000
N_SETS, MAX_OVERLAP = 5, 2
LAW_TOP = 60               # 번호 고르기에 쓰는 살아 있는 법칙 수 (놀라운 순)
BASE_P = 6 / 45            # 숫자 하나가 한 회차에 나올 확률
LAGS = (1, 2, 3)
GAPS = tuple(range(2, 11))
ALIVE_STREAK = 3
GOLD_MIN_HITS, GOLD_RATIO, HOLDOUT_SHARE = 30, 2.0, 0.3


# ── 법칙 식 ────────────────────────────────────────────────────────
def bases(A):
    """조합(오름차순 6개) 여러 개 → 기본 값 이름별 배열"""
    A = np.asarray(A, dtype=np.int32)
    b = {}
    for i in range(6):
        b[f"{i + 1}번째 번호"] = A[:, i]
        b[f"{i + 1}번째 번호의 끝수"] = A[:, i] % 10
    b["6개 합"] = A.sum(1)
    b["끝수 합"] = (A % 10).sum(1)
    b["최대-최소"] = A[:, 5] - A[:, 0]
    b["홀수 개수"] = (A % 2).sum(1)
    b["1~22 개수"] = (A <= 22).sum(1)
    for i in range(5):
        b[f"{i + 2}번째-{i + 1}번째 차이"] = A[:, i + 1] - A[:, i]
    b["앞 두 번호 합"] = A[:, 0] + A[:, 1]
    b["뒤 두 번호 합"] = A[:, 4] + A[:, 5]
    b["맨 앞+맨 뒤"] = A[:, 0] + A[:, 5]
    return b


# (이름, 필요한 앞 회차 수, 계산) — 그 회차 값 cur 와 앞 회차 p1 · 앞앞 회차 p2
PAIRS = [
    ("그 회차 값", 0, lambda c, p1, p2: c),
    ("앞 회차 + 그 회차", 1, lambda c, p1, p2: c + p1),
    ("그 회차 - 앞 회차(크기)", 1, lambda c, p1, p2: np.abs(c - p1)),
    ("앞앞 회차 + 그 회차", 2, lambda c, p1, p2: c + p2),
    ("그 회차 - 앞앞 회차(크기)", 2, lambda c, p1, p2: np.abs(c - p2)),
]
POSTS = [("그대로", lambda v: v), ("자릿수 합", lambda v: np.where(v == 0, 0, (v - 1) % 9 + 1))]
for _k in range(2, 13):
    POSTS.append((f"{_k}로 나눈 나머지", lambda v, k=_k: v % k))
    POSTS.append((f"{_k}로 나눈 몫", lambda v, k=_k: v // k))
    POSTS.append((f"{_k}로 나누어떨어질 때의 몫", lambda v, k=_k: np.where(v % k == 0, v // k, -1)))


def formula_value(f, cur, p1, p2):
    """식 f = (기본 값 이름, 회차 사이 계산 번호, 마무리 번호) 의 값. 계산 못 하면 -1"""
    return POSTS[f[2]][1](PAIRS[f[1]][2](cur, p1, p2))


def formula_name(f):
    return f"{f[0]} · {PAIRS[f[1]][0]} · {POSTS[f[2]][0]}"


def build_formulas(hist):
    """모든 식의 회차별 값 V (식 수 × 회차 수). 값 흐름이 똑같은 식은 하나만 남긴다."""
    T = len(next(iter(hist.values())))
    out, seen = [], set()
    for bn, x in hist.items():
        p1 = np.concatenate([[0], x[:-1]])
        p2 = np.concatenate([[0, 0], x[:-2]])
        for pi, (_, lag, _fn) in enumerate(PAIRS):
            for qi in range(len(POSTS)):
                v = np.asarray(formula_value((bn, pi, qi), x, p1, p2), dtype=np.int32).copy()
                v[:lag] = -1
                key = v[2:].tobytes()
                if key in seen or len(set(v[2:].tolist())) < 3:   # 값이 한두 가지뿐인 식은 법칙으로 보지 않음
                    continue
                seen.add(key)
                out.append(((bn, pi, qi), v))
    F = [f for f, _ in out]
    V = np.stack([v for _, v in out])
    assert V.shape == (len(F), T)
    return F, V


def law_modes(V, base_cols, cycles):
    """법칙 방식별 (이어짐 E · 연속 횟수 run · 우연 확률 q · 필요한 연속 횟수 need · 예상값 함수)"""
    Fn, T = V.shape
    modes = {}

    def finish(name, E, pred):
        run = np.zeros((Fn, T), dtype=np.int16)
        for r in range(1, T):
            run[:, r] = np.where(E[:, r], run[:, r - 1] + 1, 0)
        q = E[:, 5:base_cols].mean(1)
        with np.errstate(divide="ignore", invalid="ignore"):
            need = np.ceil(math.log(ALIVE_P) / np.log(q))
        need = np.where((q > 0) & (q < 0.5), np.maximum(need, MIN_RUN), 10 ** 6)
        modes[name] = {"E": E, "run": run, "q": q, "need": need, "pred": pred}

    for L in PERIODS:
        E = np.zeros((Fn, T), dtype=bool)
        E[:, L:] = (V[:, L:] == V[:, :-L]) & (V[:, L:] >= 0)
        finish(f"주기 {L}회", E, lambda t, L=L: V[:, t - L])
    for cn, C in cycles.items():
        nxt = np.full(int(V.max()) + 2, -2, dtype=np.int32)
        for i, c in enumerate(C):
            nxt[c] = C[(i + 1) % len(C)]
        want = nxt[np.clip(V, 0, None)]
        want[V < 0] = -2
        E = np.zeros((Fn, T), dtype=bool)
        E[:, 1:] = V[:, 1:] == want[:, :-1]
        finish(f"순환 {cn}", E, lambda t, want=want: want[:, t - 1])
    return modes


def alive_laws(modes, t):
    """t 회차(열 번호)를 예상하는 살아 있는 법칙 — [(방식, 식 번호, 예상값, 놀라움, 연속 횟수)]"""
    out = []
    for name, m in modes.items():
        run = m["run"][:, t - 1]
        pred = m["pred"](t)
        idx = np.where((run >= m["need"]) & (pred >= 0))[0]
        for i in idx:
            out.append((name, int(i), int(pred[i]), float(-math.log10(m["q"][i]) * run[i]), int(run[i])))
    return out


# ── 조수: 특정 숫자의 회차 간 패턴 ──────────────────────────────────
class Scout:
    """'X 가 나오면 lag 회 뒤 Y' 패턴의 누적 성적. t 회차 예상은 반드시 update(t) 전에 뽑는다."""

    def __init__(self, P):
        self.P = P                                        # (회차, 46) 그 회차에 나온 숫자
        self.n = np.zeros((4, 46, 46), dtype=np.int32)
        self.h = np.zeros((4, 46, 46), dtype=np.int32)
        self.streak = np.zeros((4, 46, 46), dtype=np.int32)
        self.log = {}                                     # (lag, X) → 발사 때마다의 결과(46칸) 목록 — 숨겨 둔 구간 확인용

    def fired(self, nums, t):
        return [(lag, int(x)) for lag in LAGS if t - lag >= 0 for x in nums[t - lag]]

    def candidates(self, nums, t):
        """→ (살아 있는 패턴 [(lag, X, Y)], 황금 [(lag, X, Y, 적중, 발사)], 간격 패턴 [(g, Y)])"""
        alive, gold = [], []
        for lag, x in self.fired(nums, t):
            ys = np.where(self.streak[lag, x, 1:] >= ALIVE_STREAK)[0] + 1
            for y in ys:
                alive.append((lag, x, int(y)))
                n, h = int(self.n[lag, x, y]), int(self.h[lag, x, y])
                if h >= GOLD_MIN_HITS and h / n >= GOLD_RATIO * BASE_P:
                    rows = self.log[(lag, x)]
                    k = max(1, int(len(rows) * HOLDOUT_SHARE))
                    hold = sum(bool(r[y]) for r in rows[-k:]) / k      # 숨겨 둔 최근 구간
                    if hold >= GOLD_RATIO * BASE_P:
                        gold.append((lag, x, int(y), h, n))
        grid = [(g, y) for g in GAPS if t - 3 * g >= 0
                for y in np.where(self.P[t - g] & self.P[t - 2 * g] & self.P[t - 3 * g])[0] if y]
        return alive, gold, grid

    def update(self, nums, t):
        out = self.P[t]
        for lag, x in self.fired(nums, t):
            self.n[lag, x] += 1
            self.h[lag, x] += out
            self.streak[lag, x] = np.where(out, self.streak[lag, x] + 1, 0)
            self.log.setdefault((lag, x), []).append(out)

    def nearest(self, nums, t, k=5):
        """황금 기준에 가장 가까운, 지금 발사 중인 패턴 (일하고 있다는 표시)"""
        rows = []
        for lag, x in self.fired(nums, t):
            for y in range(1, 46):
                n, h = int(self.n[lag, x, y]), int(self.h[lag, x, y])
                if n >= 30:
                    rows.append((h / n / BASE_P, lag, x, y, h, n, int(self.streak[lag, x, y])))
        return sorted(rows, reverse=True)[:k]


# ── 번호 5세트 ─────────────────────────────────────────────────────
def law_masks(t, laws, F, hist, sample):
    """무작위 조합 표본이 각 법칙의 다음 회차 예상을 만족하는지 — 평균이 곧 '우연히 맞을 확률'.
    (앞 회차 값이 이미 정해져 있어 법칙마다 우연 확률이 다르다. 전체 평균 q 로 비교하면 실력처럼 보이는 착시가 생긴다)"""
    bs = bases(sample)
    out = []
    for _mode, i, pred, _w, _run in laws:
        f = F[i]
        x = hist[f[0]]
        out.append(formula_value(f, bs[f[0]], x[t - 1], x[t - 2]) == pred)
    return out


def draw_sample(rng):
    return np.sort(rng.random((SAMPLE, 45)).argsort(1)[:, :6] + 1, axis=1)   # 무작위 조합 SAMPLE 개


def pick_sets(laws, masks, sample, cand_w, past):
    score = np.zeros(SAMPLE)
    seen = set()
    for k in sorted(range(len(laws)), key=lambda k: -laws[k][3]):
        key = masks[k].tobytes()
        if key in seen:                              # 식은 달라도 같은 예상(같은 조합을 고름)이면 한 번만 센다
            continue
        seen.add(key)
        if len(seen) > LAW_TOP:
            break
        p = max(float(masks[k].mean()), 1e-4)
        score += -math.log10(p) * masks[k]          # 우연히 맞기 어려운 예상일수록 크게
    if cand_w.any():
        score += cand_w[sample].sum(1)
    out = []
    for j in np.argsort(-score, kind="stable"):
        c = tuple(int(v) for v in sample[j])
        if c in past or any(len(set(c) & set(o)) > MAX_OVERLAP for o in out):
            continue
        out.append(c)
        if len(out) == N_SETS:
            break
    return [list(c) for c in out]


def make_sets(ctx, trusted=()):
    """다음 회차 번호 5세트 — 살아 있는 법칙의 예상(믿는 법칙은 힘 ×2) · 조수 후보 숫자를 가장 많이 만족하는 조합"""
    boost = {ctx["key"].get((tuple(x["f"]), x["mode"], x["next"])) for x in trusted}
    score = np.zeros(SAMPLE)
    for k in sorted(ctx["masks"])[:LAW_TOP]:             # id 는 우연히 맞기 어려운 순
        w = -math.log10(max(ctx["chance"][k], 1e-4)) * (TRUST_BOOST if k in boost else 1.0)
        score += w * ctx["masks"][k]
    score += ctx["cand_w"][ctx["sample"]].sum(1)
    out = []
    for j in np.argsort(-score, kind="stable"):
        c = tuple(int(v) for v in ctx["sample"][j])
        if c in ctx["past"] or any(len(set(c) & set(o)) > MAX_OVERLAP for o in out):
            continue
        out.append(c)
        if len(out) == N_SETS:
            break
    return [list(c) for c in out]


def run(nums, rounds, start, cycles=None, reg=None):
    cycles = cycles or {c["name"]: c["digits"] for c in SEED_CYCLES}
    reg = reg or {}
    T = len(rounds)
    nums = np.asarray(nums, dtype=np.int32)
    P = np.zeros((T, 46), dtype=bool)
    for t in range(T):
        P[t, nums[t]] = True
    hist = bases(nums)
    F, V = build_formulas(hist)
    t0 = rounds.index(start)
    modes = law_modes(V, t0, cycles)
    # 자가 점검: 1056~1060회 맨 앞번호 끝수 3·8·1·7·3 → 7381 순환 4번 연속 이어짐
    if 1060 in rounds:
        i = next(k for k in range(len(F)) if np.array_equal(V[k, 2:], hist["1번째 번호의 끝수"][2:]))   # 같은 흐름의 식
        assert modes["순환 7381"]["run"][i, rounds.index(1060)] == 4, "7381 순환 계산이 맞지 않음"

    scout = Scout(P)
    for t in range(t0):
        scout.update(nums, t)
    rng, rnd = np.random.default_rng(7183), np.random.default_rng(1837)
    law_stat = {name: [0, 0, 0.0] for name in modes}            # 적중 · 예상 횟수 · 우연 기대
    law_since = {name: [0, 0, 0.0] for name in modes}           # 순환을 등록한 뒤의 새 회차만
    sc = {"follow": [0, 0], "grid": [0, 0], "gold": [0, 0]}     # 적중 · 예상 횟수
    alive_counts, rows = [], []
    past = {tuple(int(v) for v in nums[t]) for t in range(t0)}
    for t in range(t0, T):
        laws = alive_laws(modes, t)
        alive_counts.append(len(laws))
        sample = draw_sample(rng)
        masks = law_masks(t, laws, F, hist, sample)
        for (name, i, pred, _w, _run), mk in zip(laws, masks):
            s = law_stat[name]
            s[0] += int(V[i, t] == pred)
            s[1] += 1
            s[2] += float(mk.mean())                 # 그 회차 상황에서 무작위 조합이 이 예상을 만족할 확률
            if name.startswith("순환 ") and rounds[t] > reg.get(name[3:], 0):
                z = law_since[name]
                z[0] += int(V[i, t] == pred); z[1] += 1; z[2] += float(mk.mean())
        alive, gold, grid = scout.candidates(nums, t)
        cand_w = np.zeros(46)
        for _lag, _x, y in alive:
            cand_w[y] += 1.0
            sc["follow"][0] += int(P[t, y]); sc["follow"][1] += 1
        for _g, y in grid:
            cand_w[y] += 1.0
            sc["grid"][0] += int(P[t, y]); sc["grid"][1] += 1
        for _lag, _x, y, _h, _n in gold:
            cand_w[y] += 100.0                                   # 황금 숫자는 반드시 들어가게
            sc["gold"][0] += int(P[t, y]); sc["gold"][1] += 1
        sets = pick_sets(laws, masks, sample, cand_w, past)
        win = set(int(v) for v in nums[t])
        rand = [sorted(int(v) for v in rnd.choice(np.arange(1, 46), 6, replace=False)) for _ in range(N_SETS)]
        rows.append({"round": rounds[t], "sets": sets, "m": [len(win & set(s)) for s in sets],
                     "rand_m": [len(win & set(s)) for s in rand], "laws": len(laws), "gold": [g[2] for g in gold]})
        scout.update(nums, t)
        past.add(tuple(int(v) for v in nums[t]))

    # 다음 회차(아직 추첨 전) — 지금 살아 있는 것 (T 번째 회차 자리는 없으니 값만 덧붙여 계산)
    nxt_laws = []
    histn = {k: np.concatenate([v, [0]]) for k, v in hist.items()}   # T 번째 자리(다음 회차)는 비워 둠 — 앞 회차 값만 씀
    nsample = draw_sample(rng)
    for name, m in modes.items():
        runv = m["run"][:, T - 1]
        for i in np.where(runv >= m["need"])[0]:
            if name.startswith("주기"):
                pred = int(V[i, T - int(name.split()[1][:-1])])
            else:
                C = cycles[name[3:]]
                pred = C[(C.index(int(V[i, T - 1])) + 1) % len(C)] if int(V[i, T - 1]) in C else -1
            if pred >= 0:
                mk = law_masks(T, [(name, int(i), pred, 0, 0)], F, histn, nsample)[0]
                nxt_laws.append({"law": formula_name(F[i]), "mode": name, "run": int(runv[i]), "next": pred,
                                 "chance": float(mk.mean()), "f": list(F[i]), "_k": mk.tobytes(), "_m": mk})
    nxt_laws.sort(key=lambda x: (x["chance"], -x["run"]))   # 우연히 맞기 어려운 순
    uniq, seen = [], set()
    for x in nxt_laws:                                       # 같은 예상을 하는 식은 하나만 보여 줌
        if x["_k"] not in seen:
            seen.add(x.pop("_k"))
            uniq.append(x)
    nxt_laws = uniq
    masks = {}
    for k, x in enumerate(nxt_laws, 1):
        x["id"] = k
        masks[k] = x.pop("_m")
    Pn = np.vstack([P, np.zeros((1, 46), dtype=bool)])
    scout.P = Pn
    numsn = np.vstack([nums, np.zeros((1, 6), dtype=np.int32)])
    alive, gold, grid = scout.candidates(numsn, T)
    near = scout.nearest(numsn, T)
    cand_w = np.zeros(46)
    for _lag, _x, y in alive:
        cand_w[y] += 1.0
    for _g, y in grid:
        cand_w[y] += 1.0
    for _lag, _x, y, _h, _n in gold:
        cand_w[y] += 100.0
    ctx = {"sample": nsample, "masks": masks, "chance": {x["id"]: x["chance"] for x in nxt_laws}, "cand_w": cand_w,
           "past": past, "key": {(tuple(x["f"]), x["mode"], x["next"]): x["id"] for x in nxt_laws}}
    return {"formulas": len(F), "patterns": len(F) * len(modes) + len(LAGS) * 45 * 45 + len(GAPS) * 45,
            "law_stat": law_stat, "law_since": law_since, "scout": sc, "alive_avg": float(np.mean(alive_counts)), "rows": rows,
            "ctx": ctx, "modes": len(modes), "next": {"round": rounds[-1] + 1, "laws": nxt_laws[:SHOW_ALIVE], "laws_total": len(nxt_laws),
                     "follow": [{"lag": a, "x": b, "y": c} for a, b, c in alive], "grid": [{"gap": g, "y": int(y)} for g, y in grid],
                     "gold": [{"lag": a, "x": b, "y": c, "hits": h, "fired": n} for a, b, c, h, n in gold],
                     "nearest": [{"ratio": round(r, 2), "lag": lag, "x": x, "y": y, "hits": h, "fired": n, "streak": s}
                                 for r, lag, x, y, h, n, s in near]}}


# ── 2단계: 꿈꾸는 쪽 (제미나이) ──────────────────────────────────────
SYSTEM = """당신은 '7183 에이전트'입니다. 로또 당첨번호의 법칙이 한동안 유효하다가 몇 회차 뒤 다른 법칙으로 넘어가는
'생태계'를 추리합니다. 꿈꾸기를 좋아하고 추리력이 좋습니다. 목표는 하나 — 다음 회차 당첨.
- 숫자 계산은 서버가 합니다. 당신은 주어진 표를 읽고 추리하고 상상합니다. 표에 없는 수치를 지어내지 마세요.
- 법칙은 '식의 값이 회차마다 일정 주기로 되풀이되거나, 정해 둔 순환(숫자열)을 따라가는 것'입니다.
  식 = [기본 값] · [회차 사이 계산] · [마무리]. 서버가 모든 식에 대어 전 회차에서 셉니다.
- cycles: 새 순환(숫자열)을 꿈꾸세요. 최대 3개, 서로 다른 숫자 2~6개(0~99). 다음 주에 성적을 돌려받습니다.
  이미 사전에 있는 순환(돌려 놓은 것 포함)은 내지 마세요.
- trusted: [지금 살아 있는 법칙] 목록에서 다음 회차에 이어질 것 같은 것을 최대 3개, 목록의 번호(id)로 고르고 이유를 쓰세요.
  다음 주에 맞았는지 그대로 채점합니다.
- dream: 생태계 추리 — 무엇이 끊기고 무엇이 이어받았는지, 지금 흐름이 어디로 가는지 3~6문장.
- new_parts: 지금 조각으로는 표현할 수 없는 계산이 필요하면 한두 문장으로 제안 (없으면 빈 문자열).
- notes: 다음 주의 자신에게 남기는 연구 노트 (이어서 볼 것 · 버릴 것).
- 채점은 봐주지 않습니다. 성적이 우연과 같으면 그렇다고 쓰고 다른 방향을 꿈꾸세요.
- 모두 한국어로 씁니다."""


def dream_schema():
    return {"type": "object", "properties": {
        "dream": {"type": "string"},
        "cycles": {"type": "array", "items": {"type": "object", "properties": {
            "name": {"type": "string"}, "digits": {"type": "array", "items": {"type": "integer"}}, "why": {"type": "string"}},
            "required": ["name", "digits", "why"], "additionalProperties": False}},
        "trusted": {"type": "array", "items": {"type": "object", "properties": {
            "id": {"type": "integer"}, "why": {"type": "string"}}, "required": ["id", "why"], "additionalProperties": False}},
        "new_parts": {"type": "string"},
        "notes": {"type": "string"},
    }, "required": ["dream", "cycles", "trusted", "new_parts", "notes"], "additionalProperties": False}


def ask_dream(prompt):
    """제미나이에게 꿈을 묻는다 — 답을 조금씩 받는 방식(스트리밍) · 먼저 '생각 낮음'으로, 안 되면 기본 설정으로 한 번 더.
    공용 호출(research_strategy_ai.ask_gemini)이 2,600자 자료에도 420초 안에 답을 못 받는 일이 세 번 이어져(2026-11-25)
    7183 만 따로 부른다. 모델은 같다. 어디서 막히는지 보이게 첫 조각까지 걸린 시간 · 받은 글자 수를 로그에 남긴다."""
    import research_strategy_ai as S
    from google import genai
    from google.genai import types
    raw = os.environ["GEMINI_API_KEY"]
    m = re.search(r"AIza[0-9A-Za-z_\-]{35}", raw)
    client = genai.Client(api_key=m.group(0) if m else raw.strip(), http_options={"timeout": DREAM_DEADLINE * 1000})
    base = dict(system_instruction=SYSTEM, response_mime_type="application/json", response_schema=S._strip_additional(dream_schema()))
    last = None
    for label, extra in (("생각 낮음", {"thinking_config": types.ThinkingConfig(thinking_level="low")}), ("기본 설정", {})):
        t0, got = time.time(), {"first": None, "text": []}

        def pull(t0=t0, got=got, extra=extra):   # 기본값으로 묶어 둠 — 시간 초과 뒤 남은 호출이 다음 시도의 값을 건드리지 않게
            cfg = types.GenerateContentConfig(**base, **extra)
            for ch in client.models.generate_content_stream(model=S.GEMINI_MODEL, contents=prompt, config=cfg):
                if ch.text:
                    if got["first"] is None:
                        got["first"] = round(time.time() - t0, 1)
                    got["text"].append(ch.text)
            return "".join(got["text"])
        try:
            text = S._within(DREAM_DEADLINE, pull)
            print(f"[7183 gemini] {label}: 첫 조각 {got['first']}초 · 전체 {time.time() - t0:.1f}초 · {len(text)}자", file=sys.stderr)
            return json.loads(text), S.GEMINI_MODEL
        except Exception as e:
            msg = re.sub(r"AIza[0-9A-Za-z_\-]{20,}", "AIza***", str(e))[:1500]   # 한도 초과(429)는 어떤 한도인지가 뒤쪽에 적혀 있음
            print(f"[7183 gemini] {label} 실패 ({time.time() - t0:.0f}초 · 첫 조각 {got['first']}초 · 받은 글자 {sum(map(len, got['text']))}): "
                  f"{type(e).__name__} — {msg}", file=sys.stderr)
            last = f"{label}: {type(e).__name__} — {msg}"
            if not re.search(r"\b400\b|INVALID_ARGUMENT", msg):
                break   # 설정 문제(400)일 때만 기본 설정으로 다시 — 한도 초과(무료 하루 20번) · 시간 초과는 다시 불러도 한도만 쓴다
    raise RuntimeError(last)


def quota_until(msg, now):
    """제미나이 한도 초과(429) 문장에서 다시 부를 수 있는 시각을 읽는다. 한도 초과가 아니면 None.
    무료 등급은 하루 20번이고 태평양 시간 자정(= 17:00 KST)에 풀린다 — 못 읽으면 다음 17:05 KST."""
    if not re.search(r"\b429\b|RESOURCE_EXHAUSTED", msg or ""):
        return None
    m = re.search(r"retry in (?:(\d+)h)?(?:(\d+)m)?([\d.]+)s", msg)
    if m:
        sec = int(m.group(1) or 0) * 3600 + int(m.group(2) or 0) * 60 + float(m.group(3))
        return now + timedelta(seconds=sec + 300)          # 5분 여유
    k = now.astimezone(KST)
    nxt = k.replace(hour=17, minute=5, second=0, microsecond=0)
    return (nxt if nxt > k else nxt + timedelta(days=1)).astimezone(timezone.utc)


def rotations(d):
    return {tuple(d[i:] + d[:i]) for i in range(len(d))}


def clean_cycles(raw, cycles, latest):
    """제미나이가 낸 순환을 걸러 사전에 넣을 수 있는 것만 — 서로 다른 숫자 2~6개(0~99), 이미 있는 순환(돌린 것 포함) 제외"""
    have = set().union(*[rotations(c["digits"]) for c in cycles]) if cycles else set()
    names = {c["name"] for c in cycles}
    out = []
    for x in (raw or [])[:NEW_CYCLES * 2]:
        try:
            d = [int(v) for v in x.get("digits") or []]
        except (TypeError, ValueError, AttributeError):
            continue
        if not 2 <= len(d) <= 6 or len(set(d)) != len(d) or any(v < 0 or v > 99 for v in d) or tuple(d) in have:
            continue
        name = re.sub(r"\s+", "", str(x.get("name") or ""))[:12] or "".join(str(v) for v in d)
        if name in names:
            name = "".join(str(v) for v in d)
        if name in names:
            continue
        have |= rotations(d)
        names.add(name)
        out.append({"name": name, "digits": d, "by": "gemini", "registered_round": latest, "why": str(x.get("why") or "")[:200]})
        if len(out) == NEW_CYCLES:
            break
    return out


def clean_trusted(raw, laws):
    by_id = {x["id"]: x for x in laws}
    out, seen = [], set()
    for x in raw or []:
        try:
            k = int(x.get("id"))
        except (TypeError, ValueError, AttributeError):
            continue
        if k in by_id and k not in seen:
            seen.add(k)
            out.append(dict(by_id[k], why=str(x.get("why") or "")[:200]))
        if len(out) == MAX_TRUST:
            break
    return out


def score_trusted(prev, hist, latest):
    """지난 회차에 믿은 법칙이 실제로 맞았나 → (맞힘 · 예상 수 · 우연 기대, 항목별 결과)"""
    T = len(hist["6개 합"])
    items = []
    for x in (prev or {}).get("trusted") or []:
        f = tuple(x["f"])
        v = int(np.asarray(formula_value(f, hist[f[0]][T - 1:T], hist[f[0]][T - 2], hist[f[0]][T - 3]))[0])
        items.append({"law": x["law"], "mode": x["mode"], "next": x["next"], "actual": v, "hit": v == x["next"], "chance": x["chance"]})
    return [sum(i["hit"] for i in items), len(items), round(sum(i["chance"] for i in items), 3)], items


def cycle_report(cycles, res, prev_done):
    """순환별 성적(복기 · 등록 뒤) + 완성 여부"""
    out, done_now = [], []
    for c in cycles:
        st = res["law_stat"].get("순환 " + c["name"], [0, 0, 0.0])
        sn = res["law_since"].get("순환 " + c["name"], [0, 0, 0.0])
        h, n, e = st
        z = (h - e) / math.sqrt(e * (1 - e / n)) if n and 0 < e < n else 0.0
        done = (n >= DONE_MIN_N and h >= DONE_RATIO * e and z >= DONE_Z and sn[1] >= DONE_SINCE and sn[0] > sn[2])
        out.append(dict(c, replay=[h, n, round(e, 2)], since=[sn[0], sn[1], round(sn[2], 2)], z=round(z, 2), complete=bool(done)))
        if done and c["name"] not in prev_done:
            done_now.append(c["name"])
    return out, done_now


def build_prompt(res, nums, rounds, cyc, prev, scored):
    nx = res["next"]
    L = [f"다음 회차: {nx['round']}회", "", "[최근 20회 당첨번호]"]
    L += [f"- {rounds[k]}회: {' '.join(str(int(v)) for v in nums[k])}" for k in range(len(rounds) - 20, len(rounds))]
    L += ["", f"[지금 살아 있는 법칙 — 전체 {nx['laws_total']}개 중 우연히 맞기 어려운 순]"]
    L += [f"- id {x['id']}: {x['law']} [{x['mode']}] {x['run']}번 연속 → 다음 값 {x['next']} "
          f"(무작위 조합이 만족할 확률 {x['chance'] * 100:.1f}%)" for x in nx["laws"]] or ["- (없음)"]
    L += ["", f"[성적표 — {res['rows'][0]['round']}~{res['rows'][-1]['round']}회 복기: 살아 있는 법칙의 다음 회차 예상]"]
    L += [f"- {name}: {n}번 중 {h}번 적중 · 우연이면 {e:.1f}번" for name, (h, n, e) in res["law_stat"].items()]
    s = res["scout"]
    L += ["", "[조수 — 특정 숫자의 회차 간 패턴]",
          f"- X 다음에 Y (최근 3번 연속 적중 중): {s['follow'][1]}번 중 {s['follow'][0]}번 적중 (우연 13.3%)",
          f"- 일정 간격 숫자: {s['grid'][1]}번 중 {s['grid'][0]}번 적중 (우연 13.3%)",
          f"- 이번 회차 후보 숫자: 따라 나오는 숫자 {sorted({c['y'] for c in nx['follow']})} · 간격 {sorted({c['y'] for c in nx['grid']})} · "
          f"황금 {[c['y'] for c in nx['gold']] or '없음'}"]
    L += [f"- 황금 기준에 가까운 패턴: {c['x']} 이 나오면 {c['lag']}회 뒤 {c['y']} — {c['fired']}번 중 {c['hits']}번 (우연의 {c['ratio']}배)"
          for c in nx["nearest"][:3]]
    L += ["", "[순환 사전 — 이름: 숫자열 · 복기 성적 · 등록 뒤 성적]"]
    L += [f"- {c['name']}: {'→'.join(str(v) for v in c['digits'])} ({'사장님' if c['by'] == 'seed' else '내가 꿈꿈'} · {c['registered_round']}회 등록) · "
          f"복기 {c['replay'][1]}번 중 {c['replay'][0]}번(우연 {c['replay'][2]}) · 등록 뒤 {c['since'][1]}번 중 {c['since'][0]}번(우연 {c['since'][2]})"
          for c in cyc]
    L += ["", "[지난 회차에 내가 믿은 법칙의 결과]"]
    L += [f"- {i['law']} [{i['mode']}] 예상 {i['next']} → 실제 {i['actual']} ({'적중' if i['hit'] else '빗나감'})" for i in scored] or ["- (없음)"]
    rec = (prev or {}).get("record") or {}
    if rec.get("trusted"):
        h, n, e = rec["trusted"]
        L += [f"- 지금까지 내가 믿은 법칙: {n}번 중 {h}번 적중 · 우연이면 {e}번"]
    L += ["", "[지난주의 내가 남긴 연구 노트]", (prev or {}).get("notes") or "(없음 — 첫 주)"]
    L += ["", "[쓸 수 있는 조각]", "- 기본 값: " + ", ".join(bases(np.array([[1, 2, 3, 4, 5, 6]])).keys()),
          "- 회차 사이 계산: " + ", ".join(p[0] for p in PAIRS),
          "- 마무리: 그대로, 자릿수 합, 2~12로 나눈 나머지 · 몫 · 나누어떨어질 때의 몫"]
    return "\n".join(L)


def weekly(db, a):
    """이번 회차 흐름 — 세기 → 지난 꿈 채점 → 제미나이 꿈 → 저장"""
    wins = db.all("lotto_winning_numbers", {"select": "round,draw_date,num1,num2,num3,num4,num5,num6", "order": "round"}, key="round")
    rounds = [w["round"] for w in wins]
    assert rounds == list(range(rounds[0], rounds[0] + len(rounds))), "회차가 이어지지 않음"
    nums = np.array([sorted(w[f"num{i}"] for i in range(1, 7)) for w in wins], dtype=np.int32)
    latest, target = rounds[-1], rounds[-1] + 1
    now = datetime.now(timezone.utc)
    dd = wins[-1].get("draw_date") or (date(2002, 12, 7) + timedelta(days=7 * (latest - 1))).isoformat()   # 1회 추첨일에서 계산
    # 판매 마감(토 20:00 KST) 뒤에는 만들지 않는다 — 예상은 추첨 전에 고정
    dl = datetime.combine(date.fromisoformat(str(dd)[:10]) + timedelta(days=7), datetime.min.time(), KST) + timedelta(hours=20)
    if now >= dl:
        print(f"{target}회 판매 마감 지남 — 만들지 않음 (새 당첨번호 대기)")
        return None
    got = db.get("research_results", {"select": "target_round,payload", "research_type": f"eq.{RESULT_TYPE}",
                                      "order": "target_round.desc,created_at.desc", "limit": "6"})
    cur = next((x["payload"] for x in got if x["target_round"] == target), None)
    prev = next((x["payload"] for x in got if x["target_round"] == latest), None)
    have_ai = bool(cur and cur.get("source") == "gemini") and not a.force
    registered = bool(cur and cur.get("sets_status") == "registered")
    until = (cur or {}).get("quota_until")
    quota_wait = bool(until) and now < datetime.fromisoformat(until) and not a.force
    wait_note = f"제미나이 한도 초과 — {datetime.fromisoformat(until).astimezone(KST):%m/%d %H:%M}(KST) 이후 다시 시도" if quota_wait else None
    # --late-sets (수동 실행 때만): 월요일에 제미나이가 못 답해 계산 번호로 등록된 회차에, 제미나이 번호를 별도 기록으로 한 번 추가
    late_want = bool(getattr(a, "late_sets", False) and registered and cur.get("sets_by") == "rule" and not cur.get("late_sets"))
    if have_ai and registered and not late_want:
        print(f"{target}회 7183 에이전트 이미 있음(제미나이 · 번호 등록) — 고정")
        return cur
    if quota_wait and registered:
        print(f"{target}회 7183 에이전트 — {wait_note} (번호는 등록됨 · 할 일 없음)")
        return cur
    carry = cur or prev or {}
    cycles = [dict(c) for c in (carry.get("cycles") or SEED_CYCLES)]
    cycles = [{k: c[k] for k in ("name", "digits", "by", "registered_round", "why") if k in c} for c in cycles]

    def count(cl):
        return run(nums, rounds, a.start, {c["name"]: c["digits"] for c in cl}, {c["name"]: c["registered_round"] for c in cl})

    res = count(cycles)
    hist = bases(nums)
    # 지난 회차 채점 — 항상 지난 회차 기록(prev.record)에 더하므로 같은 회차를 여러 번 돌려도 값이 같다
    rec, scored = score_trusted(prev, hist, latest) if prev else ([0, 0, 0.0], [])
    pr = (prev or {}).get("record") or {}
    old = pr.get("trusted") or [0, 0, 0.0]
    win = set(int(v) for v in nums[-1])
    pm = [len(win & set(s)) for s in ((prev or {}).get("sets") or [])] if (prev or {}).get("sets_status") == "registered" else []
    pg = [int(y in win) for y in ((prev or {}).get("gold_numbers") or [])] if pm else []
    os_, og = pr.get("sets") or [0, 0, 0], pr.get("gold") or [0, 0]
    record = {"trusted": [old[0] + rec[0], old[1] + rec[1], round(old[2] + rec[2], 3)],
              "sets": [os_[0] + len(pm), os_[1] + sum(pm), os_[2] + sum(x >= 3 for x in pm)],   # 세트 수 · 맞힌 개수 합 · 3개 이상
              "gold": [og[0] + len(pg), og[1] + sum(pg)]}                                       # 황금 숫자 수 · 적중
    prev_done = {c["name"] for c in (carry.get("cycles") or []) if c.get("complete")}
    cyc, done_now = cycle_report(cycles, res, prev_done)
    prompt = build_prompt(res, nums, rounds, cyc, dict(prev or {}, record=record), scored)
    data = model = err = None
    if have_ai:   # 이번 회차 꿈은 이미 받음 — 다시 부르지 않고 번호 등록만 마저 한다
        model = cur.get("model")
    elif quota_wait:   # 한도가 풀릴 때까지 부르지 않는다 (번호 등록만 마저 한다)
        err = wait_note
    elif os.environ.get("GEMINI_API_KEY"):
        try:
            data, model = ask_dream(prompt)
        except Exception as e:   # 실패한 날은 계산값만 — 다음 실행에서 다시
            err = str(e)[:1500]
            qu = quota_until(err, now)
            until = qu.isoformat() if qu else None
            if qu:
                print(f"  제미나이 한도 초과 — {qu.astimezone(KST):%m/%d %H:%M}(KST) 이후 다시 시도")
    else:
        err = "GEMINI_API_KEY 없음"
    nx = res["next"]
    if have_ai:
        new, trusted = [], cur.get("trusted") or []
    elif data:
        new = clean_cycles(data.get("cycles"), cycles, latest)
        trusted = clean_trusted(data.get("trusted"), nx["laws"])
        if new:   # 새 순환을 넣어 다시 세어, 꿈꾼 순환의 첫 성적을 함께 저장
            # shortcut: 사전이 꽉 차면 오래된 순환부터 버림, 완성에 가까운 순환을 지키려면 성적순으로 바꿀 것
            seed = [c for c in cycles if c["by"] == "seed"]
            cycles = seed + [c for c in cycles + new if c["by"] != "seed"][-(MAX_CYCLES - len(seed)):]
            res = count(cycles)
            cyc, done_now = cycle_report(cycles, res, prev_done)
    else:
        new, trusted = [], [dict(x, why="우연히 맞기 가장 어려운 예상 (계산)") for x in nx["laws"][:MAX_TRUST]]
    ai = have_ai or bool(data)
    kept = cur if have_ai else {}
    # 번호 5세트 — 월요일 공개 시점 이후 첫 실행에서 한 번 등록하고 고정
    sets, sets_status, sets_by, sets_note = [], "waiting", None, None
    gold_numbers = [c["y"] for c in nx["gold"]]
    if registered:
        sets, sets_status, sets_by, gold_numbers = cur["sets"], "registered", cur.get("sets_by"), cur.get("gold_numbers") or []
    else:
        from research_release import prediction_allowed
        ok, sets_note, _ = prediction_allowed(db.get, target, dd, latest)
        if ok:
            sets, sets_by = make_sets(res["ctx"], trusted if ai else ()), ("gemini" if ai else "rule")
            if a.dry_run:
                sets_status = "dry-run"
            else:
                db.upsert("research_predictions", [{
                    "algorithm": REG_ALGO, "version": REG_VERSION, "target_round": target, "data_end_round": latest, "sets": sets,
                    "generated_at": now.isoformat(), "deadline_at": dl.isoformat(), "pre_deadline": True, "locked": True,
                    "status": "pending"}], "algorithm,version,target_round", ignore=True)
                reg = db.get("research_predictions", {"select": "sets", "algorithm": f"eq.{REG_ALGO}", "version": f"eq.{REG_VERSION}",
                                                      "target_round": f"eq.{target}"})
                if reg:
                    sets, sets_status = reg[0]["sets"], "registered"
    # 늦은 제미나이 번호 — 월요일 등록 번호(sets)는 그대로 두고 별도 버전으로만 남긴다 (덮어쓰지 않음)
    late, late_at = (cur or {}).get("late_sets") or [], (cur or {}).get("late_sets_at")
    if late_want and ai:
        late, late_at = make_sets(res["ctx"], trusted), now.isoformat()
        if not a.dry_run:
            try:
                db.upsert("research_predictions", [{
                    "algorithm": REG_ALGO, "version": LATE_VERSION, "target_round": target, "data_end_round": latest, "sets": late,
                    "generated_at": late_at, "deadline_at": dl.isoformat(), "pre_deadline": True, "locked": True,
                    "status": "pending"}], "algorithm,version,target_round", ignore=True)
            except Exception as e:   # 장부에 못 남겨도 저장본에는 남긴다
                print(f"  늦은 제미나이 번호 장부 등록 실패 — 저장본에만 남김: {str(e)[:200]}")
    elif late_want:
        print("  --late-sets: 제미나이가 답하지 못해 늦은 번호를 만들지 않음")
    rows = res["rows"]
    m = [x for r in rows for x in r["m"]]
    payload = {
        "version": VERSION, "target_round": target, "latest_round": latest, "generated_at": now.isoformat(),
        "source": "gemini" if ai else "rule", "model": model, "ai_error": err,
        "quota_until": None if ai else until,       # 제미나이 한도가 풀리는 시각 — 그때까지 다시 부르지 않음
        "sets": sets, "sets_status": sets_status, "sets_by": sets_by, "sets_note": sets_note, "gold_numbers": gold_numbers,
        "reg_version": REG_VERSION,
        "late_sets": late, "late_sets_at": late_at,   # 주중에 제미나이가 답해 추가한 번호 (별도 기록 · 월요일 번호는 그대로)
        "scanned": res["patterns"], "formulas": res["formulas"], "alive_total": nx["laws_total"], "alive": nx["laws"],
        "scoreboard": {"from": rows[0]["round"], "to": rows[-1]["round"],
                       "laws": {k: [v[0], v[1], round(v[2], 1)] for k, v in res["law_stat"].items()},
                       "scout": res["scout"], "sets": {"n": len(m), "mean": round(float(np.mean(m)), 4), "ge3": int(sum(x >= 3 for x in m))}},
        "scout": {k: nx[k] for k in ("follow", "grid", "gold", "nearest")},
        "cycles": cyc, "new_cycles": kept.get("new_cycles") or [c["name"] for c in new], "completed_now": done_now,
        "dream": str(kept.get("dream") or (data or {}).get("dream") or "")[:1500], "trusted": trusted,
        "new_parts": str(kept.get("new_parts") or (data or {}).get("new_parts") or "")[:400],
        "notes": str(kept.get("notes") or (data or {}).get("notes") or (prev or {}).get("notes") or "")[:1500],
        "scored_sets": pm,
        "record": record, "scored_previous": scored,
        "rule": "법칙 · 조수는 서버 계산, 꿈(추리 · 새 순환 · 믿는 법칙)은 제미나이. 채점은 다음 회차 적중 하나 — 우연 기대와 나란히",
    }
    json.dumps(payload, ensure_ascii=False)
    print(f"{target}회 7183 에이전트 ({payload['source']}{' · AI 실패: ' + err if err and not data else ''}) — "
          f"살펴본 것 {payload['scanned']:,}개 · 살아 있는 법칙 {nx['laws_total']}개 · 순환 {len(cyc)}개 (새로 {len(new)}개) · 완성 {done_now or '없음'}")
    print(f"  지난 회차 믿은 법칙: {rec[1]}개 중 {rec[0]}개 적중 · 누적 {record['trusted']} · 지난 번호 맞힌 개수 {pm or '없음'}")
    print(f"  번호 5세트 ({sets_status}{' · ' + sets_by if sets_by else ''}{' · ' + sets_note if sets_note and not sets else ''}): {sets}")
    if late:
        print(f"  늦은 제미나이 번호 ({LATE_VERSION} · {late_at}): {late}")
    print(f"  황금 숫자: {gold_numbers or '없음'}")
    for x in trusted:
        print(f"  믿는 법칙: {x['law']} [{x['mode']}] → {x['next']} — {x['why']}")
    if payload["dream"]:
        print("  꿈: " + payload["dream"][:300])
    if a.dry_run:
        print(f"\n── 제미나이에게 보내는 자료 ({len(prompt)}자) ──\n{prompt}")
        print("\n드라이런 — 저장 안 함")
        return payload
    db.upsert("research_results", [{"research_type": RESULT_TYPE, "model_version": ROW_VERSION, "training_end_round": latest,
                                    "target_round": target, "payload": payload}],
              "research_type,model_version,training_end_round,target_round")
    print("저장 완료")
    return payload


def selfcheck():
    """제미나이 출력 걸러내기 점검 (잘못된 순환 · 번호는 버린다)"""
    cl = [dict(c) for c in SEED_CYCLES]
    got = clean_cycles([{"name": "a b", "digits": [3, 8, 1, 7], "why": "돌린 7381"}, {"name": "", "digits": [1, 1], "why": ""},
                        {"name": "큰수", "digits": [5, 100], "why": ""}, {"name": "짝", "digits": [2, 4, 6], "why": "x"}, "쓰레기"], cl, 1251)
    assert [c["name"] for c in got] == ["짝"] and got[0]["registered_round"] == 1251, got
    laws = [{"id": 1, "law": "a", "mode": "m", "next": 1, "chance": 0.1, "f": ["6개 합", 0, 0]}]
    t0 = datetime(2026, 11, 24, 17, 49, 50, tzinfo=timezone.utc)
    q = quota_until("429 RESOURCE_EXHAUSTED ... Please retry in 14h10m8.61556793s.', 'status'", t0)
    assert q.astimezone(KST).strftime("%m/%d %H:%M") == "11/25 17:04", q          # 14시간 10분 뒤 + 5분 여유
    assert quota_until("429 RESOURCE_EXHAUSTED", t0).astimezone(KST).strftime("%m/%d %H:%M") == "11/25 17:05"   # 못 읽으면 다음 17:05
    assert quota_until("503 UNAVAILABLE high demand", t0) is None
    assert [x["id"] for x in clean_trusted([{"id": 9, "why": ""}, {"id": "1", "why": "w"}, {"id": 1, "why": "중복"}, None], laws)] == [1]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="start", type=int, default=TEST_FROM)
    ap.add_argument("--out")
    ap.add_argument("--dry-run", action="store_true", help="이번 회차 흐름 전체 (저장 없음)")
    ap.add_argument("--publish", action="store_true", help="서버 전용 — research_results 에 저장")
    ap.add_argument("--force", action="store_true", help="이번 회차 꿈이 이미 있어도 다시")
    ap.add_argument("--late-sets", action="store_true",
                    help="계산 번호로 등록된 회차에 제미나이 번호를 별도 기록으로 추가 (수동 실행 때만 · 월요일 번호는 그대로)")
    a = ap.parse_args()
    if a.publish and os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("저장은 서버(GitHub Actions)에서만 합니다. 로컬은 --dry-run 만 허용")
    selfcheck()
    db = R.Db(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"], dry=not a.publish)
    if a.publish or a.dry_run:
        a.dry_run = not a.publish
        weekly(db, a)
        return
    wins = db.all("lotto_winning_numbers", {"select": "round,num1,num2,num3,num4,num5,num6", "order": "round"}, key="round")
    rounds = [w["round"] for w in wins]
    assert rounds == list(range(rounds[0], rounds[0] + len(rounds))), "회차가 이어지지 않음"
    nums = [sorted(w[f"num{i}"] for i in range(1, 7)) for w in wins]
    res = run(nums, rounds, a.start)
    rows = res["rows"]
    n_sets = sum(len(r["m"]) for r in rows)

    def stat(k):
        m = [x for r in rows for x in r[k]]
        return f"세트당 평균 {np.mean(m):.3f}개 · 3개 이상 {sum(x >= 3 for x in m)}세트 · 4개 이상 {sum(x >= 4 for x in m)}세트"

    print(f"7183 에이전트 {VERSION} — 자료 {rounds[0]}~{rounds[-1]}회 · 복기 {rows[0]['round']}~{rows[-1]['round']}회 ({len(rows)}회차)")
    print(f"살펴본 것: 법칙 식 {res['formulas']}개 × 방식 {res['modes']}가지 + 조수의 숫자 패턴 = {res['patterns']:,}개")
    print(f"\n① 법칙 — 회차마다 살아 있는 법칙 평균 {res['alive_avg']:.1f}개")
    th = tn = te = 0
    for name, (h, n, e) in res["law_stat"].items():
        print(f"   {name}: 살아 있는 법칙의 다음 회차 예상 {n}번 중 {h}번 적중 · 우연이면 {e:.1f}번")
        th, tn, te = th + h, tn + n, te + e
    print(f"   합계: {tn}번 중 {th}번 적중 · 우연이면 {te:.1f}번")
    s = res["scout"]
    print("\n② 조수 — 특정 숫자의 회차 간 패턴")
    for k, label in (("follow", "X 다음에 Y (최근 3번 연속 적중 중)"), ("grid", "일정 간격으로 나오는 숫자 (3번 연속)"), ("gold", "황금(확실한 패턴)")):
        h, n = s[k]
        print(f"   {label}: 후보 {n}번 중 {h}번 적중" + (f" = {h / n * 100:.1f}% · 우연이면 {BASE_P * 100:.1f}%" if n else " — 기준을 넘은 패턴 없음"))
    print(f"\n③ 번호 5세트 — {len(rows)}회차 × {N_SETS}세트 = {n_sets}세트")
    print(f"   7183 방식: {stat('m')}")
    print(f"   무작위   : {stat('rand_m')}")
    print(f"   이론값   : 세트당 평균 0.800개 · 3개 이상 약 {n_sets * 0.018638:.1f}세트")
    nx = res["next"]
    print(f"\n④ 다음 회차({nx['round']}회) — 지금 살아 있는 법칙 {nx['laws_total']}개")
    for x in nx["laws"][:6]:
        print(f"   {x['law']} [{x['mode']}] {x['run']}번 연속 → 다음 값 {x['next']} (무작위 조합이 이 예상을 만족할 확률 {x['chance'] * 100:.1f}%)")
    print(f"   조수 후보 숫자: 따라 나오는 숫자 {sorted({c['y'] for c in nx['follow']})} · 간격 {sorted({c['y'] for c in nx['grid']})} · 황금 {[c['y'] for c in nx['gold']] or '없음'}")
    print("   황금 기준에 가장 가까운 패턴:")
    for c in nx["nearest"]:
        print(f"     {c['x']} 이 나오면 {c['lag']}회 뒤 {c['y']}: 과거 {c['fired']}번 중 {c['hits']}번 (우연의 {c['ratio']}배) · 최근 연속 {c['streak']}번")
    if a.out:
        res.pop("ctx")                                   # 번호 고르기용 배열 — 파일로 남기지 않음
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
