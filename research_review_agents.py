"""
지방장 회차 복기 (rv-1.0) — research_agent_replay.py 의 회차 루프에서 호출 (예측 → 발표 → 복기 → 보정 → 다음 예측)

회차 t 에서 사용하는 값
  · 사전 예측: t-1 까지 데이터로 계산한 판매점 점수 s_live 와 동결 TOP5 (research_replay_agent_predictions)
    → 실제 당첨점의 '사전 순위'는 추첨 전 점수로만 매긴다 (결과를 본 뒤 만든 예측을 사전 예측으로 쓰지 않음)
  · 실제 결과: 회차 t 1등(F)·1·2등(E) 판매점
  · 가설: 회차 t 발화·적중(대조군 포함 outcomes), 판정 변화(events), 판정 전후 실전 배수
결과는 research_review_agent_rounds 에 회차당 1행(지방장 전원 배열)으로 저장한다 (불변).

판매량 분모가 없으므로 판매점별 한 장당 당첨확률을 계산했다고 주장하지 않는다.
기준모델: 지역 내 무작위(판매점 수 비례 균등 기대값) · 과거 빈도만(history) TOP5.
"""

import math
import re
from collections import Counter, defaultdict

import numpy as np

import research_agent_worker as W
from research_region_worker import clean
from research_agent_worker import S_PASS, S_COMB, STATUS

REVIEW_VERSION = "rv-1.0"
K = 5

# 가설 종류 → 복기 묶음
GROUP = {
    "store_cycle": "cycle", "cycle_pooled": "cycle",
    "store_lead": "lead", "region_lead": "lead", "region_store_lead": "lead", "self_repeat": "lead",
    "store_cowin": "cowin", "region_cowin": "cowin",
    "neighbor_spill": "spatial", "store_spill": "spatial",
    "region_trend_up": "trend", "region_trend_down": "trend", "region_dormant": "trend",
    "composite": "composite",
}
GROUP_LABEL = {"cycle": "주기", "lead": "선행·후행", "cowin": "동시 당첨", "spatial": "공간전이(인접 확산)",
               "trend": "지역 추세", "composite": "복합 조건", "other": "기타"}


def _norm(s):
    return re.sub(r"[\s\-·.,()]+", "", (s or "").lower())


def dup_groups(u):
    """이름+주소가 같은 판매점(코드만 다른 중복 기록) → 같은 그룹 번호. 그룹이 없으면 자기 자신."""
    if getattr(u, "_rv_gid", None) is not None:
        return u._rv_gid
    gid = np.arange(u.S)
    first = {}
    for i in range(u.S):
        if not u.addr[i]:
            continue
        key = _norm(u.addr[i]) + "|" + _norm(u.name[i])
        if key in first:
            gid[i] = first[key]
        else:
            first[key] = i
    u._rv_gid = gid
    return gid


def capture(eng):
    """판정 갱신 전 상태 (보정 전 실전 배수 계산용)"""
    return {"status": eng.status.copy(), "ratio": eng.test_ratio.copy(), "H": eng.H}


def _live(status, boost):
    return np.isin(status, (S_PASS, S_COMB)) & boost


def _factor(ratio):
    cap = W.FACTOR_CAP
    return float(min(max(ratio, 1 / cap), cap))


def round_review(u, eng, pr, ti, t, snapshot_id, lists, fire2, kout, expv2, before, changes, mode, stored_used, mismatch):
    """회차 t 지방장 전원 복기 행"""
    dv = pr["dv"]
    s = dv["s_live"]
    Ft, Et = u.F[ti], u.E[ti]
    gid = dup_groups(u)
    win_groups = set(gid[np.where(Ft == 1)[0]].tolist())
    ev_groups = set(gid[np.where(Et == 1)[0]].tolist())

    # 가설 → 지방장·묶음 (회차 t 시점 가설 기준)
    H0 = before["H"]
    hs = eng.st.H[:H0]
    h_agent = np.array([u.aidx.get(h["agent_id"], -1) for h in hs], int) if H0 else np.zeros(0, int)
    h_group = [GROUP.get(h["kind"], "other") for h in hs]
    h_shared = np.array([h.get("shared_from") is not None for h in hs], bool) if H0 else np.zeros(0, bool)
    fire_pre = pr["fire"][:H0]
    live_pre = _live(before["status"][:H0], eng.boost[:H0]) if H0 else np.zeros(0, bool)
    fired = fire2[:H0] if fire2 is not None else fire_pre
    succ = (kout[:H0] > 0) if kout is not None else None
    exp_ = expv2[:H0] if expv2 is not None else None

    by_agent_fired = defaultdict(list)
    for i in np.where(fired)[0]:
        if h_agent[i] >= 0:
            by_agent_fired[int(h_agent[i])].append(int(i))

    # 판정 변화 (보정 후보) — 지방장별
    idx_of = eng.st.H_index
    ch_by_agent = defaultdict(list)
    routine_by_agent = Counter()     # 발견→연구 중 같은 일상 전환은 개수만 (용량 절감)
    for c in changes:
        i = idx_of.get(c["hypothesis_id"])
        if i is None or i >= len(before["status"]):
            continue
        h = eng.st.H[i]
        lb = bool(_live(before["status"][i:i + 1], eng.boost[i:i + 1])[0])
        la = bool(_live(eng.status[i:i + 1], eng.boost[i:i + 1])[0])
        fb = _factor(before["ratio"][i]) if lb else 1.0
        fa = _factor(eng.test_ratio[i]) if la else 1.0
        meaningful = lb != la or {c["status_from"], c["status_to"]} & {"passed", "combined", "weakened", "rejected"}
        if not meaningful:
            routine_by_agent[u.aidx.get(h["agent_id"], -1)] += 1
            continue
        ch_by_agent[u.aidx.get(h["agent_id"], -1)].append(
            [c["hypothesis_id"], h["kind"], c["status_from"], c["status_to"], int(lb), int(la), round(fb, 3), round(fa, 3),
             int(c["test_n"]), int(c["test_k"]), round(float(c["test_expected"]), 3), round(float(c["test_p"]), 5)])

    new_by_agent = Counter(u.aidx.get(h["agent_id"], -1) for h in eng.st.H if h["discovered_round"] == t)

    entries = []
    spatial = defaultdict(lambda: [0, 0, 0.0, 0])   # group → [발화, 적중, 기대, 실전 적용 발화]
    shared_tot = [0, 0]
    tot = Counter()
    exp_tot = [0.0, 0.0, 0.0]
    for a, agid in enumerate(u.agent_ids):
        mem = u.members[a]
        n = int(len(mem))
        codes = (lists or {}).get(agid) or []
        top = [u.cidx[c] for c in codes if c in u.cidx][:K]
        hist = [int(x) for x in dv["hist"][a]][:K]
        # 사전 순위 (추첨 전 점수, 같은 점수는 판매점 순서 고정)
        order = mem[np.argsort(-s[mem], kind="stable")] if n else mem
        rank = {int(x): r + 1 for r, x in enumerate(order)}
        top_groups = [int(gid[x]) for x in top]
        winners = [int(x) for x in mem if Ft[x] == 1]
        e = {"n": n, "rf": len(winners), "re": int(Et[mem].sum()) if n else 0,
             "r2": int(sum(1 for x in mem if Et[x] == 1 and Ft[x] == 0))}
        if winners:
            wl = []
            for w in winners:
                g = int(gid[w])
                hit_rank = (top_groups.index(g) + 1) if g in top_groups else None
                wl.append([u.codes[w], rank.get(w), hit_rank, int(hit_rank is not None and u.codes[top[hit_rank - 1]] != u.codes[w])])
            e["w"] = wl
        # TOP k 1등 적중 (코드 정규화: 같은 이름·주소의 다른 코드 포함)
        hk = [int(sum(1 for g in top_groups[:k] if g in win_groups)) for k in (1, 3, 5)]
        e["h"] = hk
        e["a5"] = int(sum(1 for g in top_groups if g in ev_groups))
        e["hh"] = int(sum(1 for x in hist if int(gid[x]) in win_groups))
        xk = [round(min(k, n) / n * len(winners), 4) if n else 0.0 for k in (1, 3, 5)]
        e["x"] = xk
        # 가설 발화·적중 (묶음별)
        fl = by_agent_fired.get(a, [])
        if fl:
            g = defaultdict(lambda: [0, 0, 0.0, 0])
            for i in fl:
                gg = g[h_group[i]]
                gg[0] += 1
                if succ is not None and succ[i]:
                    gg[1] += 1
                if exp_ is not None:
                    gg[2] += float(exp_[i])
                if fire_pre[i] and live_pre[i]:
                    gg[3] += 1
                if h_shared[i]:
                    shared_tot[0] += 1
                    shared_tot[1] += int(bool(succ is not None and succ[i]))
            e["g"] = {k: [v[0], v[1], round(v[2], 3), v[3]] for k, v in g.items()}
            for k, v in g.items():
                sp = spatial[k]
                sp[0] += v[0]; sp[1] += v[1]; sp[2] += v[2]; sp[3] += v[3]
        if ch_by_agent.get(a):
            e["c"] = ch_by_agent[a]
        if routine_by_agent.get(a):
            e["cc"] = int(routine_by_agent[a])
        if new_by_agent.get(a):
            e["nw"] = int(new_by_agent[a])
        entries.append(e)
        tot["region_first_agents"] += int(bool(winners))
        tot["winners"] += len(winners)
        tot["h1"] += hk[0]; tot["h3"] += hk[1]; tot["h5"] += hk[2]
        tot["hist5"] += e["hh"]; tot["any5"] += e["a5"]
        tot["outside"] += sum(1 for w in e.get("w", []) if w[2] is None)
        for j in range(3):
            exp_tot[j] += xk[j]

    first_idx = np.where(Ft == 1)[0]
    summary = {"agents": len(u.agent_ids), "reviewed": len(entries),
               "region_first_agents": tot["region_first_agents"], "first_winners": int(len(first_idx)),
               "first_winners_in_agents": tot["winners"], "unassigned_first": int(sum(1 for x in first_idx if u.st_agent[x] < 0)),
               "top_first_hits": [tot["h1"], tot["h3"], tot["h5"]], "top_expected_uniform": [round(x, 3) for x in exp_tot],
               "history_first_hits5": tot["hist5"], "any_hits5": tot["any5"], "outside_winners": tot["outside"],
               "changes": int(sum(len(v) for v in ch_by_agent.values())),
               "routine_changes": int(sum(routine_by_agent.values())),
               "live_changes": int(sum(1 for v in ch_by_agent.values() for c in v if c[4] != c[5])),
               "new_hypotheses": int(sum(new_by_agent.values())), "shared_fired": shared_tot[0], "shared_success": shared_tot[1]}
    return {"review_version": REVIEW_VERSION, "target_round": t, "prediction_snapshot_id": snapshot_id,
            "prediction_mode": mode, "data_through_round": t - 1, "round_valid": bool(u.valid[ti]),
            "agent_ids": list(u.agent_ids), "entries": entries,
            "spatial": {k: [v[0], v[1], round(v[2], 3), v[3]] for k, v in spatial.items()},
            "summary": summary,
            "integrity": {"stored_snapshot_used": bool(stored_used), "recompute_matches_stored": (not mismatch) if stored_used else None,
                          "prior_rank_source": "추첨 전 점수(s_live, t-1까지 데이터)",
                          "code_normalization": "같은 이름·주소의 다른 판매점 코드는 같은 판매점으로 평가"}}


class ReviewWriter:
    """복기 행 저장 (한 번 쓴 회차는 다시 쓰지 않음). dry-run 재현에서도 복기만 저장할 수 있다."""

    def __init__(self, db, enabled):
        self.db, self.enabled = db, enabled
        self.buf = []
        self.written = 0
        self.rounds = []

    def add(self, row):
        self.buf.append(row)
        self.rounds.append(row["target_round"])

    def flush(self):
        if not self.buf:
            return
        rows, self.buf = clean(self.buf), []
        if self.enabled:
            for i in range(0, len(rows), 10):
                self.db.upsert("research_review_agent_rounds", rows[i:i + 10], "review_version,target_round",
                               ignore_duplicates=True)
            self.written += len(rows)
