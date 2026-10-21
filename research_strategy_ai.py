"""
AI 전략기획부 (sa-1.1 · Claude · Gemini) — 회차 검증 결과를 읽고 다음 연구 '방향'만 제시한다

  · AI 가 하는 일: 매일 오후 5시(KST) — 방향 1~5개(제목·이유) + 새 가설 20개 + 이전 가설을 보충한 응용 가설 10개
    (조건·결과·기대 방향은 가설 공장 어휘에서만). 이미 있는 가설과 겹치는 제안은 빼고 저장한다.
    목표: 맞힐 확률을 높일 수 있는 가설 — 비서가 검정과 함께 '가설 모의'(그대로 따라 골랐다면 더 맞았나)로 확인한다
  · AI 가 못 하는 일: 번호·명당·장부·엔진에 접근하거나 바꾸는 것. AI 에게는 도구가 없고, 응답은 정해진 JSON 형식으로만 받아
    strategy_directions · strategy_hypotheses(제안 상태)에만 저장한다. 검증·유지·폐기는 비서(research_hypothesis_factory.py)가 한다.
  · 연결된 AI: ANTHROPIC_API_KEY → Claude(claude-opus-5-5), GEMINI_API_KEY → Gemini(gemini-3.8-flash).
    키가 있는 AI 마다 회차당 1번씩 제안 (둘 다 있으면 같은 자료로 각각 제안 → 검증 통과율로 비교). 키가 하나도 없으면 건너뜀.
입력: 최신 회차 검증 보고(round_debrief) 검수 문장 · 지금까지의 가설과 판정 — 저장된 수치만. 외부 사이트 접속 없음.

사용: python research_strategy_ai.py [--dry-run]   (드라이런: AI 호출 없이 보낼 내용만 출력)
"""

import argparse
import json
from datetime import datetime, timedelta, timezone
import os
import re
import sys

import research_hypothesis_factory as F
import research_review_worker as R

VERSION = "sa-1.3"
CLAUDE_MODEL = "claude-opus-5-5"
GEMINI_MODEL = "gemini-3.8-flash"   # 무료 등급 있음 (ai.google.dev 요금표)
MAX_DIRECTIONS = 5
DAILY_HYPS = 20           # AI 마다 하루 새 가설 수
DAILY_APPLIED = 10        # AI 마다 하루 응용 가설 수 (이전 가설에 조건 보충·결과 변경)
DAILY_STORE = 10          # AI 마다 하루 판매점 가설 수 (명당 — 지방장 기대보다 1등이 더 나오는 판매점 조건)
FOCUS = ["popularity", "calendar", "sales", "numbers", "stores"]

SYSTEM = """당신은 로또 연구팀의 'AI 전략기획부'입니다. 역할은 다음 주에 검증할 연구 방향을 제시하는 것뿐입니다.
번호를 추천하거나 결과를 예측하지 않습니다. 제시한 가설은 비서가 과거 데이터로 엄격히 검정합니다
(발견 구간 269~1000회 → 확인 구간 1001회~ → 다중 비교 보정 → 통과 후 새 회차 추적).

알아야 할 사실:
- 추첨은 무작위라 당첨번호 자체를 맞히는 가설은 통과하기 매우 어렵습니다. 모든 조합의 1등 확률은 같습니다.
- 진짜 패턴이 나올 수 있는 곳은 사람의 구매 행동이 반영되는 결과입니다: 당첨자 쏠림(R1~R4), 수동 비율, 1등 판매점 지역.
- 이미 기각·폐기된 가설과 같은 것은 다시 내지 마세요. 판정 보류나 통과한 가설과 이어지는 방향은 좋습니다.
- 조건·결과·기대 방향은 주어진 목록의 키에서만 고릅니다. 목록에 없는 것은 쓰지 마세요.
- 조건을 두 개 겹치고 싶으면 condition2 에 두 번째 조건을 넣으세요 (아니면 "none"). 두 조건 가설은 기준이 더 엄격합니다.
- 비서가 따로 하는 일: 아깝게 기각된 가설에 조건 보태기(보충회생), 탈락 뒤 새 회차로 재검정(회생),
  최근 100회에서만 보이는 효과 임시 채택(임시 일부 발췌), 통과 가설의 다른 결과로 응용 — 같은 것을 중복 제안하지 마세요.

목표는 '맞힐 확률을 높이는 것'입니다. 비서는 가설을 검정하고, 번호 특징 가설은 '그대로 따라 번호를 골랐다면
5등 이상이 무작위보다 많았나'를 모의(시뮬레이션)로 확인합니다. 당첨자 쏠림 가설은 당첨 시 나눠 갖는 몫과 관련됩니다.

오늘의 방향을 1~5개 내고, 방향마다 이유(왜 유망한지, 지난 결과의 어떤 수치를 근거로 했는지)를 한국어로 짧게 쓰세요.
1) 새 가설: 모든 방향을 합쳐 20개 (directions[].hypotheses). 이미 목록에 있는 조합(진행 중이든 기각이든)은 고르지 마세요.
2) 응용 가설: 10개 (applied). 목록에 있는 이전 가설 하나를 parent_code 로 정확히 적고, 그 가설에 조건을 보태거나(condition2)
   결과를 바꿔서(outcome) 새 조합을 만드세요. 아깝게 기각된 가설(p 가 작았던 것)을 보충하는 쪽이 좋습니다.
3) 판매점 가설: 10개 (store_direction). 명당 추천이 매주 같아 '어떤 판매점에서 다음 회차 1등이 지방장 기대보다 더 나오나'를
   판매점 조건 목록(store:)에서 고르세요. 지방장 기대 = 그 판매점의 최근 가중 1·2등 이력이라, 이력만으로 설명되는 것은 통과하지 못합니다.
   제목·이유를 쓰고, 조건 2개를 겹쳐도 됩니다(condition2). 이미 있는 store: 조합은 고르지 마세요.
매일 일하므로, 어제까지의 판정과 모의 결과를 보고 아직 안 가 본 쪽을 탐색하세요.

가설 트랙(실전 부서)도 당신의 가설을 씁니다 — 검정 통과를 기다리지 않고, 최근 200회에서 방향이 맞은 가설을 바로
다음 회차 번호·명당 고르기에 쓰고, 실전에서 맞히면 힘을 키웁니다. 그래서:
- 새 가설 20개 중 최소 6개는 당첨번호 특징 결과(win_sum · win_odd · win_consec · win_low · win_high40)로 내세요.
  가설 트랙이 이 가설로 번호 조합의 특징을 직접 고릅니다.
- 판매액 조건(sales_surge · sales_drop)은 추첨이 끝나야 알 수 있어 가설 트랙이 쓰지 못합니다. 되도록 추첨 전에 알 수 있는
  조건(회차·날짜·계절·직전 회차 결과)을 쓰세요."""


def schema():
    return {
        "type": "object",
        "properties": {
            "directions": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string"},
                        "rationale": {"type": "string"},
                        "focus": {"type": "string", "enum": FOCUS},
                        "hypotheses": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "condition": {"type": "string", "enum": list(F.CONDITIONS)},
                                    "condition2": {"type": "string", "enum": list(F.CONDITIONS) + ["none"]},
                                    "outcome": {"type": "string", "enum": list(F.OUTCOMES)},
                                    "expect": {"type": "string", "enum": list(F.EXPECT)},
                                },
                                "required": ["condition", "condition2", "outcome", "expect"],
                                "additionalProperties": False,
                            },
                        },
                    },
                    "required": ["title", "rationale", "focus", "hypotheses"],
                    "additionalProperties": False,
                },
            },
            "store_direction": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "rationale": {"type": "string"},
                    "hypotheses": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "condition": {"type": "string", "enum": list(F.H.STORE_CONDITIONS)},
                                "condition2": {"type": "string", "enum": list(F.H.STORE_CONDITIONS) + ["none"]},
                                "outcome": {"type": "string", "enum": list(F.H.STORE_OUTCOMES)},
                                "expect": {"type": "string", "enum": list(F.EXPECT)},
                            },
                            "required": ["condition", "condition2", "outcome", "expect"],
                            "additionalProperties": False,
                        },
                    },
                },
                "required": ["title", "rationale", "hypotheses"],
                "additionalProperties": False,
            },
            "applied": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "parent_code": {"type": "string"},
                        "condition": {"type": "string", "enum": list(F.CONDITIONS)},
                        "condition2": {"type": "string", "enum": list(F.CONDITIONS) + ["none"]},
                        "outcome": {"type": "string", "enum": list(F.OUTCOMES)},
                        "expect": {"type": "string", "enum": list(F.EXPECT)},
                    },
                    "required": ["parent_code", "condition", "condition2", "outcome", "expect"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["directions", "applied", "store_direction"],
        "additionalProperties": False,
    }


def context(db, latest):
    deb = db.get("research_results", {"select": "payload->audit,payload->round", "research_type": "eq.round_debrief",
                                      "model_version": "eq.db-1.0", "order": "training_end_round.desc", "limit": "1"})
    audit = (deb[0].get("audit") or {}) if deb else {}
    try:
        hyps = db.get("strategy_hypotheses", {"select": "code,statement,status,verdict,simulation", "order": "created_at"})
    except RuntimeError:
        hyps = db.get("strategy_hypotheses", {"select": "code,statement,status,verdict", "order": "created_at"})
    lines = [f"최신 추첨 회차: {latest}회", "", "[조건 목록]"]
    lines += [f"- {k}: {v}" for k, v in F.CONDITIONS.items()]
    lines += ["", "[결과 목록]"] + [f"- {k}: {v}" for k, v in F.OUTCOMES.items()]
    lines += ["", "[판매점 조건 목록 — store_direction 용]"] + [f"- {k}: {v}" for k, v in F.H.STORE_CONDITIONS.items()]
    lines += ["", "[판매점 결과 목록]"] + [f"- {k}: {v}" for k, v in F.H.STORE_OUTCOMES.items()]
    lines += ["", "[기대 방향] higher=높다, lower=낮다", "", "[지난 회차 검증 보고 — 검수 문장]"]
    lines += [f"- {x}" for x in (audit.get("analyst") or []) + (audit.get("mathematician") or [])] or ["- (없음)"]
    # 살아있는 가설은 판정까지, 기각·폐기·데이터 미확보는 코드만 (다시 내지 말라는 표시 — 보내는 자료가 쌓이지 않게)
    closed = {"rejected", "discarded", "unsupported"}
    live = [h for h in hyps if h["status"] not in closed]
    dead = [h["code"] for h in hyps if h["status"] in closed]
    lines += ["", "[진행 중 · 통과 · 유지 가설과 판정]"]
    lines += [f"- [{h['status']}] {h['code']} — {h['statement']} — {h.get('verdict') or ''}"
              + (f" — 모의: {(h.get('simulation') or {}).get('note')}" if (h.get('simulation') or {}).get('note') else "")
              for h in live] or ["- (없음)"]
    lines += ["", f"[기각·폐기된 조합 {len(dead)}개 — 다시 제안하지 말 것]", ", ".join(dead) or "(없음)"]
    return "\n".join(lines)


class AiFailed(Exception):
    pass


def _strip_additional(x):
    """Gemini 스키마용: additionalProperties 제거 (지원 범위가 달라 제외)"""
    if isinstance(x, dict):
        return {k: _strip_additional(v) for k, v in x.items() if k != "additionalProperties"}
    if isinstance(x, list):
        return [_strip_additional(v) for v in x]
    return x


def ask_claude(prompt):
    """→ (데이터, 모델, 사용량). 거절·오류는 AiFailed"""
    import anthropic
    client = anthropic.Anthropic()
    try:
        resp = client.beta.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=16000,
            system=SYSTEM,
            messages=[{"role": "user", "content": prompt}],
            output_config={"effort": "medium", "format": {"type": "json_schema", "schema": schema()}},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
    except anthropic.APIStatusError as e:
        raise AiFailed(f"Claude API 오류 {e.status_code}") from e
    except anthropic.APIConnectionError as e:
        raise AiFailed("Claude API 연결 실패") from e
    usage = {"input_tokens": resp.usage.input_tokens, "output_tokens": resp.usage.output_tokens}
    if resp.stop_reason == "refusal":
        raise AiFailed("Claude 가 응답을 거절함")
    text = next(b.text for b in resp.content if b.type == "text")
    return json.loads(text), resp.model, usage


def ask_gemini(prompt):
    """Gemini Interactions API (google-genai). → (데이터, 모델, 사용량)"""
    from google import genai
    raw = os.environ["GEMINI_API_KEY"]
    m = re.search(r"AIza[0-9A-Za-z_\-]{35}", raw)   # 붙여넣기 때 섞인 보이지 않는 문자·중복 제거
    client = genai.Client(api_key=m.group(0) if m else raw.strip())
    try:
        it = client.interactions.create(
            model=GEMINI_MODEL,
            system_instruction=SYSTEM,
            input=prompt,
            response_format={"type": "text", "mime_type": "application/json", "schema": _strip_additional(schema())},
        )
    except Exception as e:  # SDK 예외 종류가 버전마다 달라 구글 오류 문장을 남김 (키처럼 보이는 문자열은 가림)
        msg = re.sub(r"AIza[0-9A-Za-z_\-]{20,}", "AIza***", str(e))[:400]
        raise AiFailed(f"Gemini API 오류: {type(e).__name__} — {msg}") from e
    status = getattr(it, "status", "completed")
    if status not in ("completed", None):
        raise AiFailed(f"Gemini 응답 상태 {status}")
    u = getattr(it, "usage", None)
    usage = {"input_tokens": getattr(u, "total_input_tokens", None),
             "output_tokens": (getattr(u, "total_output_tokens", 0) or 0) + (getattr(u, "total_thought_tokens", 0) or 0)}
    return json.loads(it.output_text), GEMINI_MODEL, usage


# 연결된 AI (키가 있는 것만, 회차당 각 1번) — 둘 다 있으면 둘 다 제안 → 화면에서 Claude/Gemini 구분
PROVIDERS = [("claude", "ANTHROPIC_API_KEY", ask_claude), ("gemini", "GEMINI_API_KEY", ask_gemini)]


def run(db, dry=False):
    latest = db.get("lotto_winning_numbers", {"select": "round", "order": "round.desc", "limit": "1"})[0]["round"]
    prompt = context(db, latest)
    if dry:
        print(prompt)
        print("\n드라이런 — AI 호출 안 함 · 연결된 AI:", [p for p, env, _ in PROVIDERS if os.environ.get(env)] or "없음")
        return None
    active = [(p, f) for p, env, f in PROVIDERS if os.environ.get(env)]
    if not active:
        print("AI 키 없음 — AI 전략기획부 건너뜀")
        db.insert("strategy_runs", {"kind": "ai_direction", "status": "skipped", "after_round": latest,
                                    "note": "API 키 미등록 — 수동 방향만 검증"})
        return None
    results = {}
    # 하루 1번 (한국시간 기준 오늘 0시 이후에 이미 제안했으면 건너뜀)
    now_kst = datetime.now(timezone.utc) + timedelta(hours=9)
    day_start = (datetime(now_kst.year, now_kst.month, now_kst.day, tzinfo=timezone.utc) - timedelta(hours=9)).isoformat()
    have = {h["code"] for h in db.get("strategy_hypotheses", {"select": "code"})}
    for name, ask in active:
        done = db.get("strategy_directions", {"select": "id", "source": "eq.ai", "created_at": f"gte.{day_start}",
                                              "model": f"ilike.*{name}*", "limit": "1"})
        if done:
            print(f"오늘 {name} 제안 이미 있음 — 건너뜀")
            continue
        try:
            data, model, usage = ask(prompt)
        except AiFailed as e:
            db.insert("strategy_runs", {"kind": "ai_direction", "status": "failed", "after_round": latest,
                                        "stats": {"provider": name}, "note": str(e)})
            print(f"{name}: {e}")
            continue
        saved_d, saved_h, dup = 0, 0, 0
        for d in (data.get("directions") or [])[:MAX_DIRECTIONS]:
            specs = []
            for h in d.get("hypotheses") or []:
                spec = {"condition": h["condition"], "outcome": h["outcome"], "expect": h["expect"]}
                if h.get("condition2") not in (None, "none", h["condition"]):
                    spec["condition2"] = h["condition2"]
                if not F.valid(spec):
                    continue
                code = F.spec_code(spec)
                if code in have:
                    dup += 1
                    continue
                if saved_h + len(specs) >= DAILY_HYPS:
                    break
                have.add(code)
                specs.append((spec["condition"], spec.get("condition2", "none"), spec["outcome"], spec["expect"]))
            if not specs:
                continue
            did = db.insert("strategy_directions", {"after_round": latest, "source": "ai", "model": model,
                                                    "title": d["title"][:200], "rationale": d["rationale"][:2000],
                                                    "focus": d.get("focus") if d.get("focus") in FOCUS else None})
            saved_h += F.add_hypotheses(db, did, specs, latest)
            saved_d += 1
        # 응용 가설: 이전 가설(parent_code)에 조건 보충 · 결과 변경 — 부모 가설의 방향 카드 아래로
        applied_saved = 0
        parent_dir = {h["code"]: h.get("direction_id") for h in db.get("strategy_hypotheses", {"select": "code,direction_id"})}
        for a in (data.get("applied") or []):
            if applied_saved >= DAILY_APPLIED:
                break
            par = a.get("parent_code")
            if par not in parent_dir:
                continue
            spec = {"condition": a["condition"], "outcome": a["outcome"], "expect": a["expect"], "kind": "applied", "parent": par}
            if a.get("condition2") not in (None, "none", a["condition"]):
                spec["condition2"] = a["condition2"]
            if not F.valid(spec) or F.spec_code(spec) in have:
                dup += 1
                continue
            have.add(F.spec_code(spec))
            applied_saved += F.add_specs(db, parent_dir[par], [spec], latest)
        # 판매점 가설 (명당) — 방향 1개로 묶어 저장
        store_saved = 0
        sd_ = data.get("store_direction") or {}
        sspecs = []
        for h in sd_.get("hypotheses") or []:
            spec = {"condition": h["condition"], "outcome": h["outcome"], "expect": h["expect"], "kind": "base", "level": "store"}
            if h.get("condition2") not in (None, "none", h["condition"]):
                spec.update(condition2=h["condition2"], kind="supplement")
            if not F.valid(spec) or F.spec_code(spec) in have:
                dup += 1
                continue
            if len(sspecs) >= DAILY_STORE:
                break
            have.add(F.spec_code(spec))
            sspecs.append(spec)
        if sspecs:
            sdid = db.insert("strategy_directions", {"after_round": latest, "source": "ai", "model": model,
                                                     "title": (sd_.get("title") or "판매점 가설")[:200],
                                                     "rationale": (sd_.get("rationale") or "")[:2000], "focus": "stores"})
            store_saved = F.add_specs(db, sdid, sspecs, latest)
            saved_d += 1
        stats = dict(usage, provider=name, model=model, version=VERSION, directions=saved_d, hypotheses=saved_h,
                     applied=applied_saved, store=store_saved, duplicates_skipped=dup)
        db.insert("strategy_runs", {"kind": "ai_direction", "status": "success", "after_round": latest, "stats": stats})
        print(f"{latest}회 {name}({model}) 방향 {saved_d}개 · 새 가설 {saved_h}개 · 응용 {applied_saved}개 · 판매점 {store_saved}개 · 중복 제외 {dup} · 토큰 {usage}")
        results[name] = stats
    return results


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
