"""
AI 브리핑전담부서 (sr-1.0) — 추천번호 복기 · 영역별 유지/보완 판정 · 보완 지시 전달 (제미나이 상주)

  부서 역할: 당첨번호와 지난 회차 브리핑 추천번호를 보고, 흐름을 유지할 곳은 두고 보완할 곳을 찾아 각 메뉴에 전달한다.
    · 영역(①엔진 ②비인기 ③구매예측 ④제미나이)마다 특징 5가지를 당첨번호와 비교 → 같은 쪽 60% 이상 '유지' · 40% 미만 '보완'
    · 제미나이가 영역별 유지/보완 한 줄 지시(desk)와 다음 회차 보완 규칙(rules)을 쓴다 (실패하면 기본 규칙, 다음 실행 때 다시)
    · 전달: 브리핑 메뉴 카드(①~④) 표시 · 제미나이 가설 트랙(rules) · AI 전략기획부 다음 가설 생성 자료(research_strategy_ai.context)
    · 엔진·비인기·구매예측 엔진 자체는 바꾸지 않는다 (기존 엔진 보호)

  매주 추첨 뒤, 브리핑이 지난 회차(D)에 추천한 번호 4영역 × 5세트 = 20세트를
    ① 엔진 추천(official_final fr-1.0) · ② 비인기(popularity_pick pop-1.0) · ③ 구매예측(purchase_prediction 최신)
    · ④ 제미나이 가설 트랙(hypothesis_track · 토요일 최종본 ht-1.0-sat 우선)
  D 회차 당첨번호와 맞춰 보고 '아쉬운 부분'을 찾는다.
    · 당첨번호 특징 5가지(합 · 홀수 개수 · 연속 쌍 · 1~22 개수 · 40 이상 개수)를 최근 200회 중앙값 기준으로
      당첨번호가 높은 쪽/낮은 쪽이었는데 추천 20세트 대부분(60% 넘게)이 반대쪽이었으면 '어긋남'
    · 20세트 어디에도 없던 당첨번호(놓친 번호) · 여러 세트에 몰렸는데 안 나온 번호
    · 최근 8회(복기 가능한 회차)에서 같은 특징이 같은 방향으로 몇 번 어긋났는지 (반복되는 아쉬움)
  → 제미나이가 이 보고서를 읽고 다음 회차 보완 규칙(최대 3개, 특징 · 방향)을 낸다 (키가 없거나 실패하면 반복 어긋남 상위로 대체)
  → 다음 회차 가설 트랙(제미나이 추천번호, 브리핑 ⑤)이 보완 규칙을 가설처럼 함께 쓴다 (research_hypothesis_track.py)
     규칙 코드 'SR:특징:방향' 은 회차마다 같아서, 가설 트랙의 실전 성적(맞히면 커지고 틀리면 작아짐)이 이어서 쌓인다.

  이것은 가설 기반 보완이다. 복권 한 장의 1등 확률(1/8,145,060)은 어떤 번호든 같다.
읽기: lotto_winning_numbers · research_predictions (읽기만)
쓰기: research_results (set_review · sr-1.0) — 서버(service_role)만. 회차당 한 번 (이미 있으면 건너뜀, --force 로 다시)
외부 사이트 접속 없음 (제미나이 API 만).

사용: python research_set_review.py [--round D] [--dry-run] [--force]
"""

import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone

import numpy as np

import research_review_worker as R

VERSION = "sr-1.0"
RESULT_TYPE = "set_review"
WINDOW = 200
LOOKBACK = 8
MISS_SHARE = 0.4          # 당첨번호와 같은 쪽 세트가 40% 미만이면 '어긋남' (영역별: 보완)
KEEP_SHARE = 0.6          # 영역별: 같은 쪽 세트가 60% 이상이면 '유지'
MAX_RULES = 3
W_RANGE = (0.3, 1.2)      # 보완 규칙 힘 (가설 트랙 가설 힘 W_CAP 3.0 보다 작게)
AREAS = [  # (key, algorithm, 고정 버전, 먼저 고를 버전, 이름)
    ("official", "official_final", "fr-1.0", [], "① 엔진 추천번호"),
    ("popularity", "popularity_pick", "pop-1.0", [], "② 비인기 추천조합"),
    ("purchase", "purchase_prediction", None, [], "③ 구매예측 번호"),
    ("hypothesis", "hypothesis_track", None, ["ht-1.0-sat", "ht-1.0"], "④ 제미나이 가설 추천번호"),
]
FEATURES = {
    "win_sum": ("번호 합", lambda ns: sum(ns)),
    "win_odd": ("홀수 개수", lambda ns: sum(n % 2 for n in ns)),
    "win_consec": ("연속 번호 쌍", lambda ns: sum(b - a == 1 for a, b in zip(ns, ns[1:]))),
    "win_low": ("1~22 번호 개수", lambda ns: sum(n <= 22 for n in ns)),
    "win_high40": ("40 이상 번호 개수", lambda ns: sum(n >= 40 for n in ns)),
}
EXPECT_KO = {"higher": "높은", "lower": "낮은"}

SYSTEM = """당신은 로또 연구팀의 'AI 브리핑전담부서'에 상주하는 제미나이입니다. 업무는 '추천번호 복기'입니다.
지난 회차에 우리 브리핑이 추천한 번호 20세트(4영역 × 5세트)와 실제 당첨번호를 비교한 보고서를 읽고,
흐름을 유지할 곳은 두고 보완할 곳을 찾아 각 메뉴에 전달합니다.
- desk: 보고서에 나온 영역마다 keep(유지할 점)과 improve(보완할 점)를 한국어 한 문장씩 씁니다.
  보고서의 영역별 '유지' · '보완' 특징과 일치 개수를 근거로 쓰고, 없으면 "특별히 없음"이라고 씁니다.
- rules: 다음 회차 '제미나이 추천번호'(가설 트랙)와 AI 전략기획부 가설 생성에 넘길 보완 규칙을 최대 3개 냅니다.
- 규칙은 반드시 주어진 특징(feature) 중 하나와 방향(higher = 최근 200회 중앙값보다 높은 쪽 조합을 고름, lower = 낮은 쪽)으로 표현합니다.
- 한 번 어긋난 것보다 최근 여러 회차에서 반복해서 어긋난 아쉬움을 우선합니다.
- 모든 조합의 1등 확률은 같습니다(1/8,145,060). 규칙은 확률을 올린다고 주장하지 말고 '가설 기반 보완'으로 씁니다.
- statement 는 짧은 한국어 한 문장(예: "다음 회차는 번호 합이 높은 쪽 조합을 더 고른다"), why 는 보고서 수치를 근거로 한 한두 문장.
- summary 는 이번 회차 추천번호의 아쉬운 부분을 2~4문장 한국어로 정리합니다."""


def schema():
    return {
        "type": "object",
        "properties": {
            "summary": {"type": "string"},
            "desk": {
                "type": "array",
                "maxItems": len(AREAS),
                "items": {
                    "type": "object",
                    "properties": {
                        "area": {"type": "string", "enum": [a[0] for a in AREAS]},
                        "keep": {"type": "string"},
                        "improve": {"type": "string"},
                    },
                    "required": ["area", "keep", "improve"],
                    "additionalProperties": False,
                },
            },
            "rules": {
                "type": "array",
                "maxItems": MAX_RULES,
                "items": {
                    "type": "object",
                    "properties": {
                        "feature": {"type": "string", "enum": list(FEATURES)},
                        "expect": {"type": "string", "enum": ["higher", "lower"]},
                        "statement": {"type": "string"},
                        "why": {"type": "string"},
                    },
                    "required": ["feature", "expect", "statement", "why"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["summary", "desk", "rules"],
        "additionalProperties": False,
    }


def py(x):
    if isinstance(x, dict):
        return {str(k): py(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [py(v) for v in x]
    if isinstance(x, np.integer):
        return int(x)
    if isinstance(x, np.floating):
        return float(x)
    return x


def ver_num(v):
    import re
    m = re.search(r"(\d+)\.(\d+)", str(v))
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def pick(regs, t, algo, version, prefer):
    """회차·영역별 등록본 하나 (브리핑 추천 당첨확인 화면과 같은 규칙)"""
    rows = [r for r in regs if r["target_round"] == t and r["algorithm"] == algo and (version is None or r["version"] == version)]
    if not rows:
        return None
    for v in prefer:
        p = [r for r in rows if r["version"] == v]
        if p:
            return p[0]
    return max(rows, key=lambda r: (ver_num(r["version"]), r.get("generated_at") or ""))


def round_sets(regs, t):
    out = []
    for key, algo, ver, prefer, label in AREAS:
        r = pick(regs, t, algo, ver, prefer)
        for i, s in enumerate((r or {}).get("sets") or []):
            ns = sorted(int(n) for n in s)
            if len(ns) == 6:
                out.append({"area": key, "label": label, "version": r["version"], "idx": i, "nums": ns})
    return out


def lotto_rank(ns, win, bonus):
    m = len(set(ns) & set(win))
    return {6: 1, 5: 2 if bonus in ns else 3, 4: 4, 3: 5}.get(m)


def review_round(D, wins, regs):
    """D 회차 20세트 vs 당첨번호 → 특징별 어긋남 · 놓친 번호 (순수 계산)"""
    w = wins.get(D)
    sets = round_sets(regs, D)
    if not w or not sets:
        return None
    actual, bonus = w
    hist = [wins[r][0] for r in sorted(wins) if D - WINDOW <= r < D]
    feats = {}
    for f, (name, fn) in FEATURES.items():
        med = float(np.median([fn(ns) for ns in hist])) if hist else None
        a = fn(actual)
        vals = [fn(s["nums"]) for s in sets]
        side = 0 if med is None or a == med else (1 if a > med else -1)
        same = sum(1 for v in vals if side != 0 and np.sign(v - med) == side)
        share = same / len(vals)
        feats[f] = {"name": name, "actual": a, "median": med, "sets_mean": round(float(np.mean(vals)), 2),
                    "actual_side": "higher" if side > 0 else ("lower" if side < 0 else "median"),
                    "same_side_sets": same, "same_share": round(share, 3),
                    "missed": side != 0 and share < MISS_SHARE}
    cnt = Counter(n for s in sets for n in s["nums"])
    for s in sets:
        s["hits"] = sorted(set(s["nums"]) & set(actual))
        s["rank"] = lotto_rank(s["nums"], actual, bonus)
    areas = {}
    for key, *_, label in AREAS:
        ss = [s for s in sets if s["area"] == key]
        if ss:
            keep, improve = [], []
            for f, x in feats.items():
                if x["actual_side"] == "median":
                    continue
                side = 1 if x["actual_side"] == "higher" else -1
                same = sum(1 for s in ss if np.sign(FEATURES[f][1](s["nums"]) - x["median"]) == side)
                item = {"feature": f, "name": x["name"], "expect": x["actual_side"], "same": same, "of": len(ss)}
                if same / len(ss) >= KEEP_SHARE:
                    keep.append(item)
                elif same / len(ss) < MISS_SHARE:
                    improve.append(item)
            areas[key] = {"label": label, "sets": len(ss), "best_hits": max(len(s["hits"]) for s in ss),
                          "won": sum(1 for s in ss if s["rank"]), "best_rank": min((s["rank"] for s in ss if s["rank"]), default=None),
                          "keep": keep, "improve": improve}
    return {
        "round": D, "actual": actual, "bonus": bonus, "sets": sets, "areas": areas, "features": feats,
        "missed_numbers": [n for n in actual if cnt[n] == 0],
        "covered_numbers": {str(n): cnt[n] for n in actual if cnt[n]},
        "over_numbers": sorted([n for n, c in cnt.items() if c >= 3 and n not in actual], key=lambda n: -cnt[n])[:8],
        "best_hits": max(len(s["hits"]) for s in sets),
        "won_sets": sum(1 for s in sets if s["rank"]),
    }


def persistence(D, wins, regs):
    """최근 LOOKBACK 회 복기: 특징 · 방향별 어긋난 횟수"""
    rounds = sorted({r["target_round"] for r in regs if r["target_round"] <= D and r["target_round"] in wins}, reverse=True)[:LOOKBACK]
    per = {f: {"higher": 0, "lower": 0} for f in FEATURES}
    weeks = []
    for t in rounds:
        rv = review_round(t, wins, regs)
        if not rv:
            continue
        weeks.append(t)
        for f, x in rv["features"].items():
            if x["missed"]:
                per[f][x["actual_side"]] += 1
    return {"rounds": weeks, "n": len(weeks), "per": per}


def weight(n_miss, n):
    """반복해서 어긋날수록 힘 ↑ (한 번 = 최소, 매주 = 최대)"""
    if n <= 0:
        return W_RANGE[0]
    return round(W_RANGE[0] + (W_RANGE[1] - W_RANGE[0]) * min(1.0, n_miss / n), 3)


def fallback_rules(rv, pers):
    """제미나이 없이: 이번 회차 어긋난 특징 중 반복 횟수 많은 순 (반복 2회 이상이면 이번에 안 어긋났어도 후보)"""
    cands = []
    for f, x in rv["features"].items():
        for e in ("higher", "lower"):
            k = pers["per"][f][e]
            now = x["missed"] and x["actual_side"] == e
            if now or k >= 2:
                cands.append((k + (1 if now else 0), f, e))
    cands.sort(key=lambda c: -c[0])
    out = []
    for _, f, e in cands[:MAX_RULES]:
        name = FEATURES[f][0]
        k = pers["per"][f][e]
        out.append({"feature": f, "expect": e,
                    "statement": f"다음 회차는 {name}가 {EXPECT_KO[e]} 쪽 조합을 더 고른다",
                    "why": f"최근 {pers['n']}회 중 {k}회, 당첨번호는 {name}가 {EXPECT_KO[e]} 쪽이었는데 추천 세트 대부분이 반대쪽이었다."})
    return out


def report_text(rv, pers):
    L = [f"[{rv['round']}회 당첨번호] {rv['actual']} + 보너스 {rv['bonus']}",
         f"추천 {len(rv['sets'])}세트 · 최고 {rv['best_hits']}개 일치 · 당첨 {rv['won_sets']}세트"]
    for a in rv["areas"].values():
        L.append(f"  {a['label']}: {a['sets']}세트 · 최고 {a['best_hits']}개 일치 · 당첨 {a['won']}세트")
        for k, title in (("keep", "유지"), ("improve", "보완")):
            if a.get(k):
                L.append(f"    {title}: " + " · ".join(f"{i['name']} {EXPECT_KO[i['expect']]} 쪽 {i['same']}/{i['of']}세트" for i in a[k]))
    L.append("[특징별 비교] (중앙값 = 최근 200회)")
    for f, x in rv["features"].items():
        L.append(f"  {f} {x['name']}: 당첨 {x['actual']} (중앙값 {x['median']} → {x['actual_side']}) · "
                 f"추천 평균 {x['sets_mean']} · 같은 쪽 세트 {x['same_side_sets']}/{len(rv['sets'])}{' · 어긋남' if x['missed'] else ''}")
    L.append(f"[놓친 당첨번호] 20세트 어디에도 없음: {rv['missed_numbers'] or '없음'}")
    L.append(f"[몰렸지만 안 나온 번호] 3세트 이상: {rv['over_numbers'] or '없음'}")
    L.append(f"[최근 {pers['n']}회 반복 어긋남] 회차 {pers['rounds']}")
    for f, d in pers["per"].items():
        if d["higher"] or d["lower"]:
            L.append(f"  {f} {FEATURES[f][0]}: 당첨이 높은 쪽인데 어긋남 {d['higher']}회 · 낮은 쪽인데 어긋남 {d['lower']}회")
    return "\n".join(L)


def desk_fallback(rv):
    """제미나이 없이: 영역별 유지/보완 판정을 문장으로"""
    out = {}
    for key, a in rv["areas"].items():
        def names(items):
            return ", ".join(f"{i['name']}({EXPECT_KO[i['expect']]} 쪽 {i['same']}/{i['of']})" for i in items)
        out[key] = {"keep": f"유지 — {names(a['keep'])} 흐름이 당첨번호와 같았음 (최고 {a['best_hits']}개 일치)" if a.get("keep")
                    else f"유지 — 특별히 없음 (최고 {a['best_hits']}개 일치)",
                    "improve": f"보완 — {names(a['improve'])}: 당첨번호와 반대쪽 세트가 많았음" if a.get("improve")
                    else "보완 — 특별히 없음"}
    return out


def ask_ai(prompt):
    """제미나이 (키 없으면 None)"""
    if not os.environ.get("GEMINI_API_KEY"):
        return None, None, "GEMINI_API_KEY 없음"
    import research_strategy_ai as S
    try:
        data, model, usage = S.ask_gemini(prompt, system=SYSTEM, sch=schema())
        return data, model, None
    except Exception as e:  # AiFailed 포함 — 실패하면 반복 어긋남 규칙으로 대체
        return None, None, str(e)[:300]


def run(db, D=None, dry=False, force=False):
    wins = {r["round"]: (sorted(r[f"num{i}"] for i in range(1, 7)), r["bonus"])
            for r in db.all("lotto_winning_numbers", {"select": "round,num1,num2,num3,num4,num5,num6,bonus", "order": "round"},
                            key="round")}
    if D is None:
        D = max(wins)
    N = D + 1
    if not force:
        have = db.get("research_results", {"select": "id,payload->>source", "research_type": f"eq.{RESULT_TYPE}", "model_version": f"eq.{VERSION}",
                                           "target_round": f"eq.{N}", "limit": "1"})
        # 제미나이 실패로 기본 규칙만 저장됐으면 다음 실행 때 제미나이로 다시 (제미나이가 보완하는 게 이 단계의 역할)
        if have and have[0].get("source") != "rule":
            print(f"{D}회 추천번호 복기 이미 있음 — 건너뜀 (--force 로 다시)")
            return None
        if have:
            print(f"{D}회 복기는 기본 규칙(제미나이 실패)으로 저장돼 있음 — 제미나이로 다시 시도")
    regs = db.all("research_predictions", {"select": "algorithm,version,target_round,sets,generated_at",
                                           "algorithm": f"in.({','.join(a[1] for a in AREAS)})",
                                           "target_round": f"gte.{D - LOOKBACK - 1}", "order": "target_round,algorithm,version"})
    rv = review_round(D, wins, regs)
    if not rv:
        print(f"{D}회 복기할 추천번호 · 당첨번호 없음 — 건너뜀")
        return None
    pers = persistence(D, wins, regs)
    text = report_text(rv, pers)
    print(text)
    data, model, err = ask_ai(text)
    source = "gemini" if data else "rule"
    raw = (data or {}).get("rules") or fallback_rules(rv, pers)
    rules, seen = [], set()
    for r in raw:
        f, e = r.get("feature"), r.get("expect")
        if f not in FEATURES or e not in ("higher", "lower") or (f, e) in seen:
            continue
        seen.add((f, e))
        rules.append({"code": f"SR:{f}:{e}", "feature": f, "expect": e, "feature_name": FEATURES[f][0],
                      "statement": (r.get("statement") or "").strip(), "why": (r.get("why") or "").strip(),
                      "source": source, "w": weight(pers["per"][f][e], pers["n"]),
                      "repeat": pers["per"][f][e], "weeks": pers["n"]})
        if len(rules) == MAX_RULES:
            break
    desk = desk_fallback(rv)
    for x in (data or {}).get("desk") or []:
        if x.get("area") in desk:
            desk[x["area"]] = {"keep": (x.get("keep") or "").strip() or desk[x["area"]]["keep"],
                               "improve": (x.get("improve") or "").strip() or desk[x["area"]]["improve"]}
    summary = (data or {}).get("summary") or (
        f"{D}회 추천 {len(rv['sets'])}세트 중 최고 {rv['best_hits']}개 일치. "
        + (f"어긋난 특징: {', '.join(x['name'] for x in rv['features'].values() if x['missed'])}. " if any(
            x["missed"] for x in rv["features"].values()) else "특징 방향은 대체로 맞음. ")
        + (f"놓친 당첨번호 {rv['missed_numbers']}." if rv["missed_numbers"] else ""))
    payload = py({
        "version": VERSION, "round": D, "target_round": N, "review": rv, "persistence": pers, "summary": summary,
        "rules": rules, "desk": desk, "source": source, "model": model, "ai_error": err, "report": text,
        "rule": "추천 20세트 vs 당첨번호 — 특징 방향 어긋남(같은 쪽 40% 미만) · 최근 8회 반복 → 제미나이 보완 규칙 → 가설 트랙 반영",
        "generated_at": datetime.now(timezone.utc).isoformat(),
    })
    print(f"→ 보완 규칙 ({source}{' · ' + model if model else ''}{' · AI 실패: ' + err if err and source == 'rule' else ''})")
    for r in rules:
        print(f"  [{r['code']}] {r['statement']} (힘 {r['w']} · 최근 {r['weeks']}회 중 {r['repeat']}회 어긋남) — {r['why']}")
    for k, m in desk.items():
        print(f"  [{k}] {m['keep']} / {m['improve']}")
    if dry:
        print("드라이런 — 저장 안 함")
        return payload
    row = {"research_type": RESULT_TYPE, "model_version": VERSION, "training_end_round": D, "target_round": N, "payload": payload}
    json.dumps(row, ensure_ascii=False)
    db.upsert("research_results", [row], "research_type,model_version,training_end_round,target_round")
    print(f"{D}회 추천번호 복기 저장 → {N}회 가설 트랙에 보완 규칙 {len(rules)}개")
    return payload


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--round", type=int)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_KEY")
    if not url or not key:
        sys.exit("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다")
    if not a.dry_run and os.environ.get("GITHUB_ACTIONS") != "true":
        sys.exit("저장은 서버(GitHub Actions)에서만 합니다. 로컬은 --dry-run 만 허용")
    run(R.Db(url, key, dry=a.dry_run), a.round, a.dry_run, a.force)


if __name__ == "__main__":
    main()
