"""
research_agent_worker.py — 전국 지방장 에이전트 v1.0 (ag-1.0) + 중앙 엔진 (2026-10-11)

* 기존 크롤러·엔진과 독립. 기존 테이블(lottery_stores, winning_history, lotto_winning_numbers,
  research_prize_stats)은 읽기만 하고, research_v5_agents.sql 의 신규 테이블에만 쓴다.
* 외부 유료 AI API 0회. 지방장 = 지역별로 데이터·가설·상태를 분리한 '논리적 에이전트'이며
  하나의 계산형 엔진이 지역 작업을 순서대로 처리한다 (지역별 상시 프로세스 없음).
* 서버(GitHub Actions 'Research Worker')에서 앱과 무관하게 실행. 쓰기에는 service_role 키가 필요하다.

지방장 배정: 광역시 구·군, 도 시·군(일반시는 하위 구·읍·면·동 연구 포함), 세종, 제주시·서귀포시, 인터넷 판매.
판매점 고유 ID = dhlottery_code. 이름·주소가 같은 다중 코드는 중복 후보로 표시만 한다(병합 근거 없음).

연구 (회차 t 의 예측에는 t-1 이하 데이터만 사용)
  · 판매점 이력·간격·주기(유명/신흥)                      store_cycle, cycle_pooled
  · 같은 회차 동시 당첨 (판매점·지역, 예측 불가 연관)       store_cowin, region_cowin
  · 선행·후행 +1~+6회 (판매점→판매점, 지역→판매점, 지역→지역, 자기 반복)
                                                           store_lead, region_store_lead, region_lead, self_repeat
  · 거리별 공간전이 (당첨 판매점 주변 1/3km)               neighbor_spill(지방장 단위), store_spill(판매점 단위)
  · 집중·감소·미출현                                       region_trend_up / region_trend_down / region_dormant
  · 복합 가설 (주기 ∧ 선행)                                composite,  다중 조건 동시 충족 분석 multi_condition

검증
  · 발견: 체크포인트 c(999,1049,…, 최신) 마다 c 이하 데이터로 전체 후보 검정 → BH-FDR(전체 검정 수 기준) q<0.10
          + 지방장별 탐색적 상위 후보(유의하지 않음 표시)
  · 순방향(미래) 검증: 발견 이후 회차만. 매 회차 '판정 가능' 가설(시행≥20, 기대 사건≥3) 전체에 BH q<0.05
  · 상태: discovered → researching → passed / weakened / rejected (복합은 combined)
  · 실전 추천에는 passed/combined 만 반영(live). 연구 중 가설은 탐색 목록(exploratory)에만 반영해 분리 평가.
  · 공유: 지방장 단위 템플릿(cycle_pooled, neighbor_spill, self_repeat)이 한 지방장에서 유의하면
          다른 모든 지방장이 자기 데이터로 같은 템플릿을 검증 (shared_from 기록, canonical_key 로 중복 제거,
          방향이 반대로 유의한 지방장이 있으면 상충으로 기록)

판매점별 판매량이 없으므로 점수는 '회차당 1·2등 기대 빈도(판매량 미보정)'이며 한 장당 당첨확률이 아니다.

사용:
  python research_agent_worker.py                      # 최신 회차까지 (완료면 건너뜀)
  python research_agent_worker.py --force
  python research_agent_worker.py --dry-run --out agent.json
  python research_agent_worker.py --selftest-leak 1100 # 미래 데이터 누출 검사 (1100회까지만 준 결과와 비교)
환경변수: SUPABASE_URL, SUPABASE_KEY (쓰기: service_role)
"""
import argparse, base64, hashlib, json, math, os, sys, time
from collections import Counter, defaultdict
from datetime import datetime, timezone

import numpy as np
import requests
from scipy import sparse
from scipy.stats import binom, norm

from research_region_worker import Db, clean, _json_default, parse_region, hav_km, valid_geo, log

MODEL = "ag-1.0"
STORE_DATA_START = 262
LEARN_START = 1000
CP_FIRST, CP_STEP = 999, 50
K_DELIVER = 5
CENTRAL_REGIONS, CENTRAL_STORES = 10, 20
HALF_LIFE = 150.0
LAGS = (1, 2, 3, 4, 5, 6)
NEIGH_KM = (1.0, 3.0)
MIN_EVENTS_PAIR = 8
MIN_EVENTS_CYCLE = 6
DISC_Q, PASS_Q = 0.10, 0.05
MIN_TRIALS, MIN_EXPECTED = 20, 3.0
FACTOR_CAP = 3.0
TREND_HORIZON = 100
STATUS = ["discovered", "researching", "passed", "weakened", "rejected", "combined"]
S_DISC, S_RES, S_PASS, S_WEAK, S_REJ, S_COMB = range(6)
# 실전·탐색 점수 보정에 쓰는 가설 (추세·미출현은 지속성 서술 검정이라 보정에 쓰지 않음, 동시 당첨은 예측 불가)
BOOST_KINDS = {"store_lead", "region_store_lead", "region_lead", "self_repeat", "store_cycle", "cycle_pooled",
               "neighbor_spill", "store_spill", "composite"}
NULL_PRIOR = 5.0            # 순방향 검정 귀무 비율의 약한 사전 (pseudo-rounds)
TUNE_FROM, TUNE_TO = 600, 999   # 감쇠·사전 강도 선택 구간 (학습 시작 전 데이터만)
HL_GRID = (75.0, 150.0, 300.0, 600.0, 1e9)
BETA_GRID = (50.0, 300.0, 2000.0, 20000.0)
PREDICTIVE_KINDS = {"store_lead", "region_store_lead", "region_lead", "self_repeat", "store_cycle", "cycle_pooled",
                    "neighbor_spill", "store_spill", "region_trend_up", "region_trend_down", "region_dormant", "composite"}
TABLES = ["research_agents", "research_agent_hypotheses", "research_agent_hypothesis_events", "research_agent_relations",
          "research_agent_deliveries", "research_agent_store_scores", "research_agent_round_evals", "research_agent_central",
          "research_agent_central_evals", "research_agent_briefings", "research_agent_runs", "research_agent_jobs"]


# ── 통계 유틸 ──────────────────────────────────────────────────────
def bh_total(p, total):
    """BH-FDR. 계산하지 않은 검정(p≈1)까지 포함한 전체 검정 수 total 기준."""
    p = np.asarray(p, dtype=float)
    n = len(p)
    if n == 0:
        return p
    total = max(int(total), n)
    order = np.argsort(p, kind="stable")
    adj = p[order] * total / np.arange(1, n + 1)
    adj = np.minimum.accumulate(adj[::-1])[::-1]
    q = np.empty(n)
    q[order] = np.minimum(adj, 1.0)
    return q


def p_one_sided(k, n, p0, up):
    k = np.asarray(k, dtype=float)
    n = np.asarray(n, dtype=float)
    p0 = np.clip(np.asarray(p0, dtype=float), 1e-12, 1 - 1e-9)
    pu = binom.sf(k - 1, n, p0)
    pd = binom.cdf(k, n, p0)
    return np.where(up, pu, pd)


def hid(canonical):
    return "ag1-" + hashlib.sha1(canonical.encode("utf-8")).hexdigest()[:14]


def key_role(key):
    if key.startswith("sb_secret_"):
        return "service_role"
    try:
        part = key.split(".")[1]
        part += "=" * (-len(part) % 4)
        return json.loads(base64.urlsafe_b64decode(part)).get("role")
    except Exception:
        return None


def norm_txt(s):
    return "".join((s or "").split())


# ── 데이터 ─────────────────────────────────────────────────────────
def load(db):
    log("[load] lottery_stores (lotto)")
    stores = db.select_keyset("lottery_stores", {
        "select": "dhlottery_code,store_name,address,region,latitude,longitude", "lottery_type": "eq.lotto"})
    log(f"  {len(stores)}")
    log("[load] winning_history (lotto 1·2등)")
    hist = db.select_keyset("winning_history", {
        "select": "dhlottery_code,round,prize_tier", "lottery_type": "eq.lotto", "prize_tier": "in.(first,second)"})
    log(f"  {len(hist)}")
    nums = db.select_all("lotto_winning_numbers", {"select": "round", "order": "round"})
    prize = {}
    if db.exists("research_prize_stats"):
        for r in db.select_all("research_prize_stats", {"select": "round,rank1_winners", "order": "round"}):
            prize[r["round"]] = r["rank1_winners"]
    crawl = None
    if db.exists("round_crawl_status"):     # 크롤러가 남기는 회차별 판매점 수집 완료 표시 (읽기 전용)
        crawl = {r["round"]: r.get("stores_status") for r in db.select_all(
            "round_crawl_status", {"select": "round,stores_status", "lottery_type": "eq.lotto", "order": "lottery_type,round"})}
    return {"stores": stores, "hist": hist, "latest": max(r["round"] for r in nums), "prize": prize,
            "number_rounds": sorted({r["round"] for r in nums}), "crawl": crawl}


def ready_latest(raw, floor=LEARN_START):
    """당첨번호·1등 판매점·2등 판매점·크롤링 완료가 모두 갖춰진 마지막 회차 (미준비 회차는 학습하지 않음)"""
    cnt = Counter((h["round"], h["prize_tier"]) for h in raw["hist"])
    crawl = raw.get("crawl")
    crawl_from = min(crawl) if crawl else None
    numbers = set(raw.get("number_rounds") or [raw["latest"]])
    pending = []
    r = raw["latest"]
    while r >= floor:
        why = []
        if r not in numbers:
            why.append("당첨번호 없음")
        if crawl is not None and r >= crawl_from and crawl.get(r) != "success":
            why.append(f"판매점 크롤링 완료 표시 없음({crawl.get(r)})")
        f, s2 = cnt[(r, "first")], cnt[(r, "second")]
        p1 = raw["prize"].get(r)
        if s2 == 0:
            why.append("2등 판매점 기록 없음")
        if f == 0 and p1 != 0:
            why.append("1등 판매점 기록 없음")
        elif p1 and f < 0.8 * p1:
            why.append(f"1등 판매점 기록 부족 {f}/{p1}")
        if not why:
            return r, pending
        pending.append({"round": r, "reasons": why})
        r -= 1
    return r, pending


class Universe:
    """판매점·지방장·회차 행렬 (latest 까지)"""

    def __init__(self, raw, latest, base=None):
        """base: 이전 실행의 판매점·지방장 순서 {"codes", "agent_ids", "stores"} — 인덱스를 고정하고 신규는 뒤에 추가
        (상태 저장·재개용. 목록에서 사라진 판매점도 이전 정보로 유지)"""
        self.latest = latest
        by_code = {}
        for s in raw["stores"]:
            c = s.get("dhlottery_code")
            if c and c not in by_code:
                by_code[c] = s
        if base:
            for c, m in base["stores"].items():
                by_code.setdefault(c, m)
            known = set(base["codes"])
            self.codes = list(base["codes"]) + sorted(c for c in by_code if c not in known)
        else:
            self.codes = sorted(by_code)
        self.store_snapshot = {c: {k: by_code[c].get(k) for k in ("dhlottery_code", "store_name", "address", "region",
                                                                    "latitude", "longitude")} for c in self.codes}
        S = self.S = len(self.codes)
        self.cidx = {c: i for i, c in enumerate(self.codes)}
        self.name, self.addr, self.sub = [], [], []
        rid_list = []
        self.lat = np.full(S, np.nan)
        self.lng = np.full(S, np.nan)
        unparsed = 0
        for i, c in enumerate(self.codes):
            s = by_code[c]
            rid, sido, unit, sub = parse_region(s.get("region"), s.get("address"), s.get("store_name"))
            if rid is None:
                unparsed += 1
            rid_list.append(rid)
            self.name.append(s.get("store_name") or c)
            self.addr.append(s.get("address") or "")
            self.sub.append(sub)
            try:
                la, ln = float(s.get("latitude")), float(s.get("longitude"))
                if valid_geo(la, ln):
                    self.lat[i], self.lng[i] = la, ln
            except (TypeError, ValueError):
                pass
        self.unparsed = unparsed
        self.agent_ids = sorted({r for r in rid_list if r and r != "internet"}) + (["internet"] if "internet" in rid_list else [])
        if base:
            known_a = set(base["agent_ids"])
            self.agent_ids = list(base["agent_ids"]) + sorted(a for a in set(self.agent_ids) if a not in known_a)
        self.aidx = {a: i for i, a in enumerate(self.agent_ids)}
        self.st_agent = np.array([self.aidx.get(r, -1) if r else -1 for r in rid_list])
        self.reg_ids = [a for a in self.agent_ids if a != "internet"]
        self.U = len(self.reg_ids)
        self.ridx = {a: i for i, a in enumerate(self.reg_ids)}
        self.st_reg = np.array([self.ridx.get(r, -1) if r else -1 for r in rid_list])
        self.members = [np.where(self.st_agent == a)[0] for a in range(len(self.agent_ids))]
        self.geo = ~np.isnan(self.lat)

        # 중복 후보 (이름+주소 동일 / 주소 동일)
        groups = defaultdict(list)
        for i in range(S):
            if self.addr[i]:
                groups[norm_txt(self.addr[i]) + "|" + norm_txt(self.name[i])].append(i)
        self.dup = np.zeros(S, bool)
        self.dup_groups_by_agent = Counter()
        for g in groups.values():
            if len(g) > 1:
                self.dup[g] = True
                self.dup_groups_by_agent[self.st_agent[g[0]]] += 1

        # 회차 행렬
        self.r0 = STORE_DATA_START
        self.rounds = np.arange(self.r0, latest + 1)
        R = self.R = len(self.rounds)
        self.E = np.zeros((R, S), dtype=np.int8)
        self.F = np.zeros((R, S), dtype=np.int8)
        has_first = np.zeros(R, bool)
        unknown_first = unknown_second = 0
        for h in raw["hist"]:
            r = h["round"]
            if r < self.r0 or r > latest:
                continue
            row = r - self.r0
            i = self.cidx.get(h["dhlottery_code"])
            first = h["prize_tier"] == "first"
            if first:
                has_first[row] = True
            if i is None:
                if first:
                    unknown_first += 1
                else:
                    unknown_second += 1
                continue
            self.E[row, i] = 1
            if first:
                self.F[row, i] = 1
        prize = raw["prize"]
        self.valid = np.array([has_first[j] or prize.get(int(self.rounds[j])) == 0 for j in range(R)])
        self.missing_rounds = [int(self.rounds[j]) for j in range(R) if not self.valid[j]]
        self.unknown_first, self.unknown_second = unknown_first, unknown_second
        # 지역 1등 행렬 (인터넷·미매칭 제외)
        self.RF = np.zeros((R, self.U), dtype=np.int8)
        self.RFc = np.zeros((R, self.U), dtype=np.int16)   # 지역 1등 판매점 수
        reg_mask = self.st_reg >= 0
        rows, cols = np.nonzero(self.F[:, reg_mask])
        regs = self.st_reg[reg_mask][cols]
        np.add.at(self.RFc, (rows, regs), 1)
        self.RF = (self.RFc > 0).astype(np.int8)
        self.share = np.array([len(self.members[self.aidx[r]]) for r in self.reg_ids], float)
        self.share /= self.share.sum()

        # 이웃 (1/3km) 희소 행렬과 '주변 판매점 당첨' 행렬 NE_d[t, s]
        self.nb = {}
        self.NE = {}
        gi = np.where(self.geo)[0]
        cell = {}
        for i in gi:
            cell.setdefault((int(self.lat[i] / 0.03), int(self.lng[i] / 0.03)), []).append(i)
        rows_d = {d: [] for d in NEIGH_KM}
        cols_d = {d: [] for d in NEIGH_KM}
        for i in gi:
            cy, cx = int(self.lat[i] / 0.03), int(self.lng[i] / 0.03)
            cand = []
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    cand.extend(cell.get((cy + dy, cx + dx), []))
            cand = np.array([j for j in cand if j != i])
            if len(cand) == 0:
                continue
            dist = hav_km(self.lat[i], self.lng[i], self.lat[cand], self.lng[cand])
            for d in NEIGH_KM:
                sel = cand[dist <= d]
                rows_d[d].extend([i] * len(sel))
                cols_d[d].extend(sel.tolist())
        Es = sparse.csr_matrix(self.E.astype(np.float32))
        for d in NEIGH_KM:
            N = sparse.csr_matrix((np.ones(len(rows_d[d]), np.float32), (rows_d[d], cols_d[d])), shape=(S, S))
            self.nb[d] = N
            # NE[t, s] = s 의 d km 이웃 중 t 회차 1·2등 판매점이 있는가
            self.NE[d] = ((Es @ N.T).toarray() > 0).astype(np.int8)

    def row(self, rnd):
        return int(rnd) - self.r0


# ── 학습 시점 비율 ────────────────────────────────────────────────
def store_rates(u, ci):
    """체크포인트 행 ci(포함)까지: 판매점 사건률 p_s (첫 사건 이후 노출 기준, 지방장 평균으로 축소)"""
    Ev = u.E[:ci + 1] * u.valid[:ci + 1, None]
    cnt = Ev.sum(0).astype(float)
    vcum = np.cumsum(u.valid[:ci + 1])
    has = cnt > 0
    first = np.where(has, Ev.argmax(0), 0)
    expo = np.where(has, vcum[ci] - vcum[first], vcum[ci]).astype(float)
    k = np.where(has, cnt - 1, 0.0)
    A = len(u.agent_ids)
    ag = np.where(u.st_agent >= 0, u.st_agent, A)
    ks = np.bincount(ag, k, minlength=A + 1)
    ns = np.bincount(ag, expo, minlength=A + 1)
    m = np.where(ns > 0, ks / np.maximum(ns, 1), k.sum() / max(expo.sum(), 1))[ag]
    a = 100.0
    return (k + a * m) / (expo + a), cnt


def region_rates(u, ci):
    v = u.valid[:ci + 1]
    return u.RF[:ci + 1][v].mean(0) if v.any() else np.zeros(u.U)


# ── 가설 저장소 ───────────────────────────────────────────────────
class Store:
    def __init__(self):
        self.H = []
        self.by_key = {}

    def add(self, h, c):
        key = h["canonical_key"]
        if key in self.by_key:
            old = self.H[self.by_key[key]]
            if c != old["discovered_round"] and old["evidence"].get("rediscovered_last") != int(c):
                old["evidence"]["rediscovered_count"] = old["evidence"].get("rediscovered_count", 0) + 1
                old["evidence"]["rediscovered_last"] = int(c)
            if h.get("shared_from") is None and old.get("shared_from") is not None and h["discovery_significant"]:
                af = old["evidence"].setdefault("also_found_by", [])
                if h["agent_id"] not in af:
                    af.append(h["agent_id"])
            return self.by_key[key]
        h["hypothesis_id"] = hid(key)
        h["discovered_round"] = int(c)
        h["idx"] = len(self.H)
        self.by_key[key] = h["idx"]
        self.H.append(h)
        return h["idx"]


def base_h(kind, scope, key, agent, direction="up", **kw):
    h = {"kind": kind, "scope": scope, "canonical_key": key, "agent_id": agent, "direction": direction,
         "predictive": kind in PREDICTIVE_KINDS, "source_region": None, "target_region": None, "source_store": None,
         "target_store": None, "related_regions": [], "related_stores": [], "lag": None, "params": {},
         "shared_from": None, "shared_by_agent": None, "shared_to_count": 0, "discovery_significant": False,
         "train_n": None, "train_k": None, "train_expected": None, "train_p": None, "train_q": None, "evidence": {}}
    h.update(kw)
    return h


# ── 발견 (체크포인트 c 이하 데이터만) ─────────────────────────────
def discover(u, st, ci, ps, pcnt, pr, stats, full=True):
    """full=False: 유의(BH q<0.10) 발견·템플릿 공유만 (탐색 상위·추세·복합은 50회 체크포인트에서만)"""
    c = int(u.rounds[ci])
    t0 = time.time()
    V = u.valid[:ci + 1].astype(np.float32)
    agent_name = u.agent_ids
    n_before = len(st.H)

    def add_pairs(kind, scope, rows_a, rows_b, k, n, p0, total, src_is_region, lag, explore_per_agent, min_k):
        """쌍 검정 결과 → BH → 유의 + 지방장별 탐색 상위"""
        if len(k) == 0:
            return []
        p = binom.sf(k - 1, n, np.clip(p0, 1e-12, 1 - 1e-9))
        q = bh_total(p, total)
        tgt_agent = u.st_agent[rows_b] if scope != "region_pair" else np.array([u.aidx[u.reg_ids[b]] for b in rows_b])
        keep = set(np.where(q < DISC_Q)[0].tolist())
        sig = set(keep)
        if explore_per_agent:
            order = np.argsort(p, kind="stable")
            taken = Counter()
            for j in order:
                a = tgt_agent[j]
                if a < 0 or taken[a] >= explore_per_agent or k[j] < min_k:
                    continue
                taken[a] += 1
                keep.add(j)
        rel = []
        for j in sorted(keep, key=lambda j: (p[j], j)):
            a, b = int(rows_a[j]), int(rows_b[j])
            ag = int(tgt_agent[j])
            if ag < 0:
                continue
            exp_ = float(n[j] * p0[j])
            common = dict(lag=lag, train_n=int(n[j]), train_k=int(k[j]), train_expected=exp_, train_p=float(p[j]),
                          train_q=float(q[j]), discovery_significant=j in sig)
            if kind in ("store_lead", "store_cowin"):
                ca, cb = u.codes[a], u.codes[b]
                ra = u.agent_ids[u.st_agent[a]] if u.st_agent[a] >= 0 else None
                rb = agent_name[ag]
                key = f"store_cowin|{min(ca, cb)}|{max(ca, cb)}" if kind == "store_cowin" else f"store_lead|{ca}|{cb}|L{lag}"
                h = base_h(kind, "store_pair", key, rb, source_store=ca, target_store=cb, source_region=ra, target_region=rb,
                           related_stores=[ca, cb], related_regions=sorted({x for x in (ra, rb) if x}),
                           params={"cross_region": ra != rb}, **common)
                h["_a"], h["_b"] = a, b
                h["_p0"] = float(p0[j])
            elif kind == "region_store_lead":
                A = u.reg_ids[a]
                cb = u.codes[b]
                rb = agent_name[ag]
                key = f"region_store_lead|{A}|{cb}|L{lag}"
                h = base_h(kind, "region_store", key, rb, source_region=A, target_region=rb, target_store=cb,
                           related_stores=[cb], related_regions=sorted({A, rb}), params={"cross_region": A != rb}, **common)
                h["_A"], h["_b"] = a, b
                h["_p0"] = float(p0[j])
            else:
                raise ValueError(kind)
            h["_lag"] = lag
            st.add(h, c)
            rel.append((kind, h.get("source_store") or h.get("source_region"), h.get("target_store"),
                        lag, h.get("source_region"), h.get("target_region"), int(n[j]), int(k[j]), exp_, float(p[j]), float(q[j])))
        return rel

    relations = []
    # 1) 판매점 쌍 (동시·선행) — 사건 MIN_EVENTS_PAIR 이상 판매점 (인터넷 제외)
    elig = np.where((pcnt >= MIN_EVENTS_PAIR) & (u.st_reg >= 0))[0]
    m = len(elig)
    M = (u.E[:ci + 1, elig] * u.valid[:ci + 1, None]).astype(np.float32)
    for L in (0,) + LAGS:
        if L == 0:
            C = M.T @ M
            np.fill_diagonal(C, 0)
            na = M.sum(0)
            total = m * (m - 1)
            kind, min_k = "store_cowin", 3
        else:
            Ma = M[:-L] * V[L:, None]
            C = Ma.T @ M[L:]
            np.fill_diagonal(C, 0)
            na = Ma.sum(0)
            total = m * (m - 1)
            kind, min_k = "store_lead", 2
        ai, bi = np.nonzero(C >= min_k)
        if kind == "store_cowin":
            sel = ai < bi                      # 대칭 → 한 번만 (작은 p 방향은 p0 차이가 작아 무시)
            ai, bi = ai[sel], bi[sel]
            total //= 2
        k = C[ai, bi].astype(float)
        relations += add_pairs(kind, "store_pair", elig[ai], elig[bi], k, na[ai].astype(float), ps[elig[bi]], total, False, L,
                               1 if full else 0, min_k)
        stats[f"tests_{kind}"] = stats.get(f"tests_{kind}", 0) + total
    del M
    # 2) 지역 → 판매점 (+1~+6)
    RFv = (u.RF[:ci + 1] * u.valid[:ci + 1, None]).astype(np.float32)
    Mb = (u.E[:ci + 1, elig] * u.valid[:ci + 1, None]).astype(np.float32)
    for L in LAGS:
        Ra = RFv[:-L] * V[L:, None]
        C = Ra.T @ Mb[L:]
        nA = Ra.sum(0)
        ai, bi = np.nonzero(C >= 2)
        # 자기 지역 → 자기 판매점은 판매점 자신의 1등이 트리거에 포함될 수 있어 제외
        sel = u.st_reg[elig[bi]] != ai
        ai, bi = ai[sel], bi[sel]
        total = u.U * m
        relations += add_pairs("region_store_lead", "region_store", ai, elig[bi], C[ai, bi].astype(float), nA[ai].astype(float),
                               ps[elig[bi]], total, True, L, 1 if full else 0, 2)
        stats["tests_region_store_lead"] = stats.get("tests_region_store_lead", 0) + total
    del Mb

    # 3) 지역 → 지역 (동시 0, 선행 +1~+6, 증가/감소)
    U = u.U
    for L in (0,) + LAGS:
        if L == 0:
            C = RFv.T @ RFv
            nA = RFv.sum(0)
        else:
            Ra = RFv[:-L] * V[L:, None]
            C = Ra.T @ RFv[L:]
            nA = Ra.sum(0)
        A_, B_ = np.meshgrid(np.arange(U), np.arange(U), indexing="ij")
        A_, B_ = A_.ravel(), B_.ravel()
        if L == 0:
            sel = A_ < B_
            A_, B_ = A_[sel], B_[sel]
        k = C[A_, B_].astype(float)
        n = nA[A_].astype(float)
        p0 = pr[B_]
        ok = n > 0
        A_, B_, k, n, p0 = A_[ok], B_[ok], k[ok], n[ok], p0[ok]
        for up in (True, False):
            p = p_one_sided(k, n, p0, up)
            total = len(p) * 1
            q = bh_total(p, total * 2)       # 증가·감소 양방향
            direction = "up" if up else "down"
            kind0 = "region_cowin" if L == 0 else "region_lead"
            keep = set(np.where(q < DISC_Q)[0].tolist())
            sig = set(keep)
            if full and up and L > 0:        # 지방장별 탐색: 들어오는 선행 관계 1개
                taken = set()
                for j in np.argsort(p, kind="stable"):
                    b = B_[j]
                    if b in taken or k[j] < 2:
                        continue
                    taken.add(b)
                    keep.add(j)
            for j in sorted(keep, key=lambda j: (p[j], j)):
                A, B = u.reg_ids[A_[j]], u.reg_ids[B_[j]]
                kind = "self_repeat" if (A == B and L > 0) else kind0
                key = (f"region_cowin|{min(A, B)}|{max(A, B)}|{direction}" if L == 0
                       else f"{kind}|{A}|{B}|L{L}|{direction}")
                exp_ = float(n[j] * p0[j])
                h = base_h(kind, "region_pair", key, B, direction, source_region=A, target_region=B, lag=L,
                           related_regions=sorted({A, B}), train_n=int(n[j]), train_k=int(k[j]), train_expected=exp_,
                           train_p=float(p[j]), train_q=float(q[j]), discovery_significant=j in sig)
                h["_A"], h["_B"], h["_lag"], h["_p0"] = int(A_[j]), int(B_[j]), L, float(p0[j])
                st.add(h, c)
                relations.append(("region_cowin" if L == 0 else "region_lead", A, B, L, A, B, int(n[j]), int(k[j]), exp_,
                                  float(p[j]), float(q[j])))
            stats["tests_region_pair"] = stats.get("tests_region_pair", 0) + total

    # 4) 판매점 주기 (개별) + 지방장 통합 주기 템플릿
    vrows = np.where(u.valid[:ci + 1])[0]
    cyc_rows = []
    pooled = defaultdict(lambda: [0, 0, 0.0, []])   # agent → n, k, exp, members[(s, lo, hi)]
    for s in np.where((pcnt >= MIN_EVENTS_CYCLE) & (u.st_agent >= 0))[0]:
        ev = np.where(u.E[:ci + 1, s] * u.valid[:ci + 1])[0]
        gaps = np.diff(ev)
        if len(gaps) < MIN_EVENTS_CYCLE - 1:
            continue
        lo = max(1, int(np.floor(np.percentile(gaps, 25))))
        hi = max(lo, int(np.ceil(np.percentile(gaps, 75))))
        t = vrows[vrows > ev[1]]
        pos = np.searchsorted(ev, t, side="left") - 1
        d = t - ev[pos]
        fire = (d >= lo) & (d <= hi)
        n = int(fire.sum())
        if n == 0:
            continue
        k = int(u.E[t[fire], s].sum())
        cyc_rows.append((s, lo, hi, n, k, float(ps[s]), gaps))
        a = int(u.st_agent[s])
        pooled[a][0] += n
        pooled[a][1] += k
        pooled[a][2] += n * float(ps[s])
        pooled[a][3].append((int(s), lo, hi))
    if cyc_rows:
        k = np.array([r[4] for r in cyc_rows], float)
        n = np.array([r[3] for r in cyc_rows], float)
        p0 = np.array([r[5] for r in cyc_rows])
        p = p_one_sided(k, n, p0, True)
        q = bh_total(p, len(p))
        famous_cut = np.percentile(pcnt[pcnt > 0], 99) if (pcnt > 0).any() else 1e9
        best_by_agent = {}
        for j, r in enumerate(cyc_rows):
            a = int(u.st_agent[r[0]])
            if a not in best_by_agent or p[j] < p[best_by_agent[a]]:
                best_by_agent[a] = j
        for j, (s, lo, hi, nn, kk, p0j, gaps) in enumerate(cyc_rows):
            famous = pcnt[s] >= famous_cut
            if not (q[j] < DISC_Q or (full and (famous or best_by_agent.get(int(u.st_agent[s])) == j))):
                continue
            ag = u.agent_ids[u.st_agent[s]]
            cd = u.codes[s]
            h = base_h("store_cycle", "store", f"store_cycle|{cd}", ag, target_store=cd, target_region=ag,
                       related_stores=[cd], related_regions=[ag],
                       params={"lo": lo, "hi": hi, "gap_mean": float(gaps.mean()), "gap_median": float(np.median(gaps)),
                               "gap_var": float(gaps.var()), "gap_cv": float(gaps.std() / max(gaps.mean(), 1e-9)),
                               "events": int(pcnt[s]), "famous": bool(famous)},
                       train_n=int(nn), train_k=int(kk), train_expected=float(nn * p0j), train_p=float(p[j]),
                       train_q=float(q[j]), discovery_significant=bool(q[j] < DISC_Q))
            h["_s"], h["_lo"], h["_hi"], h["_p0"] = int(s), lo, hi, float(p0j)
            st.add(h, c)
    stats["tests_store_cycle"] = stats.get("tests_store_cycle", 0) + len(cyc_rows)

    # 지방장 단위 템플릿: cycle_pooled / neighbor_spill / self_repeat(위에서 지역쌍으로 처리)
    templates = []   # (kind, params_key, agent, n, k, exp, p, payload)
    for a, (n, k, e, mem) in pooled.items():
        templates.append(("cycle_pooled", "", a, n, k, e, mem, "up"))
    pexp = {}
    for d in NEIGH_KM:
        N = u.nb[d]
        # 주변 판매점 중 하나 이상 사건 확률 (학습 비율 기준)
        logq = N @ np.log1p(-np.clip(ps, 0, 0.999))
        pexp[d] = 1 - np.exp(logq)
        NE = u.NE[d][:ci + 1]
        for L in LAGS:
            trig = (u.E[:ci + 1 - L] * u.valid[:ci + 1 - L, None] * u.valid[L:ci + 1, None]).astype(np.int32)
            hits = (trig * NE[L:]).sum(0)
            ntr = trig.sum(0)
            ok = u.geo & (u.st_agent >= 0)
            ag = np.where(ok, u.st_agent, len(u.agent_ids))
            A = len(u.agent_ids)
            nA = np.bincount(ag, ntr, minlength=A + 1)[:A]
            kA = np.bincount(ag, hits, minlength=A + 1)[:A]
            eA = np.bincount(ag, ntr * pexp[d], minlength=A + 1)[:A]
            for a in range(A):
                if nA[a] == 0:
                    continue
                for direction in ("up", "down"):
                    templates.append(("neighbor_spill", f"d{d:g}|L{L}|{direction}", a, int(nA[a]), int(kA[a]), float(eA[a]),
                                      {"d": d, "L": L}, direction))
            # 판매점 단위 공간전이 (사건 많은 판매점)
            sel = np.where(ok & (pcnt >= MIN_EVENTS_PAIR) & (ntr > 0))[0]
            if len(sel):
                p = p_one_sided(hits[sel], ntr[sel], pexp[d][sel], True)
                q = bh_total(p, len(sel))
                best = {}
                for j, s in enumerate(sel):
                    a = int(u.st_agent[s])
                    if a not in best or p[j] < p[best[a]]:
                        best[a] = j
                keepj = set(np.where(q < DISC_Q)[0].tolist()) | (set(best.values()) if (full and d == NEIGH_KM[0] and L == 1) else set())
                for j in sorted(keepj):
                    s = int(sel[j])
                    cd = u.codes[s]
                    ag = u.agent_ids[u.st_agent[s]]
                    h = base_h("store_spill", "store", f"store_spill|{cd}|d{d:g}|L{L}", ag, source_store=cd, source_region=ag,
                               target_region=ag, lag=L, related_stores=[cd], related_regions=[ag], params={"d_km": d},
                               train_n=int(ntr[s]), train_k=int(hits[s]), train_expected=float(ntr[s] * pexp[d][s]),
                               train_p=float(p[j]), train_q=float(q[j]), discovery_significant=bool(q[j] < DISC_Q))
                    h["_s"], h["_d"], h["_lag"], h["_pexp"] = s, d, L, float(pexp[d][s])
                    st.add(h, c)
                stats["tests_store_spill"] = stats.get("tests_store_spill", 0) + len(sel)

    # 템플릿 검정 + 공유
    if templates:
        k = np.array([t[4] for t in templates], float)
        n = np.array([t[3] for t in templates], float)
        e = np.array([t[5] for t in templates], float)
        up = np.array([t[7] == "up" for t in templates])
        p = p_one_sided(k, n, e / np.maximum(n, 1), up)
        q = bh_total(p, len(p))
        stats["tests_templates"] = stats.get("tests_templates", 0) + len(p)
        groups = defaultdict(list)
        for j, t in enumerate(templates):
            groups[(t[0], t[1])].append(j)
        best_by_agent = {}
        for j, t in enumerate(templates):
            if t[0] == "neighbor_spill" and t[7] == "up":
                if t[2] not in best_by_agent or p[j] < p[best_by_agent[t[2]]]:
                    best_by_agent[t[2]] = j
        conflicts = 0
        for (kind, pk), js in groups.items():
            sig = [j for j in js if q[j] < DISC_Q]
            origin = min(sig, key=lambda j: (p[j], templates[j][2])) if sig else None
            origin_id = None
            opp = None
            if kind == "neighbor_spill":
                dd, LL, dr = pk.split("|")
                opp_key = (kind, f"{dd}|{LL}|{'down' if dr == 'up' else 'up'}")
                opp = [j for j in groups.get(opp_key, []) if q[j] < DISC_Q]
                if sig and opp:
                    conflicts += 1
            for j in sorted(js, key=lambda j: (p[j], templates[j][2])):
                t = templates[j]
                is_origin = origin is not None and j == origin
                keep = (q[j] < DISC_Q) or (origin is not None) or (full and (kind == "cycle_pooled" or best_by_agent.get(t[2]) == j))
                if not keep:
                    continue
                a = t[2]
                ag = u.agent_ids[a]
                if kind == "cycle_pooled":
                    key = f"cycle_pooled|{ag}"
                    params = {"stores": len(t[6])}
                else:
                    key = f"neighbor_spill|{ag}|{pk}"
                    params = {"d_km": t[6]["d"]}
                shared = origin is not None and not is_origin and not (q[j] < DISC_Q)
                h = base_h(kind, "agent_pooled", key, ag, t[7], target_region=ag, related_regions=[ag],
                           lag=(t[6]["L"] if kind == "neighbor_spill" else None), params=params,
                           train_n=int(t[3]), train_k=int(t[4]), train_expected=float(t[5]), train_p=float(p[j]),
                           train_q=float(q[j]), discovery_significant=bool(q[j] < DISC_Q))
                if shared:
                    oh = templates[origin]
                    okey = f"cycle_pooled|{u.agent_ids[oh[2]]}" if kind == "cycle_pooled" else f"neighbor_spill|{u.agent_ids[oh[2]]}|{pk}"
                    h["shared_from"] = hid(okey)
                    h["shared_by_agent"] = u.agent_ids[oh[2]]
                if kind == "neighbor_spill" and sig and opp:
                    h["evidence"]["conflict"] = {"opposite_direction_agents": [u.agent_ids[templates[o][2]] for o in opp][:10]}
                if is_origin:
                    h["shared_to_count"] = len(js) - 1
                h["_agent"] = a
                if kind == "cycle_pooled":
                    h["_members"] = t[6]
                    h["_p0s"] = {s: float(ps[s]) for s, _, _ in t[6]}
                else:
                    h["_d"], h["_lag"] = t[6]["d"], t[6]["L"]
                    mem = u.members[a]
                    mem = mem[u.geo[mem]]
                    h["_mem"], h["_pexp"] = mem, pexp[t[6]["d"]][mem]
                st.add(h, c)
        stats["template_conflicts"] = stats.get("template_conflicts", 0) + conflicts

    # 5) 지역 집중·감소·미출현 (규칙 기반 발견, 이후 TREND_HORIZON 회차 검증)
    v = u.valid[:ci + 1]
    X = u.RF[:ci + 1][v]
    if full and len(X) > 200:
        rec, pri = X[-100:].mean(0), X[:-100].mean(0)
        pooled_p = X.mean(0)
        se = np.sqrt(np.maximum(pooled_p * (1 - pooled_p), 1e-9) * (1 / 100 + 1 / max(len(X) - 100, 1)))
        z = (rec - pri) / se
        last = np.array([np.where(X[:, j])[0][-1] if X[:, j].any() else -1 for j in range(u.U)])
        dormant = len(X) - 1 - last
        pz = norm.sf(np.abs(z))
        for j in range(u.U):
            R_ = u.reg_ids[j]
            rules = []
            if z[j] >= 2:
                rules.append(("region_trend_up", "up", float(pri[j]), float(pz[j])))
            if z[j] <= -2:
                rules.append(("region_trend_down", "down", float(pri[j]), float(pz[j])))
            if pr[j] > 0 and dormant[j] >= max(3 / pr[j], 30):
                rules.append(("region_dormant", "up", float(pr[j]), float((1 - pr[j]) ** dormant[j])))
            for kind, direction, base, pp in rules:
                h = base_h(kind, "region", f"{kind}|{R_}|c{c}", R_, direction, target_region=R_, related_regions=[R_],
                           params={"z": float(z[j]), "recent100": float(rec[j]), "prior": float(pri[j]),
                                   "dormant": int(dormant[j]), "horizon": TREND_HORIZON},
                           train_p=pp, discovery_significant=pp < 0.05 / u.U)
                h["_B"], h["_p0"], h["_c_row"] = j, base, ci
                st.add(h, c)

    # 6) 복합 (판매점 주기 ∧ 같은 판매점을 겨냥한 선행 가설) — 학습 구간 동시 충족 검정
    new = st.H[n_before:] if full else []
    cyc_by_store = {h["_s"]: h for h in new if h["kind"] == "store_cycle"}
    for h2 in new:
        if h2["kind"] not in ("store_lead", "region_store_lead"):
            continue
        b = h2["_b"]
        h1 = cyc_by_store.get(b)
        if h1 is None:
            continue
        f1 = fire_cycle_series(u, b, h1["_lo"], h1["_hi"], ci)
        f2 = fire_lead_series(u, h2, ci)
        both = f1 & f2 & u.valid[:ci + 1]
        n = int(both.sum())
        if n == 0:
            continue
        k = int(u.E[:ci + 1, b][both].sum())
        p0 = float(ps[b])
        p = float(binom.sf(k - 1, n, max(p0, 1e-12)))
        cd = u.codes[b]
        h = base_h("composite", "composite", f"composite|{h1['canonical_key']}|{h2['canonical_key']}", h2["agent_id"],
                   target_store=cd, target_region=h2["target_region"], related_stores=sorted(set(h2["related_stores"])),
                   related_regions=h2["related_regions"], lag=h2["lag"],
                   params={"children": [hid(h1["canonical_key"]), hid(h2["canonical_key"])]},
                   train_n=n, train_k=k, train_expected=n * p0, train_p=p, discovery_significant=False)
        h["_b"], h["_c1"], h["_c2"], h["_p0"] = b, h1["idx"], h2["idx"], p0
        st.add(h, c)

    log(f"[discover] c={c}: +{len(st.H) - n_before} hypotheses (total {len(st.H)}) {time.time() - t0:.0f}s")
    return relations


def fire_cycle_series(u, s, lo, hi, ci):
    ev = np.where(u.E[:ci + 1, s] * u.valid[:ci + 1])[0]
    t = np.arange(ci + 1)
    out = np.zeros(ci + 1, bool)
    if len(ev) == 0:
        return out
    pos = np.searchsorted(ev, t, side="left") - 1
    okp = pos >= 0
    d = np.where(okp, t - ev[np.maximum(pos, 0)], -1)
    return okp & (d >= lo) & (d <= hi)


def fire_lead_series(u, h, ci):
    L = h["_lag"]
    out = np.zeros(ci + 1, bool)
    if h["kind"] == "store_lead":
        src = u.E[:ci + 1 - L, h["_a"]] * u.valid[:ci + 1 - L]
    else:
        src = u.RF[:ci + 1 - L, h["_A"]] * u.valid[:ci + 1 - L]
    out[L:] = src > 0
    return out


# ── 순차 학습 엔진 ────────────────────────────────────────────────
class Engine:
    def __init__(self, u):
        self.u = u
        self.st = Store()
        self.H = 0
        self.n = self.k = self.e = None
        self.status = np.zeros(0, int)
        self.koff = np.zeros(0)
        self.eoff = np.zeros(0)
        self.test_ratio = np.zeros(0)
        self.test_p = np.zeros(0)
        self.test_q = np.zeros(0)
        self.disc_row = np.zeros(0, int)
        S, U = u.S, u.U
        self.params = dict(TUNED)
        self.gamma = 0.5 ** (1 / self.params["store_half_life"])
        self.gammaC = 0.5 ** (1 / self.params["central_half_life"])
        self.beta = self.params["central_beta"]
        self.kw = np.zeros(S)
        self.nw = 0.0
        self.kR = np.zeros(U)         # 지역 1등 회차 (감쇠) — 순방향 귀무 비율
        self.lam0 = np.zeros(S)
        self.kF = np.zeros(U)        # 지역 1등 판매점 수 (감쇠)
        self.kF_cum = np.zeros(U)
        self.lam_w = 0.0              # 회차당 지역 1등 판매점 수 (감쇠 평균)
        self.lam_n = 0.0
        self.phiF = 0.0
        self.phiE = 0.0
        self.last_ev = np.full(S, -10 ** 6)
        self.events = []              # 상태 변화
        self.relations = {}
        self.stats = {}
        self.backtest = {}            # target_round → per-agent results
        self.central = {}
        self.central_eval = {}
        self.multi = [0, 0, 0.0, 0, 0, 0.0, 0, 0, 0.0]   # (≥2 동시 충족) n,k,exp / (1개) n,k,exp

    # 가설 배열 재구성 (발견 직후)
    def rebuild(self):
        H = len(self.st.H)
        grow = H - self.H
        if grow > 0:
            self.n = np.concatenate([self.n if self.n is not None else np.zeros(0), np.zeros(grow)])
            self.k = np.concatenate([self.k if self.k is not None else np.zeros(0), np.zeros(grow)])
            self.e = np.concatenate([self.e if self.e is not None else np.zeros(0), np.zeros(grow)])
            self.koff = np.concatenate([self.koff, np.zeros(grow)])
            self.eoff = np.concatenate([self.eoff, np.zeros(grow)])
            self.test_ratio = np.concatenate([self.test_ratio, np.ones(grow)])
            self.status = np.concatenate([self.status, np.zeros(grow, int)])
            self.test_p = np.concatenate([self.test_p, np.ones(grow)])
            self.test_q = np.concatenate([self.test_q, np.ones(grow)])
            self.disc_row = np.concatenate([self.disc_row, np.array([self.u.row(h["discovered_round"]) for h in self.st.H[self.H:]], int)])
        self.H = H
        hs = self.st.H
        self.pred = np.array([h["predictive"] for h in hs], bool)
        self.boost = np.array([h["kind"] in BOOST_KINDS for h in hs], bool)
        self.up = np.array([h["direction"] == "up" for h in hs], bool)
        self.is_comp = np.array([h["kind"] == "composite" for h in hs], bool)
        g = defaultdict(list)
        for h in hs:
            g[h["kind"]].append(h["idx"])
        self.g = {}
        for kind, idx in g.items():
            idx = np.array(idx)
            d = {"idx": idx}
            hh = [hs[i] for i in idx]
            if kind in ("store_lead", "store_cowin"):
                d.update(a=np.array([h["_a"] for h in hh]), b=np.array([h["_b"] for h in hh]),
                         L=np.array([h["_lag"] for h in hh]), p0=np.array([h["_p0"] for h in hh]))
            elif kind == "region_store_lead":
                d.update(A=np.array([h["_A"] for h in hh]), b=np.array([h["_b"] for h in hh]),
                         L=np.array([h["_lag"] for h in hh]), p0=np.array([h["_p0"] for h in hh]))
            elif kind in ("region_lead", "self_repeat", "region_cowin"):
                d.update(A=np.array([h["_A"] for h in hh]), B=np.array([h["_B"] for h in hh]),
                         L=np.array([h["_lag"] for h in hh]), p0=np.array([h["_p0"] for h in hh]))
            elif kind == "store_cycle":
                d.update(s=np.array([h["_s"] for h in hh]), lo=np.array([h["_lo"] for h in hh]),
                         hi=np.array([h["_hi"] for h in hh]), p0=np.array([h["_p0"] for h in hh]))
            elif kind == "store_spill":
                d.update(s=np.array([h["_s"] for h in hh]), dk=np.array([h["_d"] for h in hh]),
                         L=np.array([h["_lag"] for h in hh]), pexp=np.array([h["_pexp"] for h in hh]))
            elif kind in ("region_trend_up", "region_trend_down", "region_dormant"):
                d.update(B=np.array([h["_B"] for h in hh]), p0=np.array([h["_p0"] for h in hh]),
                         c_row=np.array([h["_c_row"] for h in hh]))
            elif kind == "composite":
                d.update(b=np.array([h["_b"] for h in hh]), c1=np.array([h["_c1"] for h in hh]),
                         c2=np.array([h["_c2"] for h in hh]), p0=np.array([h["_p0"] for h in hh]))
            elif kind == "cycle_pooled":
                s_, lo_, hi_, own_, p0_ = [], [], [], [], []
                for h in hh:
                    for (s, lo, hi) in h["_members"]:
                        s_.append(s); lo_.append(lo); hi_.append(hi); own_.append(h["idx"]); p0_.append(h["_p0s"][s])
                d.update(s=np.array(s_, int), lo=np.array(lo_, int), hi=np.array(hi_, int), own=np.array(own_, int),
                         p0=np.array(p0_))
            elif kind == "neighbor_spill":
                pass                         # 지방장별 루프
            self.g[kind] = d
        self.spill = [(h["idx"], h["_d"], h["_lag"], h["_mem"], h["_pexp"]) for h in hs if h["kind"] == "neighbor_spill"]

    # 회차 행 ti 의 가설 발화 (ti-1 이하 사건만 사용; 동시 당첨은 ti 사건 필요)
    def fire(self, ti, with_cowin):
        u = self.u
        H = self.H
        fire = np.zeros(H, bool)
        trials = np.zeros(H)          # 발화 시행 수 (풀링 가설은 여러 개)
        expv = np.zeros(H)
        targets = defaultdict(list)    # hyp idx → 판매점 배열 (또는 지역 표시)
        reg_targets = {}               # hyp idx → 지역 idx
        active = self.disc_row < ti
        lam0, reg0, spill0 = self.null_rates()
        self.lam0 = lam0
        self._null = (lam0, reg0, spill0)
        vprev = lambda r: (r >= 0) & u.valid[np.clip(r, 0, u.R - 1)]
        for kind, d in self.g.items():
            idx = d["idx"]
            if kind in ("store_lead", "region_store_lead", "store_cowin"):
                if kind == "store_cowin" and not with_cowin:
                    continue
                r = ti - d["L"]
                ok = vprev(r) & (r < u.R)
                rr = np.clip(r, 0, u.R - 1)
                src = u.E[rr, d["a"]] if kind != "region_store_lead" else u.RF[rr, d["A"]]
                f = ok & (src == 1) & active[idx]
                fire[idx] = f
                trials[idx] = f
                expv[idx] = f * lam0[d["b"]]
                for j in np.where(f)[0]:
                    targets[idx[j]] = np.array([d["b"][j]])
            elif kind in ("region_lead", "self_repeat", "region_cowin"):
                if kind == "region_cowin" and not with_cowin:
                    continue
                r = ti - d["L"]
                ok = vprev(r) & (r < u.R)
                rr = np.clip(r, 0, u.R - 1)
                f = ok & (u.RF[rr, d["A"]] == 1) & active[idx]
                fire[idx] = f
                trials[idx] = f
                expv[idx] = f * reg0[d["B"]]
                for j in np.where(f)[0]:
                    reg_targets[idx[j]] = d["B"][j]
            elif kind == "store_cycle":
                dd = ti - self.last_ev[d["s"]]
                f = (dd >= d["lo"]) & (dd <= d["hi"]) & active[idx]
                fire[idx] = f
                trials[idx] = f
                expv[idx] = f * lam0[d["s"]]
                for j in np.where(f)[0]:
                    targets[idx[j]] = np.array([d["s"][j]])
            elif kind == "store_spill":
                r = ti - d["L"]
                ok = vprev(r) & (r < u.R)
                rr = np.clip(r, 0, u.R - 1)
                f = ok & (u.E[rr, d["s"]] == 1) & active[idx]
                fire[idx] = f
                trials[idx] = f
                expv[idx] = f * np.array([spill0[dk][s] for dk, s in zip(d["dk"], d["s"])])
                for j in np.where(f)[0]:
                    targets[idx[j]] = u.nb[d["dk"][j]][d["s"][j]].indices
            elif kind in ("region_trend_up", "region_trend_down", "region_dormant"):
                f = active[idx] & (ti - d["c_row"] <= TREND_HORIZON)
                fire[idx] = f
                trials[idx] = f
                expv[idx] = f * d["p0"]
                for j in np.where(f)[0]:
                    reg_targets[idx[j]] = d["B"][j]
            elif kind == "cycle_pooled":
                own_active = active[d["own"]]
                dd = ti - self.last_ev[d["s"]]
                f = (dd >= d["lo"]) & (dd <= d["hi"]) & own_active
                np.add.at(trials, d["own"], f.astype(float))
                np.add.at(expv, d["own"], f * lam0[d["s"]])
                fire[np.unique(d["own"][f])] = True
                for o in np.unique(d["own"][f]):
                    targets[o] = d["s"][f & (d["own"] == o)]
        for (i, dk, L, mem, pexp) in self.spill:
            if not active[i]:
                continue
            r = ti - L
            if r < 0 or r >= u.R or not u.valid[r]:
                continue
            trig = u.E[r, mem] == 1
            if trig.any():
                fire[i] = True
                trials[i] = trig.sum()
                expv[i] = spill0[dk][mem[trig]].sum()
                targets[i] = np.unique(np.concatenate([u.nb[dk][s].indices for s in mem[trig]]))
        if "composite" in self.g:
            d = self.g["composite"]
            f = fire[d["c1"]] & fire[d["c2"]] & active[d["idx"]]
            fire[d["idx"]] = f
            trials[d["idx"]] = f
            expv[d["idx"]] = f * lam0[d["b"]]
            for j in np.where(f)[0]:
                targets[d["idx"][j]] = np.array([d["b"][j]])
        return fire, trials, expv, targets, reg_targets

    def outcomes(self, ti, fire):
        """회차 ti 실제 결과: 발화 시 적중 k, 같은 회차 비발화 대조군 적중 koff·기대 eoff"""
        u = self.u
        H = self.H
        k = np.zeros(H)
        koff = np.zeros(H)
        eoff = np.zeros(H)
        lam0, reg0, spill0 = self._null
        active = self.disc_row < ti
        for kind, d in self.g.items():
            idx = d["idx"]
            f = fire[idx]
            off = active[idx] & ~f
            if kind in ("store_lead", "region_store_lead", "store_cowin", "composite"):
                ev = u.E[ti, d["b"]] == 1
                k[idx], koff[idx], eoff[idx] = f & ev, off & ev, off * lam0[d["b"]]
            elif kind in ("region_lead", "self_repeat", "region_cowin"):
                ev = u.RF[ti, d["B"]] == 1
                k[idx], koff[idx], eoff[idx] = f & ev, off & ev, off * reg0[d["B"]]
            elif kind in ("region_trend_up", "region_trend_down", "region_dormant"):
                k[idx] = f & (u.RF[ti, d["B"]] == 1)            # 시간 조건 가설 → 대조군 없음 (장기 비율 대비)
            elif kind == "store_cycle":
                ev = u.E[ti, d["s"]] == 1
                k[idx], koff[idx], eoff[idx] = f & ev, off & ev, off * lam0[d["s"]]
            elif kind == "store_spill":
                ev = np.array([u.NE[dk][ti, s] for dk, s in zip(d["dk"], d["s"])]) == 1
                sp = np.array([spill0[dk][s] for dk, s in zip(d["dk"], d["s"])])
                k[idx], koff[idx], eoff[idx] = f & ev, off & ev, off * sp
            elif kind == "cycle_pooled":
                own_active = active[d["own"]]
                dd = ti - self.last_ev[d["s"]]
                inw = (dd >= d["lo"]) & (dd <= d["hi"])
                ev = u.E[ti, d["s"]] == 1
                np.add.at(k, d["own"], (inw & own_active & ev).astype(float))
                offm = ~inw & own_active
                np.add.at(koff, d["own"], (offm & ev).astype(float))
                np.add.at(eoff, d["own"], offm * lam0[d["s"]])
        for (i, dk, L, mem, pexp) in self.spill:
            if not active[i]:
                continue
            r = ti - L
            if r < 0 or not u.valid[r]:
                continue
            trig = u.E[r, mem] == 1
            ne = u.NE[dk][ti, mem] == 1
            k[i] = float((ne & trig).sum())
            koff[i] = float((ne & ~trig).sum())
            eoff[i] = float(spill0[dk][mem[~trig]].sum())
        return k, koff, eoff

    def factors(self, fire, targets, reg_targets, live_mask, ratio):
        """판매점·지역 보정 배수 (가설 비율의 곱, [1/CAP, CAP])"""
        u = self.u
        logf = np.zeros(u.S)
        logr = np.zeros(u.U)
        cnt = np.zeros(u.S, int)
        for i in np.where(fire & live_mask & self.boost)[0]:
            lf = math.log(min(max(ratio[i], 1 / FACTOR_CAP), FACTOR_CAP))
            if i in reg_targets:
                logr[reg_targets[i]] += lf
            elif i in targets:
                logf[targets[i]] += lf
                cnt[targets[i]] += 1
        regf = np.exp(np.clip(logr, -math.log(FACTOR_CAP), math.log(FACTOR_CAP)))
        st_reg_f = np.where(u.st_reg >= 0, regf[np.clip(u.st_reg, 0, u.U - 1)], 1.0)
        f = np.exp(np.clip(logf + np.log(st_reg_f), -math.log(FACTOR_CAP), math.log(FACTOR_CAP)))
        return f, regf, cnt

    def test_stats(self):
        """대조군이 있으면 조건부 이항검정: k ~ Bin(k+koff, e/(e+eoff)) — 판매량 추세 등 공통 편향 상쇄"""
        n, k, e, koff, eoff = self.n, self.k, self.e, self.koff, self.eoff
        H = self.H
        p = np.ones(H)
        has = n > 0
        cond = has & (eoff > 0)
        plain = has & ~cond
        if cond.any():
            p[cond] = p_one_sided(k[cond], k[cond] + koff[cond], e[cond] / (e[cond] + eoff[cond]), self.up[cond])
        if plain.any():
            p[plain] = p_one_sided(k[plain], n[plain], e[plain] / np.maximum(n[plain], 1), self.up[plain])
        rel_on = (k + 0.5) / (e + 0.5)
        rel_off = np.where(eoff > 0, (koff + 0.5) / (eoff + 0.5), 1.0)
        ratio = rel_on / rel_off
        same = np.where(self.up, ratio > 1, ratio < 1)
        decidable = (n >= MIN_TRIALS) & (e >= MIN_EXPECTED) & ((eoff == 0) | (eoff >= MIN_EXPECTED))
        return p, ratio, same, decidable

    def update_status(self, ti_done):
        """ti_done 회차까지 반영한 상태 (판정 가능 가설 전체 BH)"""
        H = self.H
        n, k, e = self.n, self.k, self.e
        p, ratio, same, decidable = self.test_stats()
        decidable = decidable & (self.disc_row < ti_done + 1)
        q = np.ones(H)
        for fam in (True, False):
            m = decidable & (self.pred == fam)
            if m.any():
                q[m] = bh_total(p[m], m.sum())
        new = np.full(H, S_RES)
        new[n == 0] = S_DISC
        dec_pass = decidable & same & (q < PASS_Q)
        new[decidable & same] = S_WEAK
        new[dec_pass] = np.where(self.is_comp[dec_pass], S_COMB, S_PASS)
        new[decidable & ~same] = S_REJ
        new[self.disc_row > ti_done] = S_DISC
        changed = np.where((new != self.status) & (self.disc_row <= ti_done))[0]
        rnd = int(self.u.rounds[ti_done])
        for i in changed:
            self.events.append({"hypothesis_id": self.st.H[i]["hypothesis_id"], "model_version": MODEL, "round": rnd,
                                "status_from": STATUS[self.status[i]], "status_to": STATUS[new[i]], "test_n": int(n[i]),
                                "test_k": int(k[i]), "test_expected": float(e[i]), "test_p": float(p[i])})
        self.status = new
        self.test_p, self.test_q, self.test_ratio = p, q, ratio

    def lam(self):
        """감쇠 가중 판매점 사건률 (지방장 평균으로 경험적 베이즈 축소)"""
        u = self.u
        nw = max(self.nw, 1e-9)
        x = self.kw / nw
        A = len(u.agent_ids)
        ag = np.where(u.st_agent >= 0, u.st_agent, A)
        cnts = np.bincount(ag, minlength=A + 1).astype(float)
        mr = np.bincount(ag, x, minlength=A + 1) / np.maximum(cnts, 1)
        m = mr[ag]
        tau2 = max(float(np.mean((x - m) ** 2) - np.mean(m / nw)), 1e-12)
        alpha = float(np.mean(m)) / tau2
        return (self.kw + alpha * m) / (nw + alpha), m

    def null_rates(self):
        """순방향 검정 귀무 비율: 회차 직전까지의 감쇠 가중 실제 비율(약한 사전) — 판매량 변화 등 비정상성 보정"""
        u = self.u
        nw = max(self.nw, 1e-9)
        A = len(u.agent_ids)
        ag = np.where(u.st_agent >= 0, u.st_agent, A)
        cnts = np.bincount(ag, minlength=A + 1).astype(float)
        m = (np.bincount(ag, self.kw / nw, minlength=A + 1) / np.maximum(cnts, 1))[ag]
        lam0 = (self.kw + NULL_PRIOR * m) / (nw + NULL_PRIOR)
        r_m = self.kR.sum() / max(nw * u.U, 1e-9)
        reg0 = (self.kR + NULL_PRIOR * r_m) / (nw + NULL_PRIOR)
        spill = {d: 1 - np.exp(u.nb[d] @ np.log1p(-np.clip(lam0, 0, 0.999))) for d in NEIGH_KM}
        return lam0, reg0, spill

    def central_p(self, regf):
        u = self.u
        beta = self.beta
        lam = self.lam_w / max(self.lam_n, 1e-9)
        q = (self.kF + beta * u.share) / (self.kF.sum() + beta)
        p_model = 1 - np.exp(-lam * q * regf)
        p_m0 = 1 - np.exp(-lam * u.share)
        q1 = (self.kF_cum + beta * u.share) / (self.kF_cum.sum() + beta)
        p_m1 = 1 - np.exp(-lam * q1)
        return np.clip(p_model, 1e-6, 1 - 1e-6), np.clip(p_m0, 1e-6, 1 - 1e-6), np.clip(p_m1, 1e-6, 1 - 1e-6)

    def ratios(self):
        live_ratio = self.test_ratio
        tk = np.array([h["train_k"] if h["train_k"] is not None else 0 for h in self.st.H], float)
        te = np.array([h["train_expected"] if h["train_expected"] is not None else 0 for h in self.st.H], float)
        # 규칙 기반 지역 가설: 최근 100회 비율 / 이전 비율 (미출현은 근거 배수 없음 → 1)
        trend = np.array([(h["params"]["recent100"] + 0.01) / (h["params"]["prior"] + 0.01)
                          if h["kind"] in ("region_trend_up", "region_trend_down") else
                          (1.0 if h["kind"] == "region_dormant" else np.nan) for h in self.st.H])
        explore_ratio = np.where(np.isnan(trend), (tk + 1) / (te + 1), trend)
        return live_ratio, explore_ratio

    def deliver(self, ti, fire, targets, reg_targets):
        """목표 회차 ti 납품 (ti-1 까지의 정보). 반환: dict"""
        u = self.u
        lam, mreg = self.lam()
        live_ratio, explore_ratio = self.ratios()
        live_mask = np.isin(self.status, (S_PASS, S_COMB))
        explore_mask = np.isin(self.status, (S_DISC, S_RES, S_WEAK, S_PASS, S_COMB))
        f_live, regf_live, n_live = self.factors(fire, targets, reg_targets, live_mask, live_ratio)
        f_exp, _, n_exp = self.factors(fire, targets, reg_targets, explore_mask, explore_ratio)
        s_live, s_exp = lam * f_live, lam * f_exp
        A = len(u.agent_ids)

        def topk(score):
            out = []
            order = np.lexsort((np.arange(u.S), -score, u.st_agent))
            ag_sorted = u.st_agent[order]
            starts = np.searchsorted(ag_sorted, np.arange(A))
            ends = np.searchsorted(ag_sorted, np.arange(A), side="right")
            for a in range(A):
                out.append(order[starts[a]:min(ends[a], starts[a] + K_DELIVER)])
            return out, order, starts, ends

        live, order, starts, ends = topk(s_live)
        expl = topk(s_exp)[0]
        hist = topk(lam)[0]
        phi = self.phiF / max(self.phiE, 1e-9) if self.phiE > 0 else 0.145
        p_model, p_m0, p_m1 = self.central_p(regf_live)
        cand = np.concatenate(live)
        cstore = cand[np.argsort(-s_live[cand], kind="stable")][:CENTRAL_STORES]
        hcand = np.concatenate(hist)
        hstore = hcand[np.argsort(-lam[hcand], kind="stable")][:CENTRAL_STORES]
        return dict(lam=lam, mreg=mreg, f_live=f_live, f_exp=f_exp, s_live=s_live, s_exp=s_exp, live=live, expl=expl, hist=hist,
                    order=order, starts=starts, ends=ends, phi=phi, p_model=p_model, p_m0=p_m0, p_m1=p_m1, regf=regf_live,
                    cstore=cstore, hstore=hstore, n_live_hyp=int((fire & live_mask & self.boost).sum()), n_live=n_live, n_exp=n_exp,
                    live_mask=live_mask)

    def evaluate(self, ti, dv):
        u = self.u
        A = len(u.agent_ids)
        Et, Ft = u.E[ti], u.F[ti]
        ev = np.bincount(np.where(u.st_agent >= 0, u.st_agent, A), Et, minlength=A + 1)[:A]
        fv = np.bincount(np.where(u.st_agent >= 0, u.st_agent, A), Ft, minlength=A + 1)[:A]
        per = []
        for a in range(A):
            n_st = len(u.members[a])
            dl, ex, hs = dv["live"][a], dv["expl"][a], dv["hist"][a]
            per.append({"agent": a, "delivered": dl, "explored": ex, "history_only": hs,
                        "hits_first": int(Ft[dl].sum()), "hits_any": int(Et[dl].sum()), "explore_hits_any": int(Et[ex].sum()),
                        "history_hits_any": int(Et[hs].sum()), "region_events": int(ev[a]), "region_first": int(fv[a]),
                        "expected_uniform": float(min(K_DELIVER, n_st) / max(n_st, 1) * ev[a]), "n_stores": n_st})
        rf = u.RF[ti].astype(float)

        def ll(p):
            return float(-np.mean(rf * np.log(p) + (1 - rf) * np.log(1 - p)))
        focus = np.argsort(-dv["p_model"], kind="stable")[:CENTRAL_REGIONS]
        focus0 = np.argsort(-dv["p_m0"], kind="stable")[:CENTRAL_REGIONS]
        cm = {"logloss_model": ll(dv["p_model"]), "logloss_m0": ll(dv["p_m0"]), "logloss_m1": ll(dv["p_m1"]),
              "region_hits": int(rf[focus].sum()), "region_expected": float(dv["p_model"][focus].sum()),
              "region_hits_m0": int(rf[focus0].sum()), "regions_with_first": int(rf.sum()),
              "store_hits_any": int(Et[dv["cstore"]].sum()), "store_hits_first": int(Ft[dv["cstore"]].sum()),
              "store_hits_any_history": int(Et[dv["hstore"]].sum()),
              "store_expected_uniform": float(CENTRAL_STORES / u.S * Et.sum()), "events": int(Et.sum())}
        return per, cm

    def advance(self, ti):
        """회차 행 ti 결과를 상태에 반영 (감쇠 통계·마지막 사건)"""
        u = self.u
        if u.valid[ti]:
            self.kw = self.kw * self.gamma + u.E[ti]
            self.nw = self.nw * self.gamma + 1
            self.kR = self.kR * self.gamma + u.RF[ti]
            self.kF = self.kF * self.gammaC + u.RFc[ti]
            self.kF_cum = self.kF_cum + u.RFc[ti]
            self.lam_w = self.lam_w * self.gammaC + u.RFc[ti].sum()
            self.lam_n = self.lam_n * self.gammaC + 1
            self.phiF = self.phiF * self.gamma + u.F[ti].sum()
            self.phiE = self.phiE * self.gamma + u.E[ti].sum()
            hit = np.where(u.E[ti] == 1)[0]
            self.last_ev[hit] = ti


TUNED = {"store_half_life": HALF_LIFE, "central_half_life": HALF_LIFE, "central_beta": 50.0}


def tune(u):
    """감쇠 반감기·중앙 사전 강도를 TUNE_FROM~TUNE_TO(학습 시작 전) 순방향 성능으로 선택"""
    lo, hi = u.row(TUNE_FROM), u.row(TUNE_TO)
    A = len(u.agent_ids)
    ag = np.where(u.st_agent >= 0, u.st_agent, A)
    cnts = np.bincount(ag, minlength=A + 1).astype(float)
    store_score, central_score = {}, {}
    n_eval = 0
    for hl in HL_GRID:
        g = 0.5 ** (1 / hl)
        kw = np.zeros(u.S)
        nw = 0.0
        kF = np.zeros(u.U)
        lw = ln = 0.0
        hits = 0
        n_eval = 0
        ll = {b: 0.0 for b in BETA_GRID}
        for ti in range(0, hi + 1):
            if ti >= lo and u.valid[ti] and nw > 0:
                n_eval += 1
                x = kw / nw
                m = (np.bincount(ag, x, minlength=A + 1) / np.maximum(cnts, 1))[ag]
                tau2 = max(float(np.mean((x - m) ** 2) - np.mean(m / nw)), 1e-12)
                alpha = float(np.mean(m)) / tau2
                lam = (kw + alpha * m) / (nw + alpha)
                order = np.lexsort((np.arange(u.S), -lam, u.st_agent))
                srt = u.st_agent[order]
                starts = np.searchsorted(srt, np.arange(A))
                ends = np.searchsorted(srt, np.arange(A), side="right")
                take = np.concatenate([order[s:min(e, s + K_DELIVER)] for s, e in zip(starts, ends)])
                hits += int(u.E[ti, take].sum())
                rf = u.RF[ti]
                lam_c = lw / max(ln, 1e-9)
                for b in BETA_GRID:
                    q = (kF + b * u.share) / (kF.sum() + b)
                    p = np.clip(1 - np.exp(-lam_c * q), 1e-6, 1 - 1e-6)
                    ll[b] += float(-np.mean(rf * np.log(p) + (1 - rf) * np.log(1 - p)))
            if u.valid[ti]:
                kw = kw * g + u.E[ti]
                nw = nw * g + 1
                kF = kF * g + u.RFc[ti]
                lw = lw * g + u.RFc[ti].sum()
                ln = ln * g + 1
        store_score[hl] = hits
        for b in BETA_GRID:
            central_score[(hl, b)] = ll[b]
    best_hl = max(HL_GRID, key=lambda h: (store_score[h], h))
    best_c = min(central_score, key=lambda k: (central_score[k], -k[0], -k[1]))
    return {"store_half_life": best_hl, "central_half_life": best_c[0], "central_beta": best_c[1],
            "tune_rounds": [TUNE_FROM, TUNE_TO],
            "store_hits_by_half_life": {f"{k:g}": v for k, v in store_score.items()},
            "central_logloss_by_param": {f"{k[0]:g}|{k[1]:g}": v / max(n_eval, 1) for k, v in central_score.items()}}


def run(raw, latest, progress=True):
    t0 = time.time()
    u = Universe(raw, latest)
    tuned = tune(u)
    TUNED.update({k: tuned[k] for k in ("store_half_life", "central_half_life", "central_beta")})
    log(f"[tune {TUNE_FROM}~{TUNE_TO}] store HL {tuned['store_half_life']:g} · central HL {tuned['central_half_life']:g} "
        f"β {tuned['central_beta']:g} ({time.time() - t0:.0f}s)")
    log(f"[prep] stores {u.S} agents {len(u.agent_ids)} regions {u.U} rounds {u.r0}~{latest} "
        f"missing {len(u.missing_rounds)} unknown(1등 {u.unknown_first}, 2등 {u.unknown_second}) unparsed {u.unparsed} "
        f"({time.time() - t0:.0f}s)")
    eng = Engine(u)
    start_ti = u.row(LEARN_START)
    # 기준선: 999회까지 감쇠 통계
    for ti in range(0, start_ti):
        eng.advance(ti)
    checkpoints = sorted({c for c in range(CP_FIRST, latest, CP_STEP)} | {latest})
    relations_by_cp = {}
    for ti in range(start_ti, u.R + 1):          # ti == R 은 실전 목표 회차 (latest+1)
        prev_round = int(u.rounds[ti - 1])
        if prev_round in checkpoints:
            ps, pcnt = store_rates(u, ti - 1)
            pr = region_rates(u, ti - 1)
            relations_by_cp[prev_round] = discover(u, eng.st, ti - 1, ps, pcnt, pr, eng.stats)
            eng.rebuild()
            eng.update_status(ti - 1)
        live_target = ti == u.R
        fire, trials, expv, targets, reg_targets = eng.fire(ti, with_cowin=not live_target)
        dv = eng.deliver(ti, fire & eng.pred, targets, reg_targets)
        target_round = int(u.rounds[ti]) if not live_target else latest + 1
        if live_target:
            eng.live = (target_round, dv, fire, targets, reg_targets)
            break
        per, cm = eng.evaluate(ti, dv)
        eng.backtest[target_round] = per
        eng.central[target_round] = dv_central(u, dv, cm)
        eng.central_eval[target_round] = cm
        # 다중 조건 동시 충족 분석 (탐색 가설 기준)
        nh = dv["n_exp"]
        if u.valid[ti]:
            for grp, m_ in ((0, nh >= 2), (3, nh == 1), (6, nh == 0)):
                eng.multi[grp] += int(m_.sum())
                eng.multi[grp + 1] += int(u.E[ti][m_].sum())
                eng.multi[grp + 2] += float(eng.lam0[m_].sum())
            k, koff, eoff = eng.outcomes(ti, fire)
            eng.n += trials
            eng.k += k
            eng.e += expv
            eng.koff += koff
            eng.eoff += eoff
        eng.advance(ti)
        eng.update_status(ti)
        if progress and (target_round % 25 == 0):
            log(f"  [round {target_round}] H={eng.H} passed={(np.isin(eng.status, (S_PASS, S_COMB))).sum()} ({time.time() - t0:.0f}s)")
    eng.relations_by_cp = relations_by_cp
    eng.tuned = tuned
    eng.elapsed = time.time() - t0
    return u, eng


def dv_central(u, dv, cm=None, all_regions=False):
    order = np.argsort(-dv["p_model"], kind="stable")
    regions = order if all_regions else order[:20]
    focus = [{"region_id": u.reg_ids[j], "p": float(dv["p_model"][j]), "base": float(dv["p_m0"][j]),
              "ratio": float(dv["p_model"][j] / dv["p_m0"][j]), "factor": float(dv["regf"][j]), "rank": int(r + 1)}
             for r, j in enumerate(regions)]
    rank_in_agent = {}
    for a, lst in enumerate(dv["live"]):
        for r, s in enumerate(lst):
            rank_in_agent[int(s)] = r + 1
    stores = [{"store_code": u.codes[s], "agent_id": u.agent_ids[u.st_agent[s]], "name": u.name[s],
               "score": float(dv["s_live"][s]), "p_first": float(dv["s_live"][s] * dv["phi"]),
               "agent_rank": rank_in_agent.get(int(s)), "live_factor": float(dv["f_live"][s]),
               "verification": "검증 가설 반영" if dv["f_live"][s] != 1 else "이력 기반(검증 가설 없음)"} for s in dv["cstore"]]
    return {"focus_regions": focus, "store_top": stores, "live_hypotheses": dv["n_live_hyp"],
            "agents_delivered": sum(1 for x in dv["live"] if len(x))}


# ── 결과 정리 ─────────────────────────────────────────────────────
def summarize_h(u, eng, h):
    i = h["idx"]
    return {"hypothesis_id": h["hypothesis_id"], "kind": h["kind"], "agent_id": h["agent_id"], "summary": h_summary(u, h),
            "status": STATUS[eng.status[i]], "test_k": int(eng.k[i]), "test_expected": float(eng.e[i]),
            "test_p": float(eng.test_p[i]), "related_stores": h["related_stores"], "related_regions": h["related_regions"]}


def h_summary(u, h):
    nm = lambda c: u.name[u.cidx[c]] if c in u.cidx else c
    k = h["kind"]
    lag = f" +{h['lag']}회" if h.get("lag") else ""
    if k == "store_lead":
        return f"{nm(h['source_store'])}({h['source_region']}) 당첨{lag} 후 {nm(h['target_store'])}({h['target_region']}) 당첨 증가"
    if k == "store_cowin":
        return f"{nm(h['source_store'])}({h['source_region']}) ↔ {nm(h['target_store'])}({h['target_region']}) 같은 회차 동시 당첨"
    if k == "region_store_lead":
        return f"{h['source_region']} 1등{lag} 후 {nm(h['target_store'])}({h['target_region']}) 당첨 증가"
    if k in ("region_lead", "self_repeat"):
        return f"{h['source_region']} 1등{lag} 후 {h['target_region']} 1등 {'증가' if h['direction'] == 'up' else '감소'}"
    if k == "region_cowin":
        return f"{h['source_region']} ↔ {h['target_region']} 같은 회차 1등 {'동시 발생 많음' if h['direction'] == 'up' else '동시 발생 적음'}"
    if k == "store_cycle":
        p = h["params"]
        return f"{nm(h['target_store'])} 당첨 간격 {p['lo']}~{p['hi']}회 구간에 재당첨 증가 (평균 간격 {p['gap_mean']:.0f}회)"
    if k == "cycle_pooled":
        return f"{h['agent_id']} 판매점들이 자기 평균 간격 구간에서 더 자주 당첨 (지방장 통합 {h['params'].get('stores', 0)}곳)"
    if k == "neighbor_spill":
        return f"{h['agent_id']} 판매점 당첨{lag} 후 반경 {h['params']['d_km']:g}km 주변 판매점 당첨 {'증가' if h['direction'] == 'up' else '감소'}"
    if k == "store_spill":
        return f"{nm(h['source_store'])} 당첨{lag} 후 반경 {h['params']['d_km']:g}km 주변 판매점 당첨 증가"
    if k == "region_trend_up":
        return f"{h['target_region']} 최근 100회 1등 집중(z={h['params']['z']:.1f}) 지속"
    if k == "region_trend_down":
        return f"{h['target_region']} 최근 100회 1등 감소(z={h['params']['z']:.1f}) 지속"
    if k == "region_dormant":
        return f"{h['target_region']} {h['params']['dormant']}회 1등 미출현 후 반등"
    if k == "composite":
        return f"{nm(h['target_store'])} 주기 구간 ∧ 선행 조건 동시 충족 시 당첨 증가"
    return k


def build_rows(u, eng, latest, runner):
    now = datetime.now(timezone.utc).isoformat()
    H = eng.st.H
    hyp_rows = []
    for h in H:
        i = h["idx"]
        s = eng.status[i]
        live = h["kind"] in BOOST_KINDS and s in (S_PASS, S_COMB)
        row = {k: v for k, v in h.items() if not k.startswith("_") and k != "idx"}
        row.update({"model_version": MODEL, "test_n": int(eng.n[i]), "test_k": int(eng.k[i]), "test_expected": float(eng.e[i]),
                    "test_p": float(eng.test_p[i]), "test_q": float(eng.test_q[i]), "status": STATUS[s], "live_eligible": bool(live),
                    "rec_state": "live" if live else ("exploratory" if h["kind"] in BOOST_KINDS and s != S_REJ else "none"),
                    "evaluated_round": latest, "updated_at": now})
        row["evidence"] = dict(row["evidence"], summary=h_summary(u, h),
                               control={"k_off": int(eng.koff[i]), "e_off": float(eng.eoff[i])},
                               relative_ratio=float(eng.test_ratio[i]))
        hyp_rows.append(row)
    # 지방장 상태
    A = len(u.agent_ids)
    hc = [Counter() for _ in range(A)]
    for h in H:
        a = u.aidx.get(h["agent_id"])
        if a is not None:
            hc[a][STATUS[eng.status[h["idx"]]]] += 1
    perf = [Counter() for _ in range(A)]
    for tr, per in eng.backtest.items():
        for p in per:
            c = perf[p["agent"]]
            c["rounds"] += 1
            for k in ("hits_first", "hits_any", "explore_hits_any", "history_hits_any", "region_events", "region_first"):
                c[k] += p[k]
            c["expected_uniform"] += p["expected_uniform"]
    recent_from = u.R - 200
    active = (u.E[max(recent_from, 0):].sum(0) > 0)
    agent_rows = []
    for a, ag in enumerate(u.agent_ids):
        mem = u.members[a]
        subs = defaultdict(lambda: [0, 0, 0])
        for s in mem:
            sb = u.sub[s] or "(미상)"
            subs[sb][0] += 1
            subs[sb][1] += int(u.E[:, s].sum())
            subs[sb][2] += int(u.F[:, s].sum())
        sido, unit = (ag.split("|") + [ag])[:2] if ag != "internet" else ("internet", "인터넷 판매")
        p = perf[a]
        agent_rows.append({"agent_id": ag, "model_version": MODEL, "level": "internet" if ag == "internet" else "sigungu",
                           "sido": sido, "unit_name": unit,
                           "sub_units": [{"name": k, "stores": v[0], "events": v[1], "first": v[2]}
                                         for k, v in sorted(subs.items(), key=lambda x: (-x[1][1], x[0]))],
                           "store_count": int(len(mem)), "active_store_count": int(active[mem].sum()),
                           "geo_store_count": int(u.geo[mem].sum()), "duplicate_groups": int(u.dup_groups_by_agent.get(a, 0)),
                           "status": "completed", "last_processed_round": latest, "last_target_round": latest + 1,
                           "hypothesis_counts": dict(hc[a]), "delivery_count": int(p["rounds"] * min(K_DELIVER, len(mem)) + min(K_DELIVER, len(mem))),
                           "performance": {"backtest_rounds": int(p["rounds"]), "hits_first": int(p["hits_first"]),
                                           "hits_any": int(p["hits_any"]), "explore_hits_any": int(p["explore_hits_any"]),
                                           "history_hits_any": int(p["history_hits_any"]), "expected_uniform": round(p["expected_uniform"], 3),
                                           "region_events": int(p["region_events"]), "region_first": int(p["region_first"]),
                                           "lift_vs_uniform": (p["hits_any"] / p["expected_uniform"]) if p["expected_uniform"] > 0 else None},
                           "error": None, "last_run_at": now, "updated_at": now})
    # 백테스트 평가·중앙
    evals, central, central_ev = [], [], []
    for tr, per in eng.backtest.items():
        for p in per:
            evals.append({"model_version": MODEL, "target_round": tr, "agent_id": u.agent_ids[p["agent"]], "mode": "backtest",
                          "delivered": [u.codes[s] for s in p["delivered"]], "explored": [u.codes[s] for s in p["explored"]],
                          "history_only": [u.codes[s] for s in p["history_only"]], "hits_first": p["hits_first"],
                          "hits_any": p["hits_any"], "explore_hits_any": p["explore_hits_any"], "history_hits_any": p["history_hits_any"],
                          "region_events": p["region_events"], "region_first": p["region_first"],
                          "expected_uniform": p["expected_uniform"], "n_stores": p["n_stores"]})
        c = eng.central[tr]
        central.append({"model_version": MODEL, "target_round": tr, "mode": "backtest", "training_end_round": tr - 1, **c})
        central_ev.append({"model_version": MODEL, "target_round": tr, "mode": "backtest", "metrics": eng.central_eval[tr]})
    # 실전 납품 (latest+1)
    target, dv, fire, targets, reg_targets = eng.live
    live_ratio, explore_ratio = eng.ratios()
    applied = defaultdict(list)
    for i in np.where(fire & eng.boost)[0]:
        tg = targets.get(i)
        stores_ = tg if tg is not None else (u.members[u.aidx[u.reg_ids[reg_targets[i]]]] if i in reg_targets else [])
        for s in stores_:
            applied[int(s)].append(int(i))
    related = defaultdict(list)
    for h in H:
        for cd in h["related_stores"]:
            related[cd].append(h["idx"])
    deliveries, scores = [], []
    A = len(u.agent_ids)
    for a in range(A):
        order = dv["order"][dv["starts"][a]:dv["ends"][a]]
        size = len(order)
        for r, s in enumerate(order):
            s = int(s)
            scores.append({"model_version": MODEL, "target_round": target, "store_code": u.codes[s], "agent_id": u.agent_ids[a],
                           "agent_rank": r + 1, "agent_size": size, "score": float(dv["s_live"][s]),
                           "p_first": float(dv["s_live"][s] * dv["phi"]), "live_factor": float(dv["f_live"][s]),
                           "explore_factor": float(dv["f_exp"][s]), "hyp_count": len(related.get(u.codes[s], [])),
                           "training_end_round": latest})
        for r, s in enumerate(dv["live"][a]):
            s = int(s)
            cd = u.codes[s]
            ev = np.where(u.E[:, s] == 1)[0]
            fr = np.where(u.F[:, s] == 1)[0]
            gaps = np.diff(ev)
            hy = []
            seen = set()
            for i in applied.get(s, []) + related.get(cd, []):
                if i in seen:
                    continue
                seen.add(i)
                h = H[i]
                is_app = i in applied.get(s, [])
                live_ok = bool(eng.status[i] in (S_PASS, S_COMB))
                hy.append({"id": h["hypothesis_id"], "kind": h["kind"], "status": STATUS[eng.status[i]], "summary": h_summary(u, h),
                           "firing": is_app, "applied_live": is_app and live_ok and h["kind"] in BOOST_KINDS,
                           "factor_live": float(min(max(live_ratio[i], 1 / FACTOR_CAP), FACTOR_CAP)) if (is_app and live_ok) else 1.0,
                           "factor_explore": float(min(max(explore_ratio[i], 1 / FACTOR_CAP), FACTOR_CAP)) if is_app else 1.0,
                           "shared_from": h.get("shared_from")})
                if len(hy) >= 6:
                    break
            deliveries.append({"model_version": MODEL, "target_round": target, "agent_id": u.agent_ids[a], "store_code": cd,
                               "mode": "live", "rank": r + 1, "score": float(dv["s_live"][s]),
                               "p_first": float(dv["s_live"][s] * dv["phi"]), "store_name": u.name[s], "address": u.addr[s],
                               "lat": None if np.isnan(u.lat[s]) else float(u.lat[s]),
                               "lng": None if np.isnan(u.lng[s]) else float(u.lng[s]),
                               "history": {"first": int(len(fr)), "second": int(len(ev) - len(fr)),
                                           "first_rounds": [int(u.rounds[x]) for x in fr[::-1][:10]],
                                           "last_event_round": int(u.rounds[ev[-1]]) if len(ev) else None,
                                           "gap_mean": float(gaps.mean()) if len(gaps) else None,
                                           "gap_median": float(np.median(gaps)) if len(gaps) else None,
                                           "rounds_since_last": int(u.R - 1 - ev[-1]) if len(ev) else None},
                               "components": {"base": float(dv["lam"][s]), "region_prior": float(dv["mreg"][s]),
                                              "live_factor": float(dv["f_live"][s]), "explore_factor": float(dv["f_exp"][s]),
                                              "first_share": float(dv["phi"])},
                               "hypotheses": hy,
                               "verification": "검증 가설 반영" if dv["f_live"][s] != 1 else "이력 기반(검증 가설 없음)",
                               "data_quality": {"events": int(len(ev)), "has_geo": bool(u.geo[s]), "possible_duplicate": bool(u.dup[s]),
                                                "first_event_round": int(u.rounds[ev[0]]) if len(ev) else None,
                                                "missing_rounds": len(u.missing_rounds)},
                               "training_end_round": latest})
    live_central = {"model_version": MODEL, "target_round": target, "mode": "live", "training_end_round": latest,
                    **dv_central(u, dv, all_regions=True)}
    # 관계 그래프 (최신 체크포인트)
    rel_rows = []
    for cp in sorted(eng.relations_by_cp):
        if cp != latest and (cp - CP_FIRST) % CP_STEP != 0:
            continue
        seen = set()
        for (kind, src, dst, lag, sr, dr, n, k, e, p, q) in sorted(eng.relations_by_cp[cp], key=lambda x: x[9]):
            key = (kind, src, dst or dr, lag)
            if key in seen:
                continue
            seen.add(key)
            rel_rows.append({"model_version": MODEL, "training_end_round": cp, "kind": kind, "src_id": src, "dst_id": dst or dr,
                             "lag": lag, "src_region": sr, "dst_region": dr, "n": n, "k": k, "expected": e,
                             "ratio": (k / e) if e > 0 else None, "p": p, "q": q})
    return {"hypotheses": hyp_rows, "agents": agent_rows, "evals": evals, "central": central, "central_evals": central_ev,
            "deliveries": deliveries, "scores": scores, "live_central": live_central, "relations": rel_rows,
            "events": eng.events}


def performance_summary(u, eng):
    tot = Counter()
    for per in eng.backtest.values():
        for p in per:
            for k in ("hits_first", "hits_any", "explore_hits_any", "history_hits_any", "region_events"):
                tot[k] += p[k]
            tot["expected_uniform"] += p["expected_uniform"]
    cm = Counter()
    for m in eng.central_eval.values():
        for k, v in m.items():
            cm[k] += v
    nr = max(len(eng.central_eval), 1)
    rounds = sorted(eng.backtest)
    return {"rounds": [rounds[0], rounds[-1]] if rounds else [], "n_rounds": len(rounds),
            "agent_hits_live": int(tot["hits_any"]), "agent_hits_first": int(tot["hits_first"]),
            "agent_hits_history": int(tot["history_hits_any"]), "agent_hits_explore": int(tot["explore_hits_any"]),
            "expected_uniform": round(float(tot["expected_uniform"]), 2), "total_events": int(tot["region_events"]),
            "central_logloss": {"model": cm["logloss_model"] / nr, "m0": cm["logloss_m0"] / nr, "m1": cm["logloss_m1"] / nr},
            "central_region_hits": int(cm["region_hits"]), "central_region_hits_m0": int(cm["region_hits_m0"]),
            "central_region_expected": round(float(cm["region_expected"]), 2),
            "central_store_hits": int(cm["store_hits_any"]), "central_store_hits_first": int(cm["store_hits_first"]),
            "central_store_hits_history": int(cm["store_hits_any_history"]),
            "central_store_expected_uniform": round(float(cm["store_expected_uniform"]), 2),
            "multi_condition": {"ge2": {"n": eng.multi[0], "k": eng.multi[1], "expected": round(eng.multi[2], 2)},
                                "one": {"n": eng.multi[3], "k": eng.multi[4], "expected": round(eng.multi[5], 2)},
                                "none": {"n": eng.multi[6], "k": eng.multi[7], "expected": round(eng.multi[8], 2)}},
            "live_rounds_evaluated": 0}


def build_briefing(u, eng, rows, latest, perf, prev_ranks):
    H = eng.st.H
    st_counts = Counter(STATUS[s] for s in eng.status)
    by_kind = defaultdict(list)
    for h in H:
        by_kind[h["kind"]].append(h)

    def top(hs, n=3):
        hs = sorted(hs, key=lambda h: (eng.status[h["idx"]] not in (S_PASS, S_COMB), eng.test_p[h["idx"]], h["train_p"] or 1, h["hypothesis_id"]))
        return [summarize_h(u, eng, h) for h in hs[:n]]

    famous = [h for h in by_kind["store_cycle"] if h["params"].get("famous")]
    cow_store = [h for h in by_kind["store_cowin"] if h["params"].get("cross_region")]
    lead = by_kind["store_lead"] + by_kind["region_store_lead"] + by_kind["region_lead"]
    last_cp = max(eng.relations_by_cp) if eng.relations_by_cp else latest
    shared = [h for h in H if h.get("shared_from")]
    new_shared = [h for h in shared if h["discovered_round"] == last_cp]
    lc = rows["live_central"]
    top_stores = []
    for s in lc["store_top"][:10]:
        reason = (f"{s['agent_id']} 지방장 {s['agent_rank']}위 · 최근 가중 당첨 빈도 상위"
                  + (f" · 검증 가설 보정 ×{s['live_factor']:.2f}" if s["live_factor"] != 1 else " · 검증 통과 가설 미적용"))
        top_stores.append(dict(s, reason=reason))
    changes = []
    for s in lc["store_top"][:10]:
        pr = prev_ranks.get(s["store_code"])
        if pr is None or pr != s["agent_rank"]:
            i = u.cidx[s["store_code"]]
            last_row = u.R - 1
            why = []
            if u.E[last_row, i]:
                why.append(f"{latest}회 당첨으로 최근 가중 빈도 상승")
            if s["live_factor"] != 1:
                why.append("검증 통과 가설 발화")
            if not why:
                why.append("다른 판매점의 감쇠·당첨 변화로 상대 순위 이동")
            changes.append({"store_code": s["store_code"], "name": s["name"], "agent_id": s["agent_id"], "rank_now": s["agent_rank"],
                            "rank_prev": pr, "reason": " · ".join(why)})
    limits = [
        "판매점별 판매량 자료 없음 → 점수는 회차당 1·2등 기대 빈도(판매량 미보정)이며 한 장당 당첨확률이 아님",
        f"1등 기록 누락 회차 {len(u.missing_rounds)}개 (판매액 자료로 1등 0명 확인된 회차는 포함)",
        f"현재 판매점 목록에 없는 코드의 당첨 기록 1등 {u.unknown_first}건 · 2등 {u.unknown_second}건 (폐업·이전 추정, 지역 연구 제외)",
        f"주소 해석 실패 판매점 {u.unparsed}곳 · 이름·주소 동일 다중 코드 묶음 {int(sum(u.dup_groups_by_agent.values()))}개 (병합하지 않음)",
        "행정구역 공식 코드·판매점 개업/폐업일 자료 미확보 → 정규화 지역명 키 사용, 판매점 목록은 현재 기준",
        "백테스트(1000회~)는 과거 데이터만으로 사후 재현한 결과이며, 추첨 전에 저장된 실전 납품 평가는 별도 집계",
    ]
    pf = dict(perf)
    lines = [
        f"{latest + 1}회 대상: 지방장 {len(u.agent_ids)}명이 판매점 {u.S}곳을 연구해 후보를 납품했습니다.",
        f"가설 {len(H)}건 — 검증 통과 {st_counts.get('passed', 0) + st_counts.get('combined', 0)} · 연구 중 {st_counts.get('researching', 0)} · "
        f"약화 {st_counts.get('weakened', 0)} · 기각 {st_counts.get('rejected', 0)} · 발견 {st_counts.get('discovered', 0)}.",
        f"순차 검증 {pf['rounds'][0] if pf['rounds'] else '-'}~{pf['rounds'][-1] if pf['rounds'] else '-'}회: 지방장 실전 목록 1·2등 적중 {pf['agent_hits_live']}건 "
        f"(이력만 {pf['agent_hits_history']} · 무작위 기대 {pf['expected_uniform']:.0f}).",
        f"중앙 엔진 지역 예측 log-loss {pf['central_logloss']['model']:.4f} (판매점 수 기준 {pf['central_logloss']['m0']:.4f}).",
    ]
    return {"target_round": latest + 1, "training_end_round": latest, "model_version": MODEL,
            "agents": {"total": len(u.agent_ids), "completed": len(u.agent_ids), "failed": 0, "stores": u.S},
            "focus_regions": lc["focus_regions"][:5], "top_stores": top_stores,
            "famous_cycles": {"tested": len(famous), "by_status": dict(Counter(STATUS[eng.status[h["idx"]]] for h in famous)),
                              "examples": top(famous)},
            "cowin": {"counts": {"store_pairs": len(by_kind["store_cowin"]), "cross_region_store_pairs": len(cow_store),
                                 "region_pairs": len(by_kind["region_cowin"])},
                      "store_pairs": top(cow_store), "region_pairs": top(by_kind["region_cowin"])},
            "lead_lag": {"counts": {k: len(by_kind[k]) for k in ("store_lead", "region_store_lead", "region_lead", "self_repeat",
                                                                "neighbor_spill", "store_spill")},
                         "examples": top(lead + by_kind["neighbor_spill"], 4)},
            "shared": {"templates": len({h["shared_from"] for h in shared}), "instances": len(shared),
                       "new_this_checkpoint": len(new_shared), "conflicts": int(eng.stats.get("template_conflicts", 0)),
                       "examples": top(new_shared or shared)},
            "status_counts": {s: int(st_counts.get(s, 0)) for s in STATUS},
            "performance": pf, "rank_changes": changes[:8], "data_limits": limits, "lines": lines}


# ── 실행 ──────────────────────────────────────────────────────────
def count_rows(db, table):
    r = requests.get(db.base + table, params={"select": "*", "model_version": f"eq.{MODEL}"},
                     headers=dict(db.h, Prefer="count=exact", Range="0-0"), timeout=60)
    cr = r.headers.get("content-range", "")
    return int(cr.split("/")[-1]) if "/" in cr and cr.split("/")[-1].isdigit() else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out", default=None)
    ap.add_argument("--latest", type=int, default=None)
    ap.add_argument("--runner", default=os.getenv("RESEARCH_RUNNER", "local"))
    ap.add_argument("--selftest-leak", type=int, default=None)
    ap.add_argument("--evaluate-only", action="store_true", help="ag-1.0 동결: 저장된 실전 스냅샷 평가만")
    a = ap.parse_args()
    url, key = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY")
    if not url or not key:
        log("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다"); sys.exit(1)
    db = Db(url, key)
    if key.startswith("sb_"):
        # 새 형식 API 키(sb_secret_/sb_publishable_)는 JWT 가 아니므로 apikey 헤더로만 보낸다
        db.h.pop("Authorization", None)
    raw = load(db)
    ready, pending = ready_latest(raw)
    if pending:
        log(f"[ready] 데이터 미준비 회차 제외: {pending}")
    latest = min(ready, a.latest) if a.latest else ready

    if a.selftest_leak:
        cut = a.selftest_leak
        log(f"[selftest] 미래 누출 검사: {cut}회까지만 준 실행 vs 전체 실행")
        _, e1 = run(raw, cut, progress=False)
        _, e2 = run(raw, latest, progress=False)
        diffs = 0
        for tr in sorted(e1.backtest):
            for p1, p2 in zip(e1.backtest[tr], e2.backtest[tr]):
                for k in ("delivered", "explored", "history_only"):
                    if list(p1[k]) != list(p2[k]):
                        diffs += 1
            c1, c2 = e1.central[tr], e2.central[tr]
            if [x["region_id"] for x in c1["focus_regions"]] != [x["region_id"] for x in c2["focus_regions"]]:
                diffs += 1
        # 실전 목표 cut+1 납품 = 전체 실행의 cut+1 백테스트 납품
        t1, dv1 = e1.live[0], e1.live[1]
        for a_, p2 in enumerate(e2.backtest[t1]):
            if list(dv1["live"][a_]) != list(p2["delivered"]):
                diffs += 1
        res = {"selftest_leak": cut, "rounds_compared": len(e1.backtest) + 1, "differences": diffs, "pass": diffs == 0}
        print(json.dumps(res, ensure_ascii=False))
        sys.exit(0 if diffs == 0 else 4)

    role = key_role(key)
    tables_ok = all(db.exists(t) for t in TABLES)
    if a.evaluate_only:
        # ag-1.0 은 동결: 새 예측 없이, 추첨 전 저장된 ag-1.0 실전 스냅샷만 실제 결과로 평가
        if not tables_ok or role != "service_role":
            print(json.dumps({"skipped": True, "reason": "SQL 미적용 또는 service_role 아님"})); return
        u = Universe(raw, latest)
        ev, cev, n = evaluate_live(db, u, latest)
        if ev:
            db.upsert("research_agent_round_evals", clean(ev), "model_version,target_round,agent_id,mode", ignore_duplicates=True)
        if cev:
            db.upsert("research_agent_central_evals", clean(cev), "model_version,target_round,mode", ignore_duplicates=True)
            db.upsert("research_agent_jobs", [{"model_version": MODEL, "job_type": "live_eval", "job_key": c["target_round"],
                                               "status": "done", "attempts": 1, "error": None} for c in cev],
                      "model_version,job_type,job_key")
        print(json.dumps({"evaluate_only": True, "live_rounds_evaluated": n}, ensure_ascii=False)); return
    if not a.dry_run:
        if not tables_ok:
            print("::warning::research_v5_agents.sql 미적용 — 지방장 연구를 건너뜁니다 (Supabase SQL Editor 에서 실행 필요)")
            print(json.dumps({"skipped": True, "reason": "SQL 미적용"})); return
        if role != "service_role":
            print(f"::warning::SUPABASE_KEY 역할이 service_role 이 아님({role}) — 지방장 테이블은 service_role 만 쓸 수 있습니다")
            print(json.dumps({"skipped": True, "reason": f"키 역할 {role}"})); return
        if not a.force:
            done = db.select_all("research_agent_runs", {"select": "status", "order": "training_end_round", "model_version": f"eq.{MODEL}",
                                                         "training_end_round": f"eq.{latest}"})
            if any(d["status"] == "completed" for d in done):
                print(json.dumps({"skipped": True, "reason": f"{latest}회 이미 완료"})); return
        db.upsert("research_agent_runs", [{"model_version": MODEL, "training_end_round": latest, "status": "running",
                                           "runner": a.runner, "started_at": datetime.now(timezone.utc).isoformat(),
                                           "completed_at": None, "error": None}], "model_version,training_end_round")
    t_start = time.time()
    try:
        u, eng = run(raw, latest)
        rows = build_rows(u, eng, latest, a.runner)
        perf = performance_summary(u, eng)
        # 이전 목표 회차 순위 (실전 스냅샷 우선, 없으면 백테스트)
        prev_ranks = {}
        if tables_ok:
            try:
                prev = db.select_all("research_agent_store_scores", {"select": "store_code,agent_rank", "order": "store_code", "model_version": f"eq.{MODEL}",
                                                                     "target_round": f"eq.{latest}"})
                prev_ranks = {r["store_code"]: r["agent_rank"] for r in prev}
            except Exception as e:
                log(f"[warn] prev ranks {e}")
        if not prev_ranks and latest in eng.backtest:
            for p in eng.backtest[latest]:
                for r, s in enumerate(p["delivered"]):
                    prev_ranks[u.codes[s]] = r + 1
        # 실전 납품 평가 (추첨 전 저장된 스냅샷만 사용)
        live_evals, live_central_evals = [], []
        if tables_ok:
            live_evals, live_central_evals, n_live = evaluate_live(db, u, latest)
            perf["live_rounds_evaluated"] = n_live
        briefing = build_briefing(u, eng, rows, latest, perf, prev_ranks)
        summary = {"model_version": MODEL, "latest": latest, "target_round": latest + 1, "agents": len(u.agent_ids),
                   "regions": u.U, "stores": u.S, "rounds_processed": [LEARN_START, latest],
                   "hypotheses": len(eng.st.H), "status_counts": briefing["status_counts"],
                   "by_kind": dict(Counter(h["kind"] for h in eng.st.H)),
                   "significant_discoveries": int(sum(1 for h in eng.st.H if h["discovery_significant"])),
                   "shared": briefing["shared"], "tests": eng.stats, "performance": perf,
                   "deliveries": {"backtest": len(rows["evals"]) * K_DELIVER, "live": len(rows["deliveries"])},
                   "status_by_kind": {k: dict(Counter(STATUS[eng.status[h["idx"]]] for h in eng.st.H if h["kind"] == k))
                                      for k in sorted({h["kind"] for h in eng.st.H})},
                   "passed_hypotheses": [dict(summarize_h(u, eng, h), ratio=float(eng.test_ratio[h["idx"]]),
                                              q=float(eng.test_q[h["idx"]]))
                                         for h in eng.st.H if eng.status[h["idx"]] in (S_PASS, S_COMB)],
                   "tuned": eng.tuned, "elapsed_sec": round(eng.elapsed, 1), "external_ai_api_calls": 0}
        res = {"summary": summary, "briefing": briefing}
        if a.out:
            json.dump(clean(dict(res, agents=rows["agents"], sample_deliveries=rows["deliveries"][:30],
                                 sample_hypotheses=rows["hypotheses"][:50], live_central=rows["live_central"],
                                 row_counts={k: len(v) for k, v in rows.items() if isinstance(v, list)})),
                      open(a.out, "w", encoding="utf-8"), ensure_ascii=False, default=_json_default)
        if not a.dry_run:
            usage = write_all(db, u, rows, briefing, live_evals, live_central_evals, latest)
            summary["usage"] = usage
            summary["elapsed_total_sec"] = round(time.time() - t_start, 1)
            db.upsert("research_agent_runs", [{"model_version": MODEL, "training_end_round": latest, "status": "completed",
                                               "runner": a.runner, "stats": clean(summary), "error": None,
                                               "completed_at": datetime.now(timezone.utc).isoformat()}], "model_version,training_end_round")
        print(json.dumps(clean(summary), ensure_ascii=False, default=_json_default))
    except Exception as e:
        if not a.dry_run and tables_ok and role == "service_role":
            db.upsert("research_agent_runs", [{"model_version": MODEL, "training_end_round": latest, "status": "failed",
                                               "runner": a.runner, "error": str(e)[:500],
                                               "completed_at": datetime.now(timezone.utc).isoformat()}], "model_version,training_end_round")
        raise


def evaluate_live(db, u, latest):
    """추첨 전에 저장된 live 스냅샷(store_scores·central)을 실제 결과로 평가 (아직 평가 안 된 회차만)"""
    done = {r["target_round"] for r in db.select_all("research_agent_central_evals", {
        "select": "target_round", "order": "target_round,mode", "model_version": f"eq.{MODEL}", "mode": "eq.live"})}
    cands = db.select_all("research_agent_central", {"select": "target_round,focus_regions,store_top", "order": "target_round,mode", "model_version": f"eq.{MODEL}",
                                                     "mode": "eq.live", "target_round": f"lte.{latest}"})
    evals, cevals = [], []
    for c in cands:
        tr = c["target_round"]
        if tr in done or tr < u.r0:
            continue
        ti = u.row(tr)
        sc = db.select_all("research_agent_store_scores", {"select": "store_code,agent_id,agent_rank,score,live_factor,explore_factor", "order": "store_code",
                                                           "model_version": f"eq.{MODEL}", "target_round": f"eq.{tr}"})
        by_agent = defaultdict(list)
        for r in sc:
            by_agent[r["agent_id"]].append(r)
        Et, Ft = u.E[ti], u.F[ti]
        for ag, lst in by_agent.items():
            idx = lambda rows_: [u.cidx[r["store_code"]] for r in rows_ if r["store_code"] in u.cidx]
            live = sorted(lst, key=lambda r: r["agent_rank"])[:K_DELIVER]
            base = sorted(lst, key=lambda r: (-(r["score"] / (r["live_factor"] or 1)), r["store_code"]))[:K_DELIVER]
            expl = sorted(lst, key=lambda r: (-(r["score"] / (r["live_factor"] or 1) * (r["explore_factor"] or 1)), r["store_code"]))[:K_DELIVER]
            a = u.aidx.get(ag)
            mem = u.members[a] if a is not None else []
            ev = int(Et[mem].sum()) if len(mem) else 0
            evals.append({"model_version": MODEL, "target_round": tr, "agent_id": ag, "mode": "live",
                          "delivered": [r["store_code"] for r in live], "explored": [r["store_code"] for r in expl],
                          "history_only": [r["store_code"] for r in base],
                          "hits_first": int(Ft[idx(live)].sum()), "hits_any": int(Et[idx(live)].sum()),
                          "explore_hits_any": int(Et[idx(expl)].sum()), "history_hits_any": int(Et[idx(base)].sum()),
                          "region_events": ev, "region_first": int(Ft[mem].sum()) if len(mem) else 0,
                          "expected_uniform": float(min(K_DELIVER, len(mem)) / max(len(mem), 1) * ev), "n_stores": len(mem)})
        rf = {u.reg_ids[j]: int(u.RF[ti, j]) for j in range(u.U)}
        ps = [(x["p"], x["base"], rf.get(x["region_id"], 0)) for x in c["focus_regions"]]
        ll = lambda i: float(-np.mean([y * math.log(max(p[i], 1e-9)) + (1 - y) * math.log(max(1 - p[i], 1e-9)) for p in ps for y in [p[2]]]))
        top_codes = [s["store_code"] for s in c["store_top"] if s["store_code"] in u.cidx]
        cevals.append({"model_version": MODEL, "target_round": tr, "mode": "live",
                       "metrics": {"logloss_model": ll(0), "logloss_m0": ll(1),
                                   "region_hits": int(sum(p[2] for p in ps[:CENTRAL_REGIONS])),
                                   "store_hits_any": int(Et[[u.cidx[x] for x in top_codes]].sum()),
                                   "store_hits_first": int(Ft[[u.cidx[x] for x in top_codes]].sum()),
                                   "regions_evaluated": len(ps)}})
    return evals, cevals, len(cevals)


def write_all(db, u, rows, briefing, live_evals, live_central_evals, latest):
    t0 = time.time()
    jobs = {(r["job_type"], r["job_key"]) for r in db.select_all("research_agent_jobs", {"order": "job_type,job_key", 
        "select": "job_type,job_key,status", "model_version": f"eq.{MODEL}", "status": "eq.done"})}
    done_bt = {k for (t, k) in jobs if t == "backtest_round"}
    max_done = max(done_bt) if done_bt else 0
    bytes_ = Counter()

    def put(table, data, on, ignore=False):
        if not data:
            return
        data = clean(data)
        bytes_[table] += len(json.dumps(data, ensure_ascii=False, default=_json_default).encode("utf-8"))
        db.upsert(table, data, on, ignore_duplicates=ignore)

    log("[write] agents"); put("research_agents", rows["agents"], "agent_id,model_version")
    log("[write] hypotheses"); put("research_agent_hypotheses", rows["hypotheses"], "hypothesis_id,model_version")
    ev = [e for e in rows["events"] if e["round"] > max_done]
    log(f"[write] hypothesis events {len(ev)}"); put("research_agent_hypothesis_events", ev, "hypothesis_id,model_version,round", True)
    new_bt = sorted({r["target_round"] for r in rows["central"]} - done_bt)
    if new_bt:
        nb = set(new_bt)
        log(f"[write] backtest rounds {len(new_bt)} ({new_bt[0]}~{new_bt[-1]})")
        put("research_agent_round_evals", [r for r in rows["evals"] if r["target_round"] in nb],
            "model_version,target_round,agent_id,mode", True)
        put("research_agent_central", [r for r in rows["central"] if r["target_round"] in nb], "model_version,target_round,mode", True)
        put("research_agent_central_evals", [r for r in rows["central_evals"] if r["target_round"] in nb],
            "model_version,target_round,mode", True)
        put("research_agent_jobs", [{"model_version": MODEL, "job_type": "backtest_round", "job_key": t, "status": "done",
                                     "attempts": 1, "error": None} for t in new_bt], "model_version,job_type,job_key")
    log("[write] live delivery")
    put("research_agent_jobs", [{"model_version": MODEL, "job_type": "live_delivery", "job_key": latest + 1, "status": "pending",
                                 "attempts": 1, "error": None}], "model_version,job_type,job_key")
    put("research_agent_deliveries", rows["deliveries"], "model_version,target_round,agent_id,store_code,mode", True)
    put("research_agent_store_scores", rows["scores"], "model_version,target_round,store_code", True)
    put("research_agent_central", [rows["live_central"]], "model_version,target_round,mode", True)
    put("research_agent_jobs", [{"model_version": MODEL, "job_type": "live_delivery", "job_key": latest + 1, "status": "done",
                                 "attempts": 1, "error": None}], "model_version,job_type,job_key")
    if live_evals or live_central_evals:
        log(f"[write] live evals {len(live_central_evals)} rounds")
        put("research_agent_round_evals", live_evals, "model_version,target_round,agent_id,mode", True)
        put("research_agent_central_evals", live_central_evals, "model_version,target_round,mode", True)
        put("research_agent_jobs", [{"model_version": MODEL, "job_type": "live_eval", "job_key": c["target_round"], "status": "done",
                                     "attempts": 1, "error": None} for c in live_central_evals], "model_version,job_type,job_key")
    # 관계 그래프: 단계 체크포인트 + 최신만 유지 (이전 '최신' 체크포인트는 삭제)
    keep_cps = sorted({r["training_end_round"] for r in rows["relations"]})
    try:
        old = db.select_all("research_agent_relations", {"select": "training_end_round", "order": "training_end_round,kind,src_id,dst_id,lag", "model_version": f"eq.{MODEL}",
                                                         "kind": "eq.region_lead", "lag": "eq.1"})
        for cp in sorted({r["training_end_round"] for r in old} - set(keep_cps)):
            requests.delete(db.base + "research_agent_relations", params={"model_version": f"eq.{MODEL}",
                                                                          "training_end_round": f"eq.{cp}"}, headers=db.h, timeout=120)
    except Exception as e:
        log(f"[warn] relations cleanup {e}")
    log(f"[write] relations {len(rows['relations'])}")
    put("research_agent_relations", rows["relations"], "model_version,training_end_round,kind,src_id,dst_id,lag", True)
    put("research_agent_briefings", [{"model_version": MODEL, "target_round": latest + 1, "training_end_round": latest,
                                      "payload": briefing}], "model_version,target_round,training_end_round")
    put("research_results", [{"research_type": "agent_research", "model_version": MODEL, "training_end_round": latest,
                              "target_round": latest + 1, "payload": {"status_counts": briefing["status_counts"],
                                                                      "performance": briefing["performance"]}}],
        "research_type,model_version,training_end_round,target_round")
    counts = {t: count_rows(db, t) for t in TABLES}
    return {"bytes_written": dict(bytes_), "bytes_total": int(sum(bytes_.values())), "row_counts": counts,
            "write_sec": round(time.time() - t0, 1)}


if __name__ == "__main__":
    main()
