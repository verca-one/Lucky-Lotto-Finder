"""
AI 전략기획부 (sa-1.1 · Claude · Gemini) — 회차 검증 결과를 읽고 다음 연구 '방향'만 제시한다

  · AI 가 하는 일: 방향 3개(제목·이유) + 방향마다 가설 최대 3개 (조건·결과·기대 방향은 가설 공장 어휘에서만 고름)
  · AI 가 못 하는 일: 번호·명당·장부·엔진에 접근하거나 바꾸는 것. AI 에게는 도구가 없고, 응답은 정해진 JSON 형식으로만 받아
    strategy_directions · strategy_hypotheses(제안 상태)에만 저장한다. 검증·유지·폐기는 비서(research_hypothesis_factory.py)가 한다.
  · 연결된 AI: ANTHROPIC_API_KEY → Claude(claude-opus-5-5), GEMINI_API_KEY → Gemini(gemini-3.8-flash).
    키가 있는 AI 마다 회차당 1번씩 제안 (둘 다 있으면 같은 자료로 각각 제안 → 검증 통과율로 비교). 키가 하나도 없으면 건너뜀.
입력: 최신 회차 검증 보고(round_debrief) 검수 문장 · 지금까지의 가설과 판정 — 저장된 수치만. 외부 사이트 접속 없음.

사용: python research_strategy_ai.py [--dry-run]   (드라이런: AI 호출 없이 보낼 내용만 출력)
"""

import argparse
import json
import os
import sys

import research_hypothesis_factory as F
import research_review_worker as R

VERSION = "sa-1.1"
CLAUDE_MODEL = "claude-opus-5-5"
GEMINI_MODEL = "gemini-3.8-flash"   # 무료 등급 있음 (ai.google.dev 요금표)
MAX_DIRECTIONS = 3
MAX_HYPS = 3
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

방향 3개를 내고, 방향마다 이유(왜 이 방향이 유망한지, 지난 결과의 어떤 수치를 근거로 했는지)를 한국어로 짧게 쓰고,
방향마다 가설을 1~3개 고르세요."""


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
        },
        "required": ["directions"],
        "additionalProperties": False,
    }


def context(db, latest):
    deb = db.get("research_results", {"select": "payload->audit,payload->round", "research_type": "eq.round_debrief",
                                      "model_version": "eq.db-1.0", "order": "training_end_round.desc", "limit": "1"})
    audit = (deb[0].get("audit") or {}) if deb else {}
    hyps = db.get("strategy_hypotheses", {"select": "code,statement,status,verdict", "order": "created_at"})
    lines = [f"최신 추첨 회차: {latest}회", "", "[조건 목록]"]
    lines += [f"- {k}: {v}" for k, v in F.CONDITIONS.items()]
    lines += ["", "[결과 목록]"] + [f"- {k}: {v}" for k, v in F.OUTCOMES.items()]
    lines += ["", "[기대 방향] higher=높다, lower=낮다", "", "[지난 회차 검증 보고 — 검수 문장]"]
    lines += [f"- {x}" for x in (audit.get("analyst") or []) + (audit.get("mathematician") or [])] or ["- (없음)"]
    # 살아있는 가설은 판정까지, 기각·폐기·데이터 미확보는 코드만 (다시 내지 말라는 표시 — 보내는 자료가 쌓이지 않게)
    closed = {"rejected", "discarded", "unsupported"}
    live = [h for h in hyps if h["status"] not in closed]
    dead = [h["code"] for h in hyps if h["status"] in closed]
    lines += ["", "[진행 중 · 통과 · 유지 가설과 판정]"]
    lines += [f"- [{h['status']}] {h['code']} — {h['statement']} — {h.get('verdict') or ''}" for h in live] or ["- (없음)"]
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
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    try:
        it = client.interactions.create(
            model=GEMINI_MODEL,
            system_instruction=SYSTEM,
            input=prompt,
            response_format={"type": "text", "mime_type": "application/json", "schema": _strip_additional(schema())},
        )
    except Exception as e:  # SDK 예외 종류가 버전마다 달라 메시지만 남김 (키 값은 포함되지 않음)
        raise AiFailed(f"Gemini API 오류: {type(e).__name__}") from e
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
    for name, ask in active:
        done = db.get("strategy_directions", {"select": "id", "source": "eq.ai", "after_round": f"eq.{latest}",
                                              "model": f"ilike.*{name}*", "limit": "1"})
        if done:
            print(f"{latest}회 {name} 방향 이미 있음 — 건너뜀")
            continue
        try:
            data, model, usage = ask(prompt)
        except AiFailed as e:
            db.insert("strategy_runs", {"kind": "ai_direction", "status": "failed", "after_round": latest,
                                        "stats": {"provider": name}, "note": str(e)})
            print(f"{name}: {e}")
            continue
        saved_d, saved_h = 0, 0
        for d in (data.get("directions") or [])[:MAX_DIRECTIONS]:
            did = db.insert("strategy_directions", {"after_round": latest, "source": "ai", "model": model,
                                                    "title": d["title"][:200], "rationale": d["rationale"][:2000],
                                                    "focus": d.get("focus") if d.get("focus") in FOCUS else None})
            specs = [(h["condition"], h.get("condition2", "none"), h["outcome"], h["expect"])
                     for h in (d.get("hypotheses") or [])[:MAX_HYPS]]
            saved_h += F.add_hypotheses(db, did, specs, latest)
            saved_d += 1
        stats = dict(usage, provider=name, model=model, version=VERSION, directions=saved_d, hypotheses=saved_h)
        db.insert("strategy_runs", {"kind": "ai_direction", "status": "success", "after_round": latest, "stats": stats})
        print(f"{latest}회 {name}({model}) 방향 {saved_d}개 · 가설 {saved_h}개 저장 · 토큰 {usage}")
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
