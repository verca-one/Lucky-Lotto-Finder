"""
가설 공장 (hf-1.1) — AI 전략기획부(또는 관리자)가 제시한 방향의 가설을 비서가 검증·유지·폐기한다

가설 = (조건, 결과, 기대 방향). 예: '홀수 회차(조건)에는 2등 당첨자 쏠림(결과)이 높다(기대)'.
조건·결과는 아래 VOCAB 목록에서만 고른다 (저장된 DB 데이터로 계산 가능한 것만). 목록 밖이면 'unsupported'(데이터 미확보).

검증 절차 (결과를 보기 전에 고정)
  1. 발견 구간 269~1000회: 조건 회차 vs 나머지 회차, 기대 방향 단측 Mann-Whitney p < 0.05
  2. 확인 구간 1001회~가설 생성 회차: 같은 검정, 이번 실행에서 확인 단계에 오른 가설들끼리 BH(FDR 5%) 보정 후 통과
     → 둘 다 통과 = validated(검증 통과), 아니면 rejected(기각)
  3. 통과 이후 새 회차 추적(forward): 조건 회차 10회 이상 쌓이면 기대 방향이 유지되면 maintained(유지), 뒤집히면 discarded(폐기)
  · 표본(조건/비조건 각 15회) 부족이면 '판정 불가'로 닫음 (발견·확인 구간은 고정이라 늘지 않음)
  · 같은 가설은 code 로 중복 생성 막음
가설 종류 (spec.kind)
  · 기본(base) · 응용(applied): 통과·유지 가설에서 같은 조건 · 같은 계열의 다른 결과를 자동 파생 → 1~3 단계 그대로
  · 보충회생(supplement): 아깝게 기각된 가설(발견 p<0.20, 방향 맞음)에 조건 하나를 보탬 → 발견 기준 p<0.01 로 더 엄격
  · 회생(revival): 기각·폐기 후 50회차마다 '탈락 뒤 새 회차만'으로 재검정 → BH 통과 시 새 회차 추적부터 다시
  · 임시 일부 발췌(partial): 25회차마다 최근 100회만 검정, p<0.01 + BH 통과 시 '임시'(provisional) →
    다음 20회차 추적 후 같은 방향이면 정식(maintained) 승격, 아니면 내림(discarded)
결과는 '경향'에 관한 것이며, 번호 조합의 1등 확률(1/8,145,060)을 바꾸지 않는다.

읽기: research_prize_stats · lotto_winning_numbers · winning_history · lottery_stores (크롤링 테이블은 읽기만)
쓰기: strategy_hypotheses · strategy_directions · strategy_runs (research_v14_strategy.sql) — 서버 전용
외부 사이트 접속 없음.

사용: python research_hypothesis_factory.py [--dry-run]
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import date, datetime, timezone

from scipy.stats import mannwhitneyu

import research_review_worker as R

VERSION = "hf-1.1"
DISCOVERY = (269, 1000)
CONFIRM_START = 1001
ALPHA = 0.05
MIN_N = 15
FORWARD_MIN = 10
TOTAL = 8145060
CAPITAL = ("서울", "경기", "인천")

# ── 어휘: 조건 (회차별 참/거짓) ─────────────────────────────────────
CONDITIONS = {
    "round_odd": "홀수 회차",
    "day_odd": "추첨일이 홀수 날짜",
    "early_month": "추첨일이 1~10일",
    "first_half": "상반기(1~6월)",
    "summer": "여름(6~8월)",
    "winter": "겨울(12~2월)",
    "prev_rank1_many": "직전 회차 1등 15명 이상",
    "prev_rank1_few": "직전 회차 1등 5명 이하",
    "sales_surge": "판매액이 직전 4회 평균보다 10% 이상 많음",
    "sales_drop": "판매액이 직전 4회 평균보다 5% 이상 적음",
    "prev_sum_high": "직전 당첨번호 합 160 이상",
    "prev_consec": "직전 당첨번호에 연속 번호 있음",
    "prev_low_heavy": "직전 당첨번호 중 1~12가 3개 이상",
}
# ── 어휘: 결과 (회차별 수치) ───────────────────────────────────────
OUTCOMES = {
    "R1": "1등 당첨자 쏠림 (실제 ÷ 무작위 기대)",
    "R2": "2등 당첨자 쏠림",
    "R3": "3등 당첨자 쏠림",
    "R4": "4등 당첨자 쏠림",
    "manual_share": "1등 중 수동·반자동 비율",
    "win_sum": "당첨번호 합",
    "win_odd": "당첨번호 중 홀수 개수",
    "win_consec": "당첨번호 연속 쌍 수",
    "win_low": "당첨번호 중 1~22 개수",
    "win_high40": "당첨번호 중 40 이상 개수",
    "first_capital_share": "1등 판매점 중 수도권(서울·경기·인천) 비율",
}
EXPECT = {"higher": "높다", "lower": "낮다"}
COMBOS = {1: 1, 2: 6, 3: 228, 4: 11115}

# 관리자(사장님) 제안 — 첫 방향 (AI 키가 없어도 공장이 도는지 보여주는 기본 방향)
SEED = {
    "title": "날짜·회차 홀짝과 계절이 당첨 결과에 영향을 주는가",
    "rationale": "관리자 제안: '짝수날', '홀수 회차에는 2등이 많다' 같은 달력 패턴을 체계적으로 검정한다.",
    "focus": "calendar",
    "hypotheses": [("round_odd", "R2", "higher"), ("day_odd", "R2", "higher"), ("round_odd", "R1", "higher"),
                   ("day_odd", "win_odd", "higher"), ("first_half", "R1", "higher"), ("summer", "manual_share", "higher")],
}


def statement(c, o, e):
    return f"{CONDITIONS[c]}일 때 {OUTCOMES[o]}가 {EXPECT[e]}"


def code_of(c, o, e):
    return f"{c}|{o}|{e}"


# ── 회차 데이터 ────────────────────────────────────────────────────
def load_rounds(db):
    ps = db.all("research_prize_stats", {"select": "round,draw_date,num1,num2,num3,num4,num5,num6,rank1_winners,rank2_winners,"
                                                   "rank3_winners,rank4_winners,total_sales_amount,manual_winners,semi_auto_winners",
                                         "official": "eq.true", "order": "round"})
    wh = db.all("winning_history", {"select": "round,dhlottery_code", "lottery_type": "eq.lotto", "prize_tier": "eq.first",
                                    "round": f"gte.{DISCOVERY[0]}", "order": "round,dhlottery_code"}, key="round")
    codes = sorted({r["dhlottery_code"] for r in wh if r["dhlottery_code"]})
    sido = {}
    for i in range(0, len(codes), 150):
        for s in db.get("lottery_stores", {"select": "dhlottery_code,region", "lottery_type": "eq.lotto",
                                           "dhlottery_code": f"in.({','.join(codes[i:i + 150])})"}):
            sido[s["dhlottery_code"]] = (s.get("region") or "").split(" ")[0]
    firsts = defaultdict(list)
    for r in wh:
        firsts[r["round"]].append(sido.get(r["dhlottery_code"], ""))
    rows, prev = [], None
    sales_hist = []
    for r in ps:
        g = (r["total_sales_amount"] or 0) / 1000
        if g <= 0:
            continue
        ns = sorted(r[f"num{i}"] for i in range(1, 7))
        d = date.fromisoformat(str(r["draw_date"])[:10])
        avg4 = sum(sales_hist[-4:]) / 4 if len(sales_hist) >= 4 else None
        f = firsts.get(r["round"], [])
        known = [s for s in f if s]
        x = {
            "round": r["round"],
            "cond": {
                "round_odd": r["round"] % 2 == 1, "day_odd": d.day % 2 == 1, "early_month": d.day <= 10,
                "first_half": d.month <= 6, "summer": d.month in (6, 7, 8), "winter": d.month in (12, 1, 2),
                "prev_rank1_many": prev is not None and prev["r1"] >= 15,
                "prev_rank1_few": prev is not None and prev["r1"] <= 5,
                "sales_surge": avg4 is not None and g >= avg4 * 1.10,
                "sales_drop": avg4 is not None and g <= avg4 * 0.95,
                "prev_sum_high": prev is not None and sum(prev["ns"]) >= 160,
                "prev_consec": prev is not None and any(b - a == 1 for a, b in zip(prev["ns"], prev["ns"][1:])),
                "prev_low_heavy": prev is not None and sum(n <= 12 for n in prev["ns"]) >= 3,
            },
            "out": {
                "R1": r["rank1_winners"] / (g * COMBOS[1] / TOTAL),
                "R2": (r["rank2_winners"] or 0) / (g * COMBOS[2] / TOTAL),
                "R3": (r["rank3_winners"] or 0) / (g * COMBOS[3] / TOTAL),
                "R4": (r["rank4_winners"] or 0) / (g * COMBOS[4] / TOTAL),
                "manual_share": ((r["manual_winners"] or 0) + (r["semi_auto_winners"] or 0)) / r["rank1_winners"]
                if r["rank1_winners"] else None,
                "win_sum": sum(ns), "win_odd": sum(n % 2 for n in ns),
                "win_consec": sum(b - a == 1 for a, b in zip(ns, ns[1:])),
                "win_low": sum(n <= 22 for n in ns), "win_high40": sum(n >= 40 for n in ns),
                "first_capital_share": sum(s in CAPITAL for s in known) / len(known) if known else None,
            },
        }
        rows.append(x)
        sales_hist.append(g)
        prev = {"r1": r["rank1_winners"], "ns": ns}
    return rows


# ── 가설 종류 (spec.kind) ─────────────────────────────────────────
KIND_LABEL = {"base": "기본", "revival": "회생", "supplement": "보충회생", "partial": "임시 일부 발췌", "applied": "응용"}
OUTCOME_FAMILY = {"R1": "pop", "R2": "pop", "R3": "pop", "R4": "pop", "manual_share": "pop",
                  "win_sum": "num", "win_odd": "num", "win_consec": "num", "win_low": "num", "win_high40": "num",
                  "first_capital_share": "store"}
REVIVAL_EVERY = 50        # 회생: 탈락 후 50회차마다, 탈락 뒤 새 회차만으로 재검정
PARTIAL_EVERY = 25        # 임시 일부 발췌: 25회차마다 최근 100회만 검정
PARTIAL_WINDOW = 100
PARTIAL_ALPHA = 0.01      # 사후에 고른 구간이라 기준을 더 엄격하게
PARTIAL_TRACK = 20        # 임시는 다음 20회차만 추적 → 정식 승격 또는 내림
SUPPLEMENT_ALPHA = 0.01   # 보충회생(조건 2개)은 조합 수가 많아 발견 기준을 더 엄격하게
NEAR_MISS_P = 0.20        # 보충회생 대상: 발견 구간에서 방향은 맞고 p < 0.20 이었던 기각 가설
MAX_SUPPLEMENT = 36
CLOSED = ("rejected", "discarded")
EXCLUSIVE = [{"summer", "winter"}, {"sales_surge", "sales_drop"}, {"prev_rank1_many", "prev_rank1_few"}]  # 동시에 참일 수 없는 조건


def conds_of(spec):
    return [c for c in (spec.get("condition"), spec.get("condition2")) if c and c != "none"]


def valid(spec):
    cs = conds_of(spec)
    return bool(cs) and all(c in CONDITIONS for c in cs) and spec.get("outcome") in OUTCOMES and spec.get("expect") in EXPECT


def spec_statement(spec):
    return f"{'이면서 '.join(CONDITIONS[c] for c in conds_of(spec))}일 때 {OUTCOMES[spec['outcome']]}가 {EXPECT[spec['expect']]}"


def spec_code(spec):
    return f"{'+'.join(sorted(conds_of(spec)))}|{spec['outcome']}|{spec['expect']}"


def kind_of(h):
    return (h.get("spec") or {}).get("kind") or "base"


# ── 검정 ──────────────────────────────────────────────────────────
def test(rows, spec, lo, hi, min_n=MIN_N):
    cs, o, e = conds_of(spec), spec["outcome"], spec["expect"]
    a, b = [], []
    for x in rows:
        if lo <= x["round"] <= hi and x["out"][o] is not None:
            (a if all(x["cond"][c] for c in cs) else b).append(x["out"][o])
    res = {"from": lo, "to": hi, "n_cond": len(a), "n_other": len(b)}
    if len(a) < min_n or len(b) < min_n:
        res["status"] = "small"
        return res
    p = mannwhitneyu(a, b, alternative="greater" if e == "higher" else "less").pvalue
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    res.update(mean_cond=round(ma, 4), mean_other=round(mb, 4), ratio=round(ma / mb, 4) if mb else None,
               p=round(float(p), 4), direction_ok=(ma > mb) if e == "higher" else (ma < mb))
    return res


def bh(pvals):
    """Benjamini-Hochberg: 통과 여부 리스트"""
    m = len(pvals)
    order = sorted(range(m), key=lambda i: pvals[i])
    k = 0
    for rank, i in enumerate(order, 1):
        if pvals[i] <= ALPHA * rank / m:
            k = rank
    passed = set(order[:k])
    return [i in passed for i in range(m)]


def fmt(t):
    if t.get("status") == "small":
        return f"표본 부족(조건 {t['n_cond']}회)"
    return f"조건 {t['n_cond']}회 평균 {t['mean_cond']:.3f} vs 나머지 {t['mean_other']:.3f} (p {t['p']:.3f})"


# ── 파생: 보충회생 · 응용 · 회생 · 임시 일부 발췌 ────────────────────
def derive(rows, hyps, latest):
    """새 가설 [(row)] 과 부모 갱신 [(id, patch)]"""
    codes = {h["code"] for h in hyps}
    new, parent_patch = [], []

    def child(parent, spec, code, status="proposed", **extra):
        if code in codes:
            return None
        codes.add(code)
        r = {"direction_id": parent.get("direction_id"), "code": code, "statement": spec_statement(spec),
             "spec": spec, "created_round": latest, "status": status}
        r.update(extra)
        new.append(r)
        return r

    # 보충회생: 아깝게 기각된 기본·응용 가설에 조건 하나를 보탠다 (부모 발견 p 작은 순, 회당 최대 MAX_SUPPLEMENT)
    near = [h for h in hyps if h["status"] == "rejected" and kind_of(h) in ("base", "applied") and len(conds_of(h["spec"])) == 1
            and (h.get("discovery") or {}).get("direction_ok") and (h["discovery"].get("p") or 1) < NEAR_MISS_P]
    budget = MAX_SUPPLEMENT
    for h in sorted(near, key=lambda h: h["discovery"]["p"]):
        c = h["spec"]["condition"]
        for c2 in CONDITIONS:
            if budget <= 0:
                break
            if c2 == c or any({c, c2} <= ex for ex in EXCLUSIVE):
                continue
            spec = {"condition": c, "condition2": c2, "outcome": h["spec"]["outcome"], "expect": h["spec"]["expect"],
                    "kind": "supplement", "parent": h["code"]}
            if child(h, spec, spec_code(spec)):
                budget -= 1

    # 응용: 통과·유지 가설에서 같은 조건 · 같은 계열의 다른 결과
    for h in hyps:
        if h["status"] not in ("validated", "maintained"):
            continue
        o = h["spec"]["outcome"]
        for o2, fam in OUTCOME_FAMILY.items():
            if o2 == o or fam != OUTCOME_FAMILY.get(o):
                continue
            spec = {k: v for k, v in h["spec"].items() if k in ("condition", "condition2", "expect")}
            spec.update(outcome=o2, kind="applied", parent=h["code"])
            child(h, spec, spec_code(spec))

    live_children = defaultdict(set)
    for h in hyps:
        if h["status"] in ("validated", "maintained", "provisional", "proposed"):
            par = (h.get("spec") or {}).get("parent")
            if par:
                live_children[par].add(kind_of(h))

    # 회생: 탈락 뒤 새 회차만으로 재검정 (50회차마다) / 임시 일부 발췌: 최근 100회만 (25회차마다)
    rv_queue, pt_queue = [], []
    for h in hyps:
        if h["status"] not in CLOSED or kind_of(h) == "partial" or not valid(h["spec"]):
            continue
        fw = dict(h.get("forward") or {})
        dead_at = fw.get("closed_at") or h.get("last_round") or h["created_round"]
        upd = {}
        if "revival" not in live_children[h["code"]] and latest - fw.get("rv_checked", dead_at) >= REVIVAL_EVERY:
            t = test(rows, h["spec"], dead_at + 1, latest)
            if t.get("status") != "small":
                upd["rv_checked"] = latest
                if t["direction_ok"]:
                    rv_queue.append((h, t))
        if "partial" not in live_children[h["code"]] and latest - fw.get("pt_checked", dead_at) >= PARTIAL_EVERY:
            t = test(rows, h["spec"], latest - PARTIAL_WINDOW + 1, latest)
            if t.get("status") != "small":
                upd["pt_checked"] = latest
                if t["direction_ok"] and t["p"] < PARTIAL_ALPHA:
                    pt_queue.append((h, t))
        if upd:
            parent_patch.append((h["id"], {"forward": dict(fw, closed_at=dead_at, **upd)}))
    if rv_queue:
        for (h, t), ok in zip(rv_queue, bh([t["p"] for _, t in rv_queue])):
            if ok:
                spec = dict(h["spec"], kind="revival", parent=h["code"])
                child(h, spec, f"{spec_code(h['spec'])}#rv{latest}", status="validated", discovery=t,
                      forward={"start": latest + 1},
                      verdict=f"회생 — 탈락 뒤 새 회차({t['from']}~{t['to']}회)에서 효과가 나타남: {fmt(t)}. 새 회차 추적부터 다시")
    if pt_queue:
        for (h, t), ok in zip(pt_queue, bh([t["p"] for _, t in pt_queue])):
            if ok:
                spec = dict(h["spec"], kind="partial", parent=h["code"])
                child(h, spec, f"{spec_code(h['spec'])}#pt{latest}", status="provisional", discovery=t,
                      forward={"start": latest + 1, "until": latest + PARTIAL_TRACK},
                      verdict=f"임시 일부 발췌 — 전체 기간엔 없지만 최근 {PARTIAL_WINDOW}회({t['from']}~{t['to']}회)에서만 효과: "
                              f"{fmt(t)}. 다음 {PARTIAL_TRACK}회차 추적 후 정식 승격 또는 내림")
    return new, parent_patch


def evaluate(rows, hyps, latest):
    """가설 상태 갱신 목록 [(id, patch)]"""
    out = []
    confirm_queue = []
    for h in hyps:
        s = h["spec"]
        if not valid(s):
            if h["status"] != "unsupported":
                out.append((h["id"], {"status": "unsupported", "verdict": "검정 불가 — 저장된 데이터로 계산할 수 없는 조건·결과 (데이터 미확보)"}))
            continue
        if h["status"] == "proposed":
            d = test(rows, s, *DISCOVERY)
            cf = test(rows, s, CONFIRM_START, h["created_round"])
            a = SUPPLEMENT_ALPHA if kind_of(h) == "supplement" else ALPHA
            if d.get("status") == "small" or cf.get("status") == "small":
                # 발견·확인 구간은 고정이라 표본이 더 늘지 않는다 → 판정 불가로 닫는다 (회생·임시 발췌 검사는 계속)
                out.append((h["id"], {"status": "rejected", "discovery": d, "confirm": cf, "last_round": latest,
                                      "forward": {"closed_at": latest},
                                      "verdict": f"판정 불가 — 조건이 드물어 표본 부족: 발견 {fmt(d)} · 확인 {fmt(cf)}"}))
            elif not (d["p"] < a and d["direction_ok"]):
                out.append((h["id"], {"status": "rejected", "discovery": d, "confirm": cf, "last_round": latest,
                                      "forward": {"closed_at": latest},
                                      "verdict": f"기각 — 발견 구간에서 차이 없음 (기준 p<{a}): {fmt(d)}"}))
            else:
                confirm_queue.append((h, d, cf))
        elif h["status"] in ("validated", "maintained"):
            start = (h.get("forward") or {}).get("start") or (h["last_round"] or h["created_round"]) + 1
            fw = test(rows, s, start, latest)
            fw["start"] = start
            patch = {"forward": fw, "last_round": latest}
            if fw.get("n_cond", 0) >= FORWARD_MIN and fw.get("status") != "small":
                if fw["direction_ok"]:
                    patch.update(status="maintained", verdict=f"유지 — 통과 이후 새 회차에서도 같은 방향: {fmt(fw)}")
                else:
                    patch.update(status="discarded", verdict=f"폐기 — 통과 이후 새 회차에서 방향이 뒤집힘: {fmt(fw)}")
                    patch["forward"] = dict(fw, closed_at=latest)
            else:
                base = (h.get("verdict") or "검증 통과").split(" · 새 회차 추적 중")[0]
                patch["verdict"] = base if h["status"] == "maintained" else \
                    f"{base} · 새 회차 추적 중 (조건 회차 {fw.get('n_cond', 0)}/{FORWARD_MIN})"
            out.append((h["id"], patch))
        elif h["status"] == "provisional":
            f0 = h.get("forward") or {}
            start, until = f0.get("start", latest + 1), f0.get("until", latest)
            fw = test(rows, s, start, latest, min_n=5)
            fw.update(start=start, until=until)
            patch = {"forward": fw, "last_round": latest}
            if latest >= until:
                if fw.get("status") != "small" and fw["direction_ok"]:
                    patch.update(status="maintained", verdict=f"임시 → 정식 승격 — 추적 {PARTIAL_TRACK}회차 동안 같은 방향: {fmt(fw)}")
                else:
                    patch.update(status="discarded", verdict=f"임시 기한 만료 — 추적 {PARTIAL_TRACK}회차에서 유지 안 됨: {fmt(fw)}")
                    patch["forward"] = dict(fw, closed_at=latest)
            else:
                patch["verdict"] = (h.get("verdict") or "").split(" · 임시 추적")[0] + \
                    f" · 임시 추적 {max(0, latest - start + 1)}/{PARTIAL_TRACK}회"
            out.append((h["id"], patch))
    if confirm_queue:
        ok = bh([cf["p"] for _, _, cf in confirm_queue])
        for (h, d, cf), passed in zip(confirm_queue, ok):
            if passed and cf["direction_ok"]:
                out.append((h["id"], {"status": "validated", "discovery": d, "confirm": cf, "last_round": latest,
                                      "forward": {"start": latest + 1},
                                      "verdict": f"검증 통과 — 발견 {fmt(d)} · 확인 {fmt(cf)} (다중 비교 보정 통과)"}))
            else:
                out.append((h["id"], {"status": "rejected", "discovery": d, "confirm": cf, "last_round": latest,
                                      "forward": {"closed_at": latest},
                                      "verdict": f"기각 — 발견 구간은 통과했지만 확인 구간에서 재현 안 됨: {fmt(cf)}"}))
    return out


# ── 저장 ──────────────────────────────────────────────────────────
SELECT = "id,code,spec,status,discovery,confirm,forward,verdict,created_round,last_round,direction_id"


def _existing(db, params, dry):
    """전략 테이블 조회 — 드라이런에서 테이블이 아직 없으면 빈 목록"""
    try:
        return db.get("strategy_hypotheses", params)
    except RuntimeError:
        if dry:
            return []
        raise


def ensure_seed(db, latest, dry):
    have = {h["code"] for h in _existing(db, {"select": "code"}, dry)}
    todo = [t for t in SEED["hypotheses"] if code_of(*t) not in have]
    if not todo:
        return 0
    if dry:
        return len(todo)
    did = db.insert("strategy_directions", {"after_round": latest, "source": "manual", "title": SEED["title"],
                                            "rationale": SEED["rationale"], "focus": SEED["focus"]})
    add_hypotheses(db, did, todo, latest)
    return len(todo)


def add_hypotheses(db, direction_id, specs, latest):
    """specs: [(condition, outcome, expect)] 또는 [(condition, condition2, outcome, expect)] — 이미 있는 code 는 건너뜀"""
    rows = []
    for t in specs:
        c, c2, o, e = (t[0], None, t[1], t[2]) if len(t) == 3 else t
        spec = {"condition": c, "outcome": o, "expect": e, "kind": "base"}
        if c2 and c2 != "none" and c2 != c:
            spec.update(condition2=c2, kind="supplement")
        if valid(spec):
            rows.append({"direction_id": direction_id, "code": spec_code(spec), "statement": spec_statement(spec),
                         "spec": spec, "created_round": latest})
    db.upsert("strategy_hypotheses", rows, "code", ignore=True)
    return len(rows)


def run(db, dry=False):
    latest = db.get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})[0]["round"]
    seeded = ensure_seed(db, latest, dry)
    rows = load_rounds(db)
    hyps = _existing(db, {"select": SELECT}, dry)
    if dry and seeded:   # 드라이런: 아직 저장 안 된 기본 가설도 계산해서 보여준다
        hyps += [{"id": f"seed-{i}", "code": code_of(*t), "direction_id": None,
                  "spec": {"condition": t[0], "outcome": t[1], "expect": t[2], "kind": "base"},
                  "status": "proposed", "forward": None, "verdict": None, "created_round": latest, "last_round": None}
                 for i, t in enumerate(SEED["hypotheses"])]
    now = datetime.now(timezone.utc).isoformat()

    # 1) 판정 (기존 가설)
    updates = evaluate(rows, hyps, latest)
    # 2) 판정 결과를 반영한 상태로 파생 (보충회생 · 응용 · 회생 · 임시 일부 발췌)
    by_id = {h["id"]: h for h in hyps}
    for hid, patch in updates:
        by_id[hid].update(patch)
    new, parent_patch = derive(rows, hyps, latest)
    # 3) 새로 만든 '제안' 가설도 바로 판정
    new_proposed = [dict(r, id=f"new-{i}", last_round=None, forward=r.get("forward")) for i, r in enumerate(new)
                    if r["status"] == "proposed"]
    new_updates = {u[0]: u[1] for u in evaluate(rows, new_proposed, latest)}
    for r, tmp in zip([r for r in new if r["status"] == "proposed"], new_proposed):
        r.update(new_updates.get(tmp["id"], {}))

    counts = defaultdict(int)
    for hid, patch in updates:
        counts[patch.get("status", "updated")] += 1
        code = by_id[hid]["code"]
        if "status" in patch:
            print(f"  {code:44s} → {patch['status']} · {patch.get('verdict', '')}")
        if not dry:
            db.patch("strategy_hypotheses", {"id": f"eq.{hid}"}, dict(patch, updated_at=now))
    for hid, patch in parent_patch:
        if not dry:
            db.patch("strategy_hypotheses", {"id": f"eq.{hid}"}, patch)
    made = defaultdict(int)
    for r in new:
        made[r["spec"]["kind"]] += 1
        counts[r["status"]] += 1
        print(f"  + [{KIND_LABEL[r['spec']['kind']]}] {r['code']:40s} → {r['status']} · {r.get('verdict', '')}")
    if new and not dry:
        keys = ("direction_id", "code", "statement", "spec", "created_round", "status", "discovery", "confirm",
                "forward", "verdict", "last_round")
        db.upsert("strategy_hypotheses", [dict({k: r.get(k) for k in keys}, updated_at=now) for r in new], "code", ignore=True)
    stats = {"version": VERSION, "rounds": len(rows), "evaluated": len(updates) + len(new), "seeded": seeded,
             "derived": dict(made), "by_status": dict(counts)}
    print(json.dumps(stats, ensure_ascii=False))
    if not dry:
        db.insert("strategy_runs", {"kind": "factory", "status": "success", "after_round": latest, "stats": stats})
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
    if not a.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("저장은 서버(GitHub Actions)에서만 합니다. 로컬은 --dry-run 만 허용")
    run(R.Db(url, key, dry=a.dry_run), a.dry_run)


if __name__ == "__main__":
    main()
