"""
회차 검증 보고 · 지방장 보고 (db-1.0) — 브리핑 '회차 검증' · '지방장보고' 탭의 서버 계산

매 회차 추첨 후, 지난 회차(D)에 브리핑이 실제로 추천한 것을 그대로 꺼내 채점하고 다음 회차(N=D+1)와 비교한다.
  · 번호: 사전 등록 장부(research_predictions)의 공식 5세트 · 비인기 추천 · 구매예측 · 번호 엔진 · 무작위 대조군
          → 세트별 일치 번호·등수, 누적 성적(무작위 기대 대비 z·p), 이번 당첨번호 특징의 과거 빈도
  · 판매점: 브리핑 '이번 주 엔진 추천 명당' 선정 규칙(중앙 엔진 주목 지역 상위 5곳의 지방장 납품 1위 → 전국 상위 후보)을
            D 회차 동결 자료로 그대로 재현해 1·2등 적중 확인, N 회차 선정과 비교(유지·신규·제외, 모델 추정 p_first 변화)
  · 지방장: 238명 각자의 D 회차 TOP5 · 적중 · 지역 1등 놓친 사례 · 가설 판정 변화 · N 회차 TOP5 변경
  · 검수: 실무 분석 관점(무엇이 근접했고 무엇을 놓쳤나) · 수학 관점(무작위 대비 유의성, 다중 비교) — 저장된 수치로 만든
          규칙 기반 자동 검수 문장이다. 사람이 검수한 것이 아니다.

원칙: 모든 6개 번호 조합의 1등 확률은 같다(1/8,145,060). 판매점 p_first 는 모델 추정치이며 한 장당 당첨확률이 아니다.
      한 회차 결과로 가설을 채택·폐기하지 않는다(누적 검정 기준). 수치가 없으면 '데이터 미확보'.
읽기: lotto_winning_numbers · winning_history · lottery_stores · research_predictions · research_results ·
      research_agent_central · research_agent_deliveries · research_review_agent_rounds · research_review_agent_cards ·
      research_review_rounds · research_prize_stats  (크롤링 테이블은 읽기만)
쓰기: research_results (round_debrief · agent_debrief, model_version db-1.0) — 서버(service_role)만

사용: python research_debrief_worker.py [--round D] [--dry-run]
"""

import argparse
import json
import math
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone

import research_review_worker as R

VERSION = "db-1.0"
AGENT_MODEL = "ag-1.1"
TOTAL = 8145060
COMBOS = {1: 1, 2: 6, 3: 228, 4: 11115, 5: 182780}
P_PRIZE = sum(COMBOS.values()) / TOTAL                       # 한 세트가 3개 이상 일치(5등 이상)할 확률 2.38%
MEAN0 = 6 * 6 / 45                                           # 무작위 세트 기대 일치 0.8
VAR0 = 6 * (6 / 45) * (39 / 45) * (39 / 44)                  # 초기하 분산 0.6145
GROUPS = [  # (key, algorithm, 고정 version 또는 None=최신, 이름, 역할)
    ("official", "official_final", "fr-1.0", "공식 최종 추천번호", "브리핑 ①"),
    ("popularity", "popularity_pick", "pop-1.0", "비인기 추천조합", "브리핑 ②"),
    ("purchase", "purchase_prediction", None, "구매예측 번호", "브리핑 구매예측"),
    ("number_engine", "number_engine", None, "Number 엔진 기본 조합", "연구용"),
    ("random", "random_control", None, "무작위 대조군", "비교 기준"),
]
TIER = {"first": 1, "second": 2}
SMALL_SETS = 100                                             # 누적 세트가 이보다 적으면 유의성 판정 보류


def norm_cdf(z):
    return 0.5 * (1 + math.erf(z / math.sqrt(2)))


def pct(x, d=1):
    return f"{100 * x:.{d}f}%"


def sets_of(v):
    return [sorted(int(n) for n in s) for s in (v or []) if s and len(s) == 6]


def ver_key(v):
    try:
        return tuple(int(x) for x in str(v).lstrip("rpvfdb-").split("."))
    except ValueError:
        return (0,)


# ── 데이터 ────────────────────────────────────────────────────────
def load(db, D):
    N = D + 1
    wins = {r["round"]: r for r in db.all("lotto_winning_numbers", {"select": "round,draw_date,num1,num2,num3,num4,num5,num6,bonus",
                                                                    "order": "round"})}
    regs = db.all("research_predictions", {"select": "algorithm,version,target_round,sets,generated_at,deadline_at,pre_deadline,status",
                                           "target_round": f"lte.{N}", "order": "target_round,algorithm,version"})
    wh = db.get("winning_history", {"select": "dhlottery_code,prize_tier,purchase_method", "round": f"eq.{D}",
                                    "lottery_type": "eq.lotto", "limit": "1000"})
    central = {}
    for t in (D, N):
        c = db.get("research_agent_central", {"select": "target_round,training_end_round,focus_regions,store_top,created_at",
                                              "model_version": f"eq.{AGENT_MODEL}", "target_round": f"eq.{t}"})
        central[t] = c[0] if c else None
    deliv = {}
    for t in (D, N):
        deliv[t] = db.all("research_agent_deliveries", {
            "select": "agent_id,store_code,rank,score,p_first,store_name,address,history",
            "model_version": f"eq.{AGENT_MODEL}", "target_round": f"eq.{t}", "mode": "eq.live",
            "order": "agent_id,rank,store_code"})
    ar = db.get("research_review_agent_rounds", {"select": "target_round,prediction_mode,data_through_round,agent_ids,entries,summary,spatial",
                                                 "review_version": f"eq.{R.REVIEW_VERSION}", "target_round": f"eq.{D}"})
    rr = db.get("research_review_rounds", {"select": "status,corrections,signals,spatial,regions",
                                           "review_version": f"eq.{R.REVIEW_VERSION}", "target_round": f"eq.{D}"})
    cards = {r["agent_id"]: r for r in db.all("research_review_agent_cards", {
        "select": "agent_id,sido,unit_name,n_stores,hypotheses,cards", "review_version": f"eq.{R.REVIEW_VERSION}",
        "order": "agent_id"})}
    fr_next = db.get("research_results", {"select": "id,training_end_round,payload->sets,created_at",
                                          "research_type": "eq.final_recommendation", "model_version": "eq.fr-1.0",
                                          "target_round": f"eq.{N}", "training_end_round": f"eq.{D}"})
    pop = {}
    for t in (D, N):
        p = db.get("research_results", {"select": "payload", "research_type": "eq.number_popularity", "model_version": "eq.pop-1.0",
                                        "target_round": f"eq.{t}", "training_end_round": f"eq.{t - 1}"})
        pop[t] = p[0]["payload"] if p else None
    prize = db.get("research_prize_stats", {"select": "round,rank1_winners,rank1_amount,total_sales_amount,rank4_winners,"
                                                      "auto_winners,manual_winners,semi_auto_winners", "round": f"eq.{D}"})
    codes = {r["dhlottery_code"] for r in wh}
    names = {}
    cl = sorted(c for c in codes if c)
    for i in range(0, len(cl), 150):
        for r in db.get("lottery_stores", {"select": "dhlottery_code,store_name,address", "lottery_type": "eq.lotto",
                                           "dhlottery_code": f"in.({','.join(cl[i:i + 150])})"}):
            names.setdefault(r["dhlottery_code"], (r["store_name"], r.get("address")))
    return dict(D=D, N=N, wins=wins, regs=regs, wh=wh, central=central, deliv=deliv,
                agent_round=ar[0] if ar else None, review=rr[0] if rr else None, cards=cards,
                fr_next=fr_next[0] if fr_next else None, pop=pop, prize=prize[0] if prize else None, names=names)


def win_of(d, t):
    w = d["wins"].get(t)
    return (sorted(w[f"num{i}"] for i in range(1, 7)), w["bonus"], w["draw_date"]) if w else (None, None, None)


# ── 번호 ──────────────────────────────────────────────────────────
def pick_reg(regs, t, algo, version):
    rows = [r for r in regs if r["target_round"] == t and r["algorithm"] == algo and (version is None or r["version"] == version)]
    return max(rows, key=lambda r: ver_key(r["version"])) if rows else None


def track_record(d, algo, version):
    """장부 등록·추첨 완료 회차 누적 성적 (사전 등록분만). z = (일치합 − 0.8·세트수) / √(0.6145·세트수)"""
    rounds, S, M, ge3, prizes = 0, 0, 0, 0, Counter()
    for r in d["regs"]:
        if r["algorithm"] != algo or (version and r["version"] != version) or not r.get("pre_deadline"):
            continue
        actual, bonus, _ = win_of(d, r["target_round"])
        if not actual:
            continue
        rounds += 1
        for s in sets_of(r["sets"]):
            sc = R.score_set(s, actual, bonus)
            S += 1
            M += sc["matches"]
            ge3 += sc["matches"] >= 3
            if sc["rank"]:
                prizes[sc["rank"]] += 1
    if not S:
        return None
    z = (M - MEAN0 * S) / math.sqrt(VAR0 * S)
    lam = S * P_PRIZE
    return {"rounds": rounds, "sets": S, "mean": round(M / S, 3), "expected_mean": round(MEAN0, 3),
            "ge3": ge3, "expected_ge3": round(lam, 2), "p_ge3": round(R.poisson_sf(ge3, lam), 4),
            "z": round(z, 2), "p_one_sided": round(1 - norm_cdf(z), 4), "prizes": {str(k): v for k, v in sorted(prizes.items())}}


def combo_traits(d, actual, D):
    """이번 당첨번호 특징 · 과거(1~D−1회) 같은 특징이 나온 회차 비율 — 예측 가능했는지 감각용"""
    def tr(ns):
        ns = sorted(ns)
        return {"consec": sum(b - a == 1 for a, b in zip(ns, ns[1:])), "sum": sum(ns), "odd": sum(n % 2 for n in ns),
                "span": ns[-1] - ns[0], "le12": sum(n <= 12 for n in ns), "ge40": sum(n >= 40 for n in ns),
                "decades": len({n // 10 for n in ns})}
    me = tr(actual)
    past = [tr(win_of(d, t)[0]) for t in d["wins"] if t < D]
    n = len(past)
    out = {"traits": me, "past_rounds": n}
    if n:
        out["share"] = {
            "consec_ge": round(sum(p["consec"] >= me["consec"] for p in past) / n, 4),
            "span_le": round(sum(p["span"] <= me["span"] for p in past) / n, 4),
            "sum_abs_ge": round(sum(abs(p["sum"] - 138) >= abs(me["sum"] - 138) for p in past) / n, 4),
            "decades_le": round(sum(p["decades"] <= me["decades"] for p in past) / n, 4),
        }
    return out


def numbers_block(d):
    D, N = d["D"], d["N"]
    actual, bonus, draw_date = win_of(d, D)
    groups = []
    for key, algo, version, label, role in GROUPS:
        r = pick_reg(d["regs"], D, algo, version)
        g = {"key": key, "label": label, "role": role, "algorithm": algo}
        if not r:
            g["status"] = f"{D}회 사전 등록 없음"
        else:
            sc = R.score_sets(sets_of(r["sets"]), actual, bonus) if actual else None
            g.update(version=r["version"], pre_deadline=bool(r.get("pre_deadline")), generated_at=r.get("generated_at"))
            if sc:
                for s in sc["sets"]:
                    s["hits"] = sorted(set(s["numbers"]) & set(actual))
                g.update(sets=sc["sets"], best_matches=sc["best_matches"], best_rank=sc["best_rank"], mean=sc["mean_matches"],
                         p_best_or_more=round(1 - (1 - _p_ge(sc["best_matches"])) ** len(sc["sets"]), 4))
            g["track"] = track_record(d, algo, r["version"])
        nr = pick_reg(d["regs"], N, algo, version)
        if nr:
            g["next"] = {"version": nr["version"], "sets": sets_of(nr["sets"]), "generated_at": nr.get("generated_at")}
        groups.append(g)
    return {"actual": actual, "bonus": bonus, "draw_date": draw_date, "groups": groups,
            "traits": combo_traits(d, actual, D) if actual else None}


def _p_ge(m):
    """한 세트가 m개 이상 일치할 확률 (초기하)"""
    return sum(math.comb(6, k) * math.comb(39, 6 - k) for k in range(m, 7)) / TOTAL


def popularity_check(d):
    """이번 당첨조합을 인기도 모델은 어떻게 봤나 (D−1회 자료로 학습) ↔ 실제 1등·4등 당첨자 쏠림"""
    pz = d["prize"]
    actual, _, _ = win_of(d, d["D"])
    if not pz or not actual or not pz.get("total_sales_amount"):
        return {"status": "당첨자 수 미확보"}
    games = pz["total_sales_amount"] / 1000
    out = {"rank1_winners": pz["rank1_winners"], "rank1_expected": round(games / TOTAL, 2),
           "R1": round(pz["rank1_winners"] / (games / TOTAL), 3),
           "R4": round(pz["rank4_winners"] / (games * COMBOS[4] / TOTAL), 3) if pz.get("rank4_winners") else None,
           "manual_rank1": (pz.get("manual_winners") or 0) + (pz.get("semi_auto_winners") or 0), "rank1_amount": pz.get("rank1_amount")}
    try:
        import research_popularity as P
        from research_region_worker import Db as PDb
        data = [r for r in P.load_rounds(PDb(_ENV["url"], _ENV["key"])) if r["round"] < d["D"]]
        prev, _, _ = win_of(d, d["D"] - 1)
        sc = P.Scorer(data, prev, seed=P.SEED + d["D"])
        s = sc.score(actual)
        out.update(model_pct=s["popularity_pct"], model_training_end=data[-1]["round"])
    except Exception as e:  # 인기도 모델 실패는 보고서 전체를 막지 않는다
        out["model_error"] = str(e)[:200]
    return out


# ── 판매점 (브리핑 선정 재현) ──────────────────────────────────────
def briefing_picks(central, deliv):
    """master_briefing_service.selectAgentPicks 와 같은 규칙"""
    if not central:
        return []
    rank1 = {}
    for x in deliv:
        if x["rank"] == 1:
            rank1.setdefault(x["agent_id"], x)
    focus = sorted([f for f in central.get("focus_regions") or [] if f.get("region_id")],
                   key=lambda f: f.get("rank") or 1 << 30)
    out, used = [], set()
    for f in focus[:5]:
        x = rank1.get(f["region_id"])
        if not x or not x["store_code"] or x["store_code"] in used:
            continue
        used.add(x["store_code"])
        out.append({"code": x["store_code"], "name": x.get("store_name"), "agent_id": f["region_id"], "source": "focus",
                    "focus_rank": f.get("rank"), "region_p": f.get("p"), "p_first": x.get("p_first"), "score": x.get("score")})
    for i, s in enumerate(central.get("store_top") or []):
        if len(out) >= 5:
            break
        if not s.get("store_code") or s["store_code"] in used:
            continue
        used.add(s["store_code"])
        out.append({"code": s["store_code"], "name": s.get("name"), "agent_id": s.get("agent_id"), "source": "store_top",
                    "top_rank": i + 1, "p_first": s.get("p_first"), "score": s.get("score")})
    return out


def stores_block(d):
    D, N = d["D"], d["N"]
    tier = {}
    for r in d["wh"]:
        t = TIER.get(r["prize_tier"])
        if t:
            tier[r["dhlottery_code"]] = min(t, tier.get(r["dhlottery_code"], 9))
    prev = briefing_picks(d["central"][D], d["deliv"][D])
    for p in prev:
        p["tier"] = tier.get(p["code"], 0)
    nxt = briefing_picks(d["central"][N], d["deliv"][N])
    prev_codes = {p["code"]: p for p in prev}
    for p in nxt:
        o = prev_codes.get(p["code"])
        p["status"] = "kept" if o else "new"
        if o:
            p["p_first_prev"] = o.get("p_first")
    dropped = [{"code": p["code"], "name": p["name"], "agent_id": p["agent_id"], "tier": p["tier"]}
               for p in prev if p["code"] not in {x["code"] for x in nxt}]
    firsts = [{"code": c, "name": d["names"].get(c, (None,))[0], "address": d["names"].get(c, (None, None))[1]}
              for c, t in tier.items() if t == 1]
    sm = (d["agent_round"] or {}).get("summary") or {}
    exp_pick = sum(p.get("p_first") or 0 for p in prev)
    return {"briefing_prev": prev, "briefing_next": nxt, "dropped": dropped,
            "prev_hits_first": sum(p["tier"] == 1 for p in prev), "prev_hits_second": sum(p["tier"] == 2 for p in prev),
            "prev_expected_first": round(exp_pick, 3),
            "first_stores": firsts, "first_count": len(firsts), "second_count": sum(1 for t in tier.values() if t == 2),
            "central_ready": {"prev": bool(d["central"][D]), "next": bool(d["central"][N])},
            "agents": {"top_first_hits": sm.get("top_first_hits"), "uniform_expected": sm.get("top_expected_uniform"),
                       "history_top5": sm.get("history_first_hits5"), "first_winners": sm.get("first_winners"),
                       "outside": sm.get("outside_winners"), "live_changes": sm.get("live_changes"),
                       "new_hypotheses": sm.get("new_hypotheses"), "changes": sm.get("changes")}}


# ── 지방장 ────────────────────────────────────────────────────────
def agent_label(a):
    return "인터넷 판매" if a == "internet" else a.replace("|", " ")


def agents_block(d):
    D, N = d["D"], d["N"]
    tier = {}
    for r in d["wh"]:
        t = TIER.get(r["prize_tier"])
        if t:
            tier[r["dhlottery_code"]] = min(t, tier.get(r["dhlottery_code"], 9))
    by = {t: defaultdict(list) for t in (D, N)}
    for t in (D, N):
        for x in d["deliv"][t]:
            if x["rank"] <= 5:
                by[t][x["agent_id"]].append(x)
    ar = d["agent_round"] or {}
    ents = dict(zip(ar.get("agent_ids") or [], ar.get("entries") or []))
    ids = sorted(set(by[D]) | set(by[N]) | set(ents))
    out = []
    for a in ids:
        prev = sorted(by[D].get(a, []), key=lambda x: x["rank"])
        nxt = sorted(by[N].get(a, []), key=lambda x: x["rank"])
        e = ents.get(a) or {}
        pc = {x["store_code"]: x for x in prev}
        row = {
            "id": a, "label": agent_label(a), "n": e.get("n"),
            "prev": [[x["store_code"], x.get("store_name"), x["rank"], round(x.get("p_first") or 0, 5), tier.get(x["store_code"], 0)]
                     for x in prev],
            "next": [[x["store_code"], x.get("store_name"), x["rank"], round(x.get("p_first") or 0, 5),
                      "kept" if x["store_code"] in pc else "new", pc[x["store_code"]]["rank"] if x["store_code"] in pc else None]
                     for x in nxt],
            "dropped": [[x["store_code"], x.get("store_name"), x["rank"], tier.get(x["store_code"], 0)]
                        for x in prev if x["store_code"] not in {y["store_code"] for y in nxt}],
            "h": e.get("h"), "x": e.get("x"),
            # 지역 1등 [판매점, 사전 순위(전체 n곳 중), TOP 안 순위 또는 null]
            "firsts": [[w[0], d["names"].get(w[0], (None,))[0], w[1], w[2]] for w in e.get("w", [])],
            "changes": len(e.get("c", [])), "live_changes": sum(1 for c in e.get("c", []) if c[4] != c[5]),
            "routine": e.get("cc", 0), "new_hyp": e.get("nw", 0),
            "hyp": (d["cards"].get(a) or {}).get("hypotheses") or {},
        }
        row["note"] = agent_note(row)
        out.append(row)
    return out


def agent_note(r):
    parts = []
    hits = sum(1 for p in r["prev"] if p[4] == 1)
    seconds = sum(1 for p in r["prev"] if p[4] == 2)
    if r["firsts"]:
        parts.append(f"지역 1등 {len(r['firsts'])}곳")
        if hits:
            parts.append(f"TOP5 1등 적중 {hits}곳" + (f"(기대 {r['x'][2]:.2f})" if r.get("x") else ""))
        miss = [f for f in r["firsts"] if f[3] is None]
        if miss:
            m = min(miss, key=lambda f: f[2] or 1 << 30)
            parts.append(f"놓친 1등 {m[1] or m[0]}(사전 {m[2]}위/{r['n'] or '-'}곳)")
    else:
        parts.append("지역 1등 없음")
    if seconds:
        parts.append(f"TOP5 2등 {seconds}곳")
    kept = sum(1 for x in r["next"] if x[4] == "kept")
    parts.append(f"다음 회차 TOP5 유지 {kept} · 신규 {len(r['next']) - kept}" if r["next"] else "다음 회차 납품 미확보")
    if r["live_changes"]:
        parts.append(f"실전 배수 변경 {r['live_changes']}건")
    return " · ".join(parts)


# ── 검수 (규칙 기반 자동 문장) ─────────────────────────────────────
def audit(d, nums, stores, popc, agents):
    D, N = d["D"], d["N"]
    a, m = [], []
    g = {x["key"]: x for x in nums["groups"]}
    if nums["actual"]:
        tr = nums["traits"]
        t, sh = tr["traits"], tr.get("share", {})
        a.append(f"{D}회 당첨번호 {' '.join(map(str, nums['actual']))} + {nums['bonus']}: 연속 쌍 {t['consec']}개 · 범위 {t['span']} · "
                 f"10단위 {t['decades']}구간 · 합 {t['sum']}. 과거 {tr['past_rounds']}회 중 연속 쌍이 이만큼 이상인 회차 {pct(sh.get('consec_ge', 0))}, "
                 f"범위가 이만큼 좁은 회차 {pct(sh.get('span_le', 0))}.")
        scored = [x for x in nums["groups"] if x.get("sets")]
        if scored:
            best = max(scored, key=lambda x: (x["best_matches"], x["mean"]))
            bs = max(best["sets"], key=lambda s: s["matches"])
            a.append(f"가장 근접: {best['label']} — {' '.join(map(str, bs['numbers']))} 에서 {bs['matches']}개 일치"
                     f"({', '.join(map(str, bs['hits'])) or '없음'})" + (f" → {R.RANK_LABEL[bs['rank']]}" if bs["rank"] else " · 낙첨") + ".")
            off = g.get("official")
            if off and off.get("sets"):
                a.append(f"공식 5세트: 최고 {off['best_matches']}개 · 평균 {off['mean']:.2f}개 (무작위 기대 0.80개). "
                         f"맞힌 번호 {', '.join(map(str, sorted({h for s in off['sets'] for h in s['hits']}))) or '없음'}.")
    if stores["briefing_prev"]:
        a.append(f"브리핑 추천 명당 {len(stores['briefing_prev'])}곳 중 1등 {stores['prev_hits_first']}곳 · 2등 {stores['prev_hits_second']}곳 "
                 f"(모델 추정 기대 1등 {stores['prev_expected_first']:.2f}곳). 이번 회차 1등 판매점 {stores['first_count']}곳.")
    ag = stores["agents"]
    if ag.get("top_first_hits"):
        a.append(f"지방장 238명 TOP5 안 1등 {ag['top_first_hits'][2]}곳 (지역 내 무작위 기대 {ag['uniform_expected'][2]:.2f}곳 · "
                 f"과거 빈도만 쓴 TOP5 {ag['history_top5']}곳) · 지방장 범위 밖 1등 {ag['outside']}곳.")
    misses = sorted([(f[2] or 1 << 30, r["label"], f[1] or f[0], r["n"]) for r in agents for f in r["firsts"] if f[3] is None])[:3]
    if misses:
        a.append("놓친 1등(사전 순위 높았던 순): " + ", ".join(f"{l} {n}({p}위/{c}곳)" for p, l, n, c in misses) + ".")

    # 수학 관점
    for x in nums["groups"]:
        if x.get("sets"):
            m.append(f"{x['label']}: 이번 최고 {x['best_matches']}개 일치 — 무작위 {len(x['sets'])}세트로도 이 이상 나올 확률 "
                     f"{pct(x['p_best_or_more'])}.")
    k = sum(1 for x in nums["groups"] if x.get("track"))
    for x in nums["groups"]:
        t = x.get("track")
        if not t:
            continue
        sig = t["p_one_sided"] < 0.05 / max(1, k)
        small = t["sets"] < SMALL_SETS
        m.append(f"{x['label']} 사전 등록 누적 {t['rounds']}회·{t['sets']}세트: 평균 {t['mean']:.2f}개 vs 기대 0.80 (z {t['z']:+.2f}, p {t['p_one_sided']:.3f}) · "
                 f"3개 이상 {t['ge3']}번 vs 기대 {t['expected_ge3']:.1f}번 → "
                 + (f"표본 {t['sets']}세트로는 판단 불가 ({SMALL_SETS}세트 이상부터 판정)" if small
                    else "무작위보다 유의하게 높음(다중 비교 보정 후)" if sig else "무작위와 구별되지 않음"))
    if popc.get("R1") is not None:
        line = (f"인기도 점검: {D}회 1등 {popc['rank1_winners']}명 (무작위 기대 {popc['rank1_expected']:.1f}명, ×{popc['R1']:.2f})"
                + (f" · 4등 쏠림 ×{popc['R4']:.2f}" if popc.get("R4") else ""))
        if popc.get("model_pct") is not None:
            line += f" · 인기도 모델은 이 조합을 무작위 대비 인기 백분위 {popc['model_pct']:.0f}로 봄"
            hi, real = popc["model_pct"] >= 50, (popc.get("R4") or popc["R1"]) >= 1
            line += " → 방향 일치" if hi == real else " → 방향 불일치 (한 회차는 우연 오차가 큼)"
        m.append(line + ".")
    if ag.get("top_first_hits") and ag.get("uniform_expected"):
        lam = ag["uniform_expected"][2]
        m.append(f"지방장 TOP5 1등 {ag['top_first_hits'][2]}곳: 지역 내 무작위 기준 P(≥관측) {R.poisson_sf(ag['top_first_hits'][2], lam):.3f}. "
                 f"단, 과거 빈도만 써도 {ag['history_top5']}곳 — 판매량이 많은 곳을 고른 효과이며 예측력 우위로 보지 않음.")
    m.append(f"번호: 모든 조합의 1등 확률은 1/{TOTAL:,}, 한 세트가 3개 이상 맞을 확률 {pct(P_PRIZE, 2)}, 5세트 중 하나라도 {pct(1 - (1 - P_PRIZE) ** 5)}. "
             "한 회차 결과로 가설을 채택·폐기하지 않습니다 (누적 검정 기준).")
    sig_any = any(x.get("track") and x["track"]["sets"] >= SMALL_SETS and x["track"]["p_one_sided"] < 0.05 / max(1, k)
                  for x in nums["groups"])
    verdict = ("누적 성적에서 무작위보다 유의하게 높은 번호 알고리즘이 있습니다 — 표본을 더 쌓아 재확인 필요."
               if sig_any else "번호 알고리즘 중 무작위보다 유의하게 나은 것은 아직 없습니다. 비인기 추천은 확률이 아니라 당첨 시 몫을 노리는 선택입니다.")
    return {"analyst": a, "mathematician": m, "verdict": verdict,
            "note": "규칙 기반 자동 검수 — 저장된 수치로 만든 문장이며 사람이 검수한 것이 아닙니다."}


def next_block(d, nums):
    D, N = d["D"], d["N"]
    off = next((g for g in nums["groups"] if g["key"] == "official"), {})
    prev_sets = [s["numbers"] for s in off.get("sets") or []]
    fr = d["fr_next"]
    nsets = sets_of(fr.get("sets")) if fr else []
    popn = d["pop"].get(N) or {}
    popd = d["pop"].get(D) or {}

    def pinfo(pl, s):
        for x in (pl.get("official") or []):
            if sorted(x["set"]) == sorted(s):
                return x
        return None
    prev_nums, next_nums = Counter(n for s in prev_sets for n in s), Counter(n for s in nsets for n in s)
    return {
        "official": {"status": "ready" if nsets else "awaiting_engine", "training_end": fr["training_end_round"] if fr else None,
                     "sets": [{"numbers": s, "same_as_prev": s in prev_sets, "popularity": pinfo(popn, s)} for s in nsets],
                     "prev_sets": [{"numbers": s, "popularity": pinfo(popd, s)} for s in prev_sets],
                     "numbers_added": sorted(set(next_nums) - set(prev_nums)), "numbers_removed": sorted(set(prev_nums) - set(next_nums)),
                     "numbers_kept": sorted(set(prev_nums) & set(next_nums))},
        "popularity_picks": [x for x in (popn.get("picks") or [])], "popularity_status": popn.get("picks_status") if popn else "awaiting_data",
        "probabilities": {"rank1": 1 / TOTAL, "rank2": COMBOS[2] / TOTAL, "rank3": COMBOS[3] / TOTAL, "rank4": COMBOS[4] / TOTAL,
                          "rank5": COMBOS[5] / TOTAL, "any_prize": P_PRIZE, "any_prize_5sets": 1 - (1 - P_PRIZE) ** 5},
    }


# ── 실행 ──────────────────────────────────────────────────────────
_ENV = {}


def run(db, D=None):
    if D is None:
        D = db.get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})[0]["round"]
    d = load(db, D)
    nums = numbers_block(d)
    stores = stores_block(d)
    agents = agents_block(d)
    popc = popularity_check(d)
    nxt = next_block(d, nums)
    missing = []
    if not nums["actual"]:
        missing.append("당첨번호")
    if not stores["first_count"]:
        missing.append("1등 판매점")
    if not d["agent_round"]:
        missing.append("지방장 복기")
    if not d["central"][d["N"]]:
        missing.append(f"{d['N']}회 지방장 예측")
    if nxt["official"]["status"] != "ready":
        missing.append(f"{d['N']}회 공식 번호({D}회까지 학습)")
    if popc.get("R1") is None:
        missing.append("당첨자 수")
    now = datetime.now(timezone.utc).isoformat()
    main = {"version": VERSION, "round": D, "next": d["N"], "status": "final" if not missing else "partial", "missing": missing,
            "generated_at": now, "numbers": nums, "stores": stores, "popularity_check": popc, "next_round": nxt,
            "audit": audit(d, nums, stores, popc, agents),
            "hypotheses": {"corrections": ((d["review"] or {}).get("corrections") or {}).get("by_to_status"),
                           "applied": ((d["review"] or {}).get("corrections") or {}).get("applied"),
                           "new": ((d["review"] or {}).get("corrections") or {}).get("new_hypotheses"),
                           "spatial": (d["review"] or {}).get("spatial"), "signals": (d["review"] or {}).get("signals")}}
    ag = {"version": VERSION, "round": D, "next": d["N"], "generated_at": now, "agents": agents,
          "summary": {"agents": len(agents), "with_first": sum(1 for r in agents if r["firsts"]),
                      "top5_first_hits": sum(1 for r in agents for p in r["prev"] if p[4] == 1),
                      "top5_second_hits": sum(1 for r in agents for p in r["prev"] if p[4] == 2),
                      "next_ready": bool(d["deliv"][d["N"]])}}
    return main, ag


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--round", type=int)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL", ""), os.environ.get("SUPABASE_KEY", "")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수 필요")
    if not a.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("저장은 서버(GitHub Actions)에서만 합니다. 로컬은 --dry-run 만 허용")
    _ENV.update(url=url, key=key)
    db = R.Db(url, key, dry=a.dry_run)
    main_row, ag_row = run(db, a.round)
    D, N = main_row["round"], main_row["next"]
    print(f"{D}회 검증 보고 ({main_row['status']}{' · 미확보: ' + ', '.join(main_row['missing']) if main_row['missing'] else ''})")
    for line in main_row["audit"]["analyst"] + main_row["audit"]["mathematician"]:
        print("  ·", line)
    print(f"  지방장 {ag_row['summary']['agents']}명 · TOP5 1등 {ag_row['summary']['top5_first_hits']} · 2등 {ag_row['summary']['top5_second_hits']}")
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fp:
            json.dump({"main": main_row, "agents": ag_row}, fp, ensure_ascii=False, indent=1)
    rows = [{"research_type": t, "model_version": VERSION, "training_end_round": D, "target_round": N, "payload": p}
            for t, p in (("round_debrief", main_row), ("agent_debrief", ag_row))]
    db.upsert("research_results", rows, "research_type,model_version,training_end_round,target_round")
    print("드라이런 — 저장 안 함" if a.dry_run else f"저장: research_results round_debrief · agent_debrief ({D}→{N})")


if __name__ == "__main__":
    main()
