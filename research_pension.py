"""
연금복권720+ 연구 (pn-1.0) — 연금 명당 · 연금 번호 엔진 · 연금 가설 트랙 (브리핑 '연금복권' 탭 · 일반 모드 추천 '연금' 탭)

  ① 연금 명당 (지방장 방식): 연금 1·2등 판매점 기록(winning_history · pension, 13회~)을 반감기 100회로 감쇠 누적
     + 0.3 × 같은 지역 평균 → 다음 회차 1·2등 추정 비중. 전국 상위 10곳 (시·군·구당 1곳, 인터넷 판매 제외)
  ② 연금 번호 엔진: 관리자가 입력한 당첨번호(pension_winning_numbers)가 50회 이상일 때만 가동.
     최근 최대 200회 1등 번호의 자리별 숫자 빈도(+1 평활)로 6자리를 뽑고, 1등 조 빈도 순으로 조를 붙여 5장
  ③ 연금 가설 트랙: AI 전략기획부(제미나이)의 연금 가설(spec.level = pension) 중 이번 회차 조건이 참이고
     최근 최대 200회에서 방향이 맞은 것만 힘을 받아, 그 방향(합·홀수·높은 숫자·반복·첫자리·끝자리·조)의 번호 5장
     — 검증 전 '가설 기반' 예측. 실전 성적(방향 맞힘)이 쌓이면 힘이 커지고 작아진다.
  목표 회차 = 달력상 다음 추첨 회차 (매주 목요일). 추첨일 18시(KST) 이후에는 그 회차를 다시 계산하지 않는다(고정).
  모든 결과는 추정·가설이며 복권 한 장의 당첨 확률을 바꾸지 않는다 (1등 1/5,000,000).
읽기: pension_winning_numbers · winning_history · lottery_stores · strategy_* (크롤링 테이블은 읽기만)
쓰기: research_results (pension_briefing) · research_public_extra (lottery = pension, 공개 요약) — 서버(service_role)만
외부 사이트 접속 없음.

사용: python research_pension.py [--dry-run]
"""

import argparse
import json
import math
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone

import numpy as np

import research_review_worker as R

VERSION = "pn-1.0"
RESULT_TYPE = "pension_briefing"
DAY1 = date(2020, 5, 7)
KST = timezone(timedelta(hours=9))
HALF_LIFE = 100.0
REGION_PRIOR = 0.3
ENGINE_MIN = 50
WINDOW = 200
MIN_COND = 5
W_CAP = 3.0
N_TICKETS = 5
N_STORES = 10
ONLINE = {"00000000", "001160"}

# ── 연금 가설 어휘 (AI 전략기획부가 고르는 키) ─────────────────────────
PENSION_CONDITIONS = {
    "round_odd": "홀수 회차",
    "day_odd": "추첨일이 홀수 날짜",
    "early_month": "추첨일이 1~10일",
    "first_half": "상반기(1~6월)",
    "summer": "여름(6~8월)",
    "winter": "겨울(12~2월)",
    "prev_group_high": "직전 1등 조가 4·5조",
    "prev_sum_high": "직전 1등 번호 6자리 합 27 이상",
    "prev_repeat": "직전 1등 번호에 같은 숫자 반복",
    "prev_odd_heavy": "직전 1등 번호에 홀수 4개 이상",
    "prev_first_high": "직전 1등 번호 첫자리 5~9",
}
PENSION_OUTCOMES = {
    "p_group": "1등 조 (1~5)",
    "p_sum": "1등 번호 6자리 합",
    "p_odd": "1등 번호 홀수 개수",
    "p_high": "1등 번호 5~9 숫자 개수",
    "p_repeat": "1등 번호 반복 숫자 수",
    "p_first": "1등 번호 첫자리",
    "p_last": "1등 번호 끝자리",
}
EXPECT = {"higher": "높다", "lower": "낮다"}


def josa(word):
    w = re.sub(r"\s*\([^)]*\)\s*$", "", word).strip()
    ch = w[-1] if w else ""
    if "가" <= ch <= "힣":
        return "이" if (ord(ch) - 0xAC00) % 28 else "가"
    return "가"


def pension_statement(spec):
    conds = [c for c in (spec.get("condition"), spec.get("condition2")) if c and c != "none"]
    o = PENSION_OUTCOMES[spec["outcome"]]
    return f"[연금] {'이면서 '.join(PENSION_CONDITIONS[c] for c in conds)}일 때 {o}{josa(o)} {EXPECT[spec['expect']]}"


def pension_code(spec):
    conds = sorted(c for c in (spec.get("condition"), spec.get("condition2")) if c and c != "none")
    return f"pension:{'+'.join(conds)}|{spec['outcome']}|{spec['expect']}"


def draw_date(r):
    return DAY1 + timedelta(days=7 * (r - 1))


def latest_drawn(now_kst):
    r = (now_kst.date() - DAY1).days // 7 + 1
    if draw_date(r) == now_kst.date() and now_kst.hour < 20:
        r -= 1
    return r


def features(group, num):
    d = [int(c) for c in num]
    return {"p_group": group, "p_sum": sum(d), "p_odd": sum(x % 2 for x in d), "p_high": sum(x >= 5 for x in d),
            "p_repeat": 6 - len(set(d)), "p_first": d[0], "p_last": d[-1]}


def conditions_for(r, prev):
    dd = draw_date(r)
    c = {"round_odd": r % 2 == 1, "day_odd": dd.day % 2 == 1, "early_month": dd.day <= 10,
         "first_half": dd.month <= 6, "summer": dd.month in (6, 7, 8), "winter": dd.month in (12, 1, 2)}
    if prev is None:
        for k in ("prev_group_high", "prev_sum_high", "prev_repeat", "prev_odd_heavy", "prev_first_high"):
            c[k] = None
    else:
        f = features(prev["group"], prev["number"])
        c.update(prev_group_high=prev["group"] >= 4, prev_sum_high=f["p_sum"] >= 27, prev_repeat=f["p_repeat"] > 0,
                 prev_odd_heavy=f["p_odd"] >= 4, prev_first_high=f["p_first"] >= 5)
    return c


def load_numbers(db):
    rows = db.all("pension_winning_numbers", {"select": "round,winning_group,winning_number,bonus_number,draw_date",
                                              "order": "round"}, key="round")
    out = {}
    for r in rows:
        n = str(r.get("winning_number") or "").strip()
        g = r.get("winning_group")
        if re.fullmatch(r"\d{6}", n) and g in (1, 2, 3, 4, 5):
            out[int(r["round"])] = {"round": int(r["round"]), "group": int(g), "number": n}
    return out


# ── ① 연금 명당 ───────────────────────────────────────────────────
SIDO = {"서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천", "광주광역시": "광주",
        "대전광역시": "대전", "울산광역시": "울산", "세종특별자치시": "세종", "경기도": "경기", "강원도": "강원",
        "강원특별자치도": "강원", "충청북도": "충북", "충청남도": "충남", "전라북도": "전북", "전북특별자치도": "전북",
        "전라남도": "전남", "경상북도": "경북", "경상남도": "경남", "제주특별자치도": "제주"}


def region_key(address, region):
    a = (address or "").split()
    if len(a) >= 2 and a[0] not in ("동행복권(dhlottery.co.kr)",):
        return f"{SIDO.get(a[0], a[0])}|{a[1]}"
    return region or "미상"


def stores_block(db, latest):
    wh = db.all("winning_history", {"select": "round,dhlottery_code,prize_tier", "lottery_type": "eq.pension",
                                    "order": "round,dhlottery_code"}, key="round")
    ev = defaultdict(list)
    per_round = Counter()
    for r in wh:
        c = r["dhlottery_code"]
        if not c or c in ONLINE or r["round"] > latest:
            continue
        ev[c].append((r["round"], r["prize_tier"]))
        per_round[r["round"]] += 1
    if not ev:
        return {"status": "판매점 기록 없음", "stores": []}
    info = {}
    codes = sorted(ev)
    for i in range(0, len(codes), 150):
        for s in db.get("lottery_stores", {"select": "dhlottery_code,store_name,address,region,first_count,second_count",
                                           "lottery_type": "eq.pension", "dhlottery_code": f"in.({','.join(codes[i:i + 150])})"}):
            info[s["dhlottery_code"]] = s
    g = 0.5 ** (1 / HALF_LIFE)
    kw = {c: sum(g ** (latest - r) for r, _ in e) for c, e in ev.items()}
    reg = {c: region_key(info.get(c, {}).get("address"), info.get(c, {}).get("region")) for c in ev}
    by_reg = defaultdict(list)
    for c, k in kw.items():
        by_reg[reg[c]].append(k)
    reg_mean = {k: sum(v) / len(v) for k, v in by_reg.items()}
    score = {c: kw[c] + REGION_PRIOR * reg_mean[reg[c]] for c in kw}
    total = sum(score.values())
    recent = [per_round.get(r, 0) for r in range(latest - 51, latest + 1)]
    lam = sum(recent) / len(recent)            # 최근 52회 회차당 1·2등 판매점 사건 수 (인터넷 제외)
    out, used = [], set()
    for c in sorted(score, key=lambda x: -score[x]):
        if len(out) >= N_STORES:
            break
        if reg[c] in used and reg[c] != "미상":
            continue
        used.add(reg[c])
        s = info.get(c, {})
        rounds = sorted({r for r, _ in ev[c]}, reverse=True)
        out.append({"store_code": c, "name": s.get("store_name") or c, "address": s.get("address") or "",
                    "region": reg[c].replace("|", " "), "first": sum(t == "first" for _, t in ev[c]),
                    "second": sum(t == "second" for _, t in ev[c]), "last_round": rounds[0], "rounds": rounds[:8],
                    "share": round(score[c] / total, 6), "p_next": round(1 - math.exp(-lam * score[c] / total), 6)})
    return {"status": "ok", "stores": out, "events_per_round": round(lam, 3), "stores_with_events": len(ev),
            "rule": f"연금 1·2등 판매점 기록 반감기 {HALF_LIFE:.0f}회 감쇠 + {REGION_PRIOR} × 지역 평균 · 인터넷 판매 제외 · 시·군·구당 1곳"}


# ── ② 연금 번호 엔진 ──────────────────────────────────────────────
def engine_block(nums, latest, target):
    have = sorted(r for r in nums if r <= latest)
    if len(have) < ENGINE_MIN:
        return {"status": "waiting", "have": len(have), "need": ENGINE_MIN,
                "note": f"당첨번호 {len(have)}회 입력 — {ENGINE_MIN}회부터 가동 (관리자 → 연금복권 당첨번호 입력)"}
    use = [nums[r] for r in have[-WINDOW:]]
    pos = np.ones((6, 10))
    for x in use:
        for i, ch in enumerate(x["number"]):
            pos[i, int(ch)] += 1
    pos /= pos.sum(axis=1, keepdims=True)
    gc = Counter(x["group"] for x in use)
    groups = sorted(range(1, 6), key=lambda g: (-gc.get(g, 0), g))
    rng = np.random.default_rng(20261022 + target)
    tickets, seen = [], set()
    while len(tickets) < N_TICKETS:
        n = "".join(str(rng.choice(10, p=pos[i])) for i in range(6))
        if n in seen:
            continue
        seen.add(n)
        tickets.append({"group": groups[len(tickets) % 5], "number": n})
    hot = [[int(np.argmax(pos[i]))] for i in range(6)]
    return {"status": "ok", "have": len(have), "window": [use[0]["round"], use[-1]["round"]], "tickets": tickets,
            "group_counts": {str(g): gc.get(g, 0) for g in range(1, 6)},
            "hot_digits": [h[0] for h in hot],
            "rule": "최근 최대 200회 자리별 숫자 빈도(+1 평활)로 6자리 추출 · 1등 조 빈도 순으로 조 배정"}


# ── ③ 연금 가설 트랙 ──────────────────────────────────────────────
def hypotheses(db):
    dirs = {d["id"]: d for d in db.all("strategy_directions", {"select": "id,source", "order": "id"}, key="id")}
    out = []
    for h in db.all("strategy_hypotheses", {"select": "id,code,statement,status,spec,direction_id", "order": "code"}, key="code"):
        sp = h.get("spec") or {}
        if sp.get("level") == "pension" and (dirs.get(h.get("direction_id")) or {}).get("source") == "ai":
            out.append(h)
    return out


def track_block(db, nums, latest, target, prev_payload):
    hyps = hypotheses(db)
    have = sorted(r for r in nums if r <= latest)
    if not hyps:
        return {"status": "waiting", "note": "제미나이 연금 가설이 아직 없습니다 (매일 17시 AI 전략기획부)"}
    if len(have) < ENGINE_MIN:
        return {"status": "waiting", "hypotheses_total": len(hyps),
                "note": f"연금 가설 {len(hyps)}개 대기 — 당첨번호 {len(have)}회 입력, {ENGINE_MIN}회부터 가동"}
    rows = []
    for r in have:
        rows.append({"round": r, "cond": conditions_for(r, nums.get(r - 1)), "out": features(nums[r]["group"], nums[r]["number"])})
    recent = rows[-WINDOW:]
    prev = nums.get(latest)
    tc = conditions_for(target, prev)
    rec = {k: tuple(v) for k, v in ((prev_payload or {}).get("track", {}).get("record") or {}).items()}
    # 직전 회차 채점
    scored = []
    pt = (prev_payload or {}).get("track") or {}
    if (prev_payload or {}).get("target_round") == latest and latest in nums and not pt.get("scored"):
        f = features(nums[latest]["group"], nums[latest]["number"])
        for u in pt.get("used", []):
            v, med = f.get(u["outcome"]), u.get("median")
            if v is None or med is None or v == med:
                continue
            hit = (v > med) == (u["expect"] == "higher")
            p, h = rec.get(u["code"], (0, 0))
            rec[u["code"]] = (p + 1, h + int(hit))
            scored.append({"code": u["code"], "hit": hit})
    used, skipped = [], Counter()
    for h in hyps:
        sp = h["spec"]
        conds = [c for c in (sp.get("condition"), sp.get("condition2")) if c and c != "none"]
        if any(c not in PENSION_CONDITIONS for c in conds) or sp.get("outcome") not in PENSION_OUTCOMES:
            skipped["unsupported"] += 1
            continue
        if any(tc.get(c) is None for c in conds):
            skipped["unknown"] += 1
            continue
        if not all(tc.get(c) for c in conds):
            skipped["condition_false"] += 1
            continue
        o, e = sp["outcome"], sp["expect"]
        cv = [x["out"][o] for x in recent if all(x["cond"].get(c) for c in conds)]
        ov = [x["out"][o] for x in recent if not all(x["cond"].get(c) for c in conds)]
        if len(cv) < MIN_COND or len(ov) < MIN_COND:
            skipped["small"] += 1
            continue
        se = math.sqrt(np.var(cv, ddof=1) / len(cv) + np.var(ov, ddof=1) / len(ov)) or 1e-9
        z = (np.mean(cv) - np.mean(ov)) / se * (1 if e == "higher" else -1)
        if z <= 0:
            skipped["weak"] += 1
            continue
        p, hh = rec.get(h["code"], (0, 0))
        m = (hh + 1) / (p + 2) * 2
        allv = [x["out"][o] for x in recent]
        used.append({"code": h["code"], "statement": h["statement"], "status": h["status"], "outcome": o, "expect": e,
                     "conds": conds, "z": round(float(z), 3), "w": round(float(min(z, W_CAP)), 3), "m": round(m, 3),
                     "w_eff": round(float(min(z, W_CAP) * m), 3), "median": float(np.median(allv)),
                     "n_cond": len(cv), "mean_cond": round(float(np.mean(cv)), 3), "mean_other": round(float(np.mean(ov)), 3)})
    # 번호: 무작위 후보 중 가설 방향 점수 상위 (조는 p_group 방향)
    rng = np.random.default_rng(20261023 + target)
    cand = []
    for _ in range(20000):
        g = int(rng.integers(1, 6))
        n = "".join(str(int(x)) for x in rng.integers(0, 10, 6))
        f = features(g, n)
        s = sum(u["w_eff"] * float(np.sign(f[u["outcome"]] - u["median"])) * (1 if u["expect"] == "higher" else -1) for u in used)
        cand.append((s, g, n))
    cand.sort(key=lambda x: -x[0])
    tickets, seen = [], set()
    for s, g, n in cand:
        if n in seen or any(sum(a == b for a, b in zip(n, t["number"])) >= 4 for t in tickets):
            continue
        seen.add(n)
        tickets.append({"group": g, "number": n, "score": round(s, 3)})
        if len(tickets) == N_TICKETS:
            break
    return {"status": "ok", "hypotheses_total": len(hyps), "used": used, "skipped": dict(skipped), "tickets": tickets,
            "conditions": tc, "record": {k: list(v) for k, v in rec.items()}, "scored_previous": scored,
            "rule": "제미나이 연금 가설 · 이번 회차 조건 참 · 최근 최대 200회 방향 일치 가중 × 실전 성적 배수 — 검증 전 가설 기반"}


def public_summary(p):
    """일반 모드 공개 요약 (연구 원본 · 계수 없음)"""
    eng, st, tr = p["engine"], p["stores"], p["track"]
    return {
        "lottery": "pension", "target_round": p["target_round"], "draw_date": p["draw_date"],
        "engine": {"status": eng["status"], "tickets": eng.get("tickets", []), "note": eng.get("note"),
                   "rule": "최근 당첨번호 자리별 숫자 빈도 기반 추천" if eng["status"] == "ok" else None},
        "stores": [{k: s[k] for k in ("name", "region", "first", "second", "last_round")} for s in st.get("stores", [])],
        "track": {"status": tr["status"], "tickets": [{k: t[k] for k in ("group", "number")} for t in tr.get("tickets", [])],
                  "hypotheses": [u["statement"].replace("[연금] ", "") for u in tr.get("used", [])][:5], "note": tr.get("note")},
        "disclaimer": "모든 추천은 과거 기록·가설에 기반한 참고용입니다. 연금복권 한 장의 1등 확률(1/5,000,000)은 어떤 번호든 같습니다.",
    }


def run(db, dry=False, now=None):
    now = now or datetime.now(timezone.utc)
    nk = now.astimezone(KST)
    latest = latest_drawn(nk)
    target = latest + 1
    td = draw_date(target)
    if nk >= datetime(td.year, td.month, td.day, 18, tzinfo=KST):
        print(f"연금 {target}회 추첨일 18시 이후 — 고정 (다시 계산하지 않음)")
        return None
    nums = load_numbers(db)
    prev = db.get("research_results", {"select": "target_round,payload", "research_type": f"eq.{RESULT_TYPE}",
                                       "model_version": f"eq.{VERSION}", "target_round": f"eq.{latest}", "limit": "1"})
    prev_payload = prev[0]["payload"] if prev else None
    p = {"version": VERSION, "target_round": target, "latest_round": latest, "draw_date": td.isoformat(),
         "numbers_entered": len([r for r in nums if r <= latest]),
         "stores": stores_block(db, latest), "engine": engine_block(nums, latest, target),
         "track": track_block(db, nums, latest, target, prev_payload), "generated_at": now.isoformat()}
    print(f"연금 {target}회 ({td}) · 당첨번호 입력 {p['numbers_entered']}회 · 엔진 {p['engine']['status']} · 가설 트랙 {p['track']['status']}")
    for s in p["stores"].get("stores", []):
        print(f"  명당 {s['name']} ({s['region']}) 1등 {s['first']} · 2등 {s['second']} · 최근 {s['last_round']}회 · 추정 {s['p_next'] * 100:.2f}%")
    for t in p["engine"].get("tickets", []):
        print(f"  엔진 {t['group']}조 {t['number']}")
    for t in p["track"].get("tickets", []):
        print(f"  가설 {t['group']}조 {t['number']}")
    row = {"research_type": RESULT_TYPE, "model_version": VERSION, "training_end_round": latest, "target_round": target, "payload": p}
    pub = {"lottery": "pension", "target_round": target, "payload": public_summary(p), "is_public_approved": True,
           "updated_at": now.isoformat()}
    json.dumps([row, pub], ensure_ascii=False)
    if dry:
        print("드라이런 — 저장 안 함")
        return p
    db.upsert("research_results", [row], "research_type,model_version,training_end_round,target_round")
    if prev_payload and p["track"].get("scored_previous") and not prev_payload.get("track", {}).get("scored"):
        pp = dict(prev_payload)
        pp["track"] = dict(pp.get("track") or {}, scored=True)
        db.patch("research_results", {"research_type": f"eq.{RESULT_TYPE}", "model_version": f"eq.{VERSION}",
                                      "target_round": f"eq.{latest}"}, {"payload": pp})
    try:
        db.upsert("research_public_extra", [pub], "lottery,target_round")
    except RuntimeError as e:
        print(f"공개 요약 저장 생략 — research_v16_extra.sql 실행 필요 ({str(e)[:120]})")
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다")
    if not a.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("저장은 서버(GitHub Actions)에서만 합니다. 로컬은 --dry-run 만 허용")
    run(R.Db(url, key, dry=a.dry_run), a.dry_run)


if __name__ == "__main__":
    main()
