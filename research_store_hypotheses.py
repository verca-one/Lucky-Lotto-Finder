"""
판매점 가설 (hs-1.0) — 가설 공장의 판매점 단위 검정 · 모의

가설 = (판매점 조건, 결과, 기대 방향). 예: '반경 3km 안 판매점에서 직전 회차 1등이 나온 판매점은 다음 회차 1등이 더 나온다'.
  · 기준선 = 지방장 모델(ag-1.1)과 같은 방식: 1·2등 사건을 반감기 150회로 감쇠 누적 + 같은 시·군·구 평균 쪽 보정
    b = 감쇠 사건 수 + 0.3 × (지역 평균 감쇠 사건 수) — 그 회차 직전까지 정보만
    → 회차마다 그 회차 1등 판매점 수를 b 비율로 나눠 '지방장이 이미 아는 것만으로 기대되는 1등'(E)을 만든다.
    많이 파는 집·최근 잘 나가는 집 효과는 이 기준선이 흡수하므로, 조건이 지방장보다 더 설명하는지 본다.
  · 검정: 조건 판매점·회차의 실제 1등(O_c) vs 기대(E_c) — 전체 1등 수가 주어졌을 때 이항검정 (단측)
    배수 = (O_c/E_c) ÷ (O_나머지/E_나머지)
  · 구간: 발견 600~1000회 → 확인 1001회~가설 생성 회차 (가설 공장과 같은 절차 · BH 보정)
  · 모의: 확인 구간에서 시·군·구별 TOP5를 '이력 점수'로 고를 때와 '이력 점수 × 가설 가중'으로 고를 때 1등 적중 수 비교
    (지방장 TOP5 방식) → 회차별 차이 신뢰구간 하한 > 0 이면 '모의에서 적중 상승'
  · 조건은 모두 그 회차 직전(t−1)까지의 정보만 쓴다. 판매점 목록은 DB 의 로또 판매점(좌표 있는 곳) 기준.
    판매량·역 근처는 DB 에 없어 데이터 미확보.
읽기: lottery_stores · winning_history (크롤링 테이블은 읽기만)
"""

import math
from collections import defaultdict
from datetime import date

import numpy as np
from scipy.spatial import cKDTree
from scipy.stats import binom

START_ROUND = 262          # 로또 판매점 1·2등 기록 시작
DISCOVERY = (600, 1000)
CONFIRM_START = 1001
MIN_EVENTS = 30            # 구간 전체 1등 수
MIN_EXPECTED = 3.0         # 조건 쪽 기대 1등 수
SIM_TOP = 5
SIM_BOOST = 1.5            # 모의: 가설 쪽 판매점 점수 가중 (낮다 가설이면 1/1.5)
MIN_SIM_GAIN = 5           # 모의 '적중 상승'으로 인정할 최소 증가 (곳)
SIM_GAIN_RATE = 0.02       # … 또는 이력만 쓴 적중의 2%
HALF_LIFE = 150.0          # 지방장 모델 감쇠 반감기 (research_agent_worker.HALF_LIFE)
REGION_PRIOR = 0.3
SIDO_SHORT = {"서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천", "광주광역시": "광주",
              "대전광역시": "대전", "울산광역시": "울산", "세종특별자치시": "세종", "경기도": "경기", "강원도": "강원",
              "강원특별자치도": "강원", "충청북도": "충북", "충청남도": "충남", "전라북도": "전북", "전북특별자치도": "전북",
              "전라남도": "전남", "경상북도": "경북", "경상남도": "경남", "제주특별자치도": "제주"}


def addr_key(address):
    """주소 → (시도|시군구|도로명|건물번호) — 연금 판매점(코드 체계 다름)을 로또 판매점과 맞출 때"""
    import re
    a = re.sub(r"\([^)]*\)", " ", address or "")
    t = a.split()
    if len(t) < 4:
        return None
    t[0] = SIDO_SHORT.get(t[0], t[0])
    for i in range(2, len(t) - 1):
        if re.search(r"(로|길)$", t[i]) or re.search(r"(로|길)\d", t[i]):
            num = re.match(r"[\d\-]+", t[i + 1])
            if num:
                return "|".join(t[:2] + [t[i], num.group(0)])
    return None
CAPITAL = ("서울", "경기", "인천")
LOTTO_DAY1 = date(2002, 12, 7)
PENSION_DAY1 = date(2020, 4, 30)

STORE_CONDITIONS = {
    "near_first_prev": "반경 3km 안 다른 판매점에서 직전 회차 1등",
    "near_first_prev_1km": "반경 1km 안 다른 판매점에서 직전 회차 1등",
    "near_first_5": "반경 3km 안 다른 판매점에서 최근 5회 안 1등",
    "own_first_52": "본인이 최근 52회 안에 1등",
    "own_second_10": "본인이 최근 10회 안에 2등",
    "own_drought_famous": "1등 3회 이상 명당인데 최근 100회 1·2등 없음 (잠든 명당)",
    "emerging": "최근 52회 1·2등 2회 이상 · 그 이전엔 2회 이하 (신흥)",
    "famous_10": "로또 1등 10회 이상 (유명 명당)",
    "region_hot_10": "같은 시·군·구에서 최근 10회 1등 2곳 이상",
    "region_cold_26": "같은 시·군·구에서 최근 26회 1등 없음",
    "capital": "수도권(서울·경기·인천) 판매점",
    "dense_1km": "반경 1km 안 판매점 15곳 이상 (상권 밀집)",
    "isolated_1km": "반경 1km 안 판매점 2곳 이하 (단독 상권)",
    "pension_winner": "연금복권 1·2등이 나온 적 있는 판매점 (손님 많은 가게 대리지표)",
}
STORE_OUTCOMES = {"first": "다음 회차 1등", "first_second": "다음 회차 1·2등"}
EXCLUSIVE = [{"dense_1km", "isolated_1km"}, {"region_hot_10", "region_cold_26"}, {"near_first_prev", "near_first_prev_1km"}]


def region_key(address, region):
    p = (address or "").split()
    if len(p) >= 2 and p[1][-1:] in ("시", "군", "구"):
        return f"{p[0]}|{p[1]}"
    return p[0] if p else (region or "기타")


def lotto_round_of(d):
    """날짜 d 이후 첫 토요일 추첨 회차"""
    days = (d - LOTTO_DAY1).days
    return days // 7 + 1 + (1 if days % 7 else 0)


class StoreData:
    """판매점 × 회차 행렬 (좌표 있는 로또 판매점)"""

    def __init__(self, db, latest):
        stores = db.all("lottery_stores", {"select": "dhlottery_code,region,address,latitude,longitude",
                                           "lottery_type": "eq.lotto", "latitude": "not.is.null",
                                           "order": "dhlottery_code"}, key="dhlottery_code")
        self.codes = [s["dhlottery_code"] for s in stores]
        idx = {c: i for i, c in enumerate(self.codes)}
        S = len(self.codes)
        self.latest = latest
        self.T0 = START_ROUND
        T = latest - self.T0 + 1
        self.first = np.zeros((T, S), dtype=np.int8)
        self.second = np.zeros((T, S), dtype=np.int8)
        for tier, mat in (("first", self.first), ("second", self.second)):
            for r in db.all("winning_history", {"select": "round,dhlottery_code", "lottery_type": "eq.lotto",
                                                "prize_tier": f"eq.{tier}", "round": f"gte.{self.T0}",
                                                "order": "round,dhlottery_code"}, key="round"):
                i = idx.get(r["dhlottery_code"])
                if i is not None and self.T0 <= r["round"] <= latest:
                    mat[r["round"] - self.T0, i] = 1
        # 위치 · 지역
        lat = np.array([s["latitude"] for s in stores], dtype=float)
        lng = np.array([s["longitude"] for s in stores], dtype=float)
        to_xy = lambda la, lo: np.c_[np.asarray(la) * 111.0, np.asarray(lo) * 111.0 * math.cos(math.radians(36.5))]
        xy = to_xy(lat, lng)
        tree = cKDTree(xy)
        # 연금복권 1·2등 → 같은 주 로또 회차로 환산 (그 회차 이후부터 조건 참)
        # 연금 판매점은 코드가 로또와 같거나(일부) 다르다 → 코드가 없으면 주소(시도|시군구|도로명|번호)로 매칭
        self.pension_from = np.full(S, 10 ** 6, dtype=np.int32)
        by_addr = {}
        for i, st in enumerate(stores):
            k = addr_key(st.get("address"))
            if k:
                by_addr.setdefault(k, i)
        pst = {x["dhlottery_code"]: x for x in db.all("lottery_stores", {
            "select": "dhlottery_code,address", "lottery_type": "eq.pension", "order": "dhlottery_code"}, key="dhlottery_code")}
        self.pension_matched = 0
        for r in db.all("winning_history", {"select": "round,dhlottery_code", "lottery_type": "eq.pension",
                                            "order": "round,dhlottery_code"}, key="round"):
            i = idx.get(r["dhlottery_code"])
            if i is None:
                ps = pst.get(r["dhlottery_code"])
                i = by_addr.get(addr_key(ps.get("address"))) if ps else None
            if i is None:
                continue
            lr = lotto_round_of(date.fromordinal(PENSION_DAY1.toordinal() + 7 * (r["round"] - 1)))
            if self.pension_from[i] == 10 ** 6:
                self.pension_matched += 1
            self.pension_from[i] = min(self.pension_from[i], lr + 1)
        self.n3 = [np.array([j for j in nb if j != i], dtype=np.int32) for i, nb in enumerate(tree.query_ball_point(xy, 3.0))]
        self.n1 = [np.array([j for j in nb if j != i], dtype=np.int32) for i, nb in enumerate(tree.query_ball_point(xy, 1.0))]
        cnt1 = np.array([len(x) for x in self.n1])
        self.dense = cnt1 >= 15
        self.isolated = cnt1 <= 2
        keys = [region_key(s.get("address"), s.get("region")) for s in stores]
        uniq = sorted(set(keys))
        self.region_of = np.array([uniq.index(k) for k in keys], dtype=np.int32)
        self.n_regions = len(uniq)
        self.capital = np.array([(s.get("region") or "").split(" ")[0] in CAPITAL for s in stores])
        # 누적 (회차 t 행 = t 직전까지)
        self.cf = np.vstack([np.zeros((1, S), dtype=np.int32), np.cumsum(self.first, axis=0, dtype=np.int32)])
        self.cs = np.vstack([np.zeros((1, S), dtype=np.int32), np.cumsum(self.second, axis=0, dtype=np.int32)])
        # 감쇠 사건 누적 (행 t = t 직전까지) — 지방장 모델과 같은 반감기
        g = 0.5 ** (1 / HALF_LIFE)
        ev = (self.first | self.second).astype(np.float32)
        self.kw = np.zeros((T + 1, S), dtype=np.float32)
        for i in range(T):
            self.kw[i + 1] = self.kw[i] * g + ev[i]
        self._cache = {}

    def ti(self, t):
        return t - self.T0

    def before(self, cum, t, k=None):
        """회차 t 직전까지 누적 (k 가 있으면 최근 k회)"""
        a = cum[self.ti(t)]
        if k is None:
            return a
        return a - cum[max(0, self.ti(t) - k)]

    def baseline(self, t):
        """지방장 방식 기준선: 감쇠 1·2등 사건 + 지역 평균 쪽 보정"""
        k = self.kw[self.ti(t)]
        reg_mean = (np.bincount(self.region_of, weights=k, minlength=self.n_regions)
                    / np.maximum(np.bincount(self.region_of, minlength=self.n_regions), 1))
        return k + REGION_PRIOR * reg_mean[self.region_of] + 1e-6

    def outcome(self, t, o):
        y = self.first[self.ti(t)].astype(bool)
        return y | self.second[self.ti(t)].astype(bool) if o == "first_second" else y

    def _near(self, t, k, nbs):
        m = np.zeros(len(self.codes), dtype=bool)
        lo = max(self.T0, t - k)
        for tt in range(lo, t):
            for w in np.nonzero(self.first[self.ti(tt)])[0]:
                m[nbs[w]] = True
        return m

    def cond(self, key, t):
        ck = (key, t)
        if ck in self._cache:
            return self._cache[ck]
        f_all, s_all = self.before(self.cf, t), self.before(self.cs, t)
        if key == "near_first_prev":
            m = self._near(t, 1, self.n3)
        elif key == "near_first_prev_1km":
            m = self._near(t, 1, self.n1)
        elif key == "near_first_5":
            m = self._near(t, 5, self.n3)
        elif key == "own_first_52":
            m = self.before(self.cf, t, 52) > 0
        elif key == "own_second_10":
            m = self.before(self.cs, t, 10) > 0
        elif key == "own_drought_famous":
            m = (f_all >= 3) & ((self.before(self.cf, t, 100) + self.before(self.cs, t, 100)) == 0)
        elif key == "emerging":
            recent = self.before(self.cf, t, 52) + self.before(self.cs, t, 52)
            m = (recent >= 2) & ((f_all + s_all - recent) <= 2)
        elif key == "famous_10":
            m = f_all >= 10
        elif key in ("region_hot_10", "region_cold_26"):
            k = 10 if key == "region_hot_10" else 26
            wins = self.before(self.cf, t, k)
            reg = np.bincount(self.region_of, weights=(wins > 0).astype(float), minlength=self.n_regions)
            m = reg[self.region_of] >= 2 if key == "region_hot_10" else reg[self.region_of] == 0
        elif key == "capital":
            m = self.capital
        elif key == "dense_1km":
            m = self.dense
        elif key == "isolated_1km":
            m = self.isolated
        elif key == "pension_winner":
            m = self.pension_from <= t
        else:
            raise KeyError(key)
        if len(self._cache) > 4000:
            self._cache.clear()
        self._cache[ck] = m
        return m

    def mask(self, conds, t):
        m = np.ones(len(self.codes), dtype=bool)
        for c in conds:
            m &= self.cond(c, t)
        return m


def store_test(sd, conds, o, e, lo, hi):
    """가설 공장 단계 결과와 같은 모양 (mean_cond/mean_other 는 '실제÷이력 기대' 배수)"""
    hi = min(hi, sd.latest)
    Oc = Ec = Oall = 0.0
    cells = 0
    for t in range(max(lo, sd.T0 + 1), hi + 1):
        y = sd.outcome(t, o)
        W = y.sum()
        if W == 0:
            continue
        b = sd.baseline(t)
        m = sd.mask(conds, t)
        cells += int(m.sum())
        Ec += W * b[m].sum() / b.sum()
        Oc += y[m].sum()
        Oall += W
    res = {"from": lo, "to": hi, "unit": "store", "n_cond": int(Oc), "n_other": int(Oall - Oc),
           "cells": cells, "expected_cond": round(Ec, 2)}
    En = Oall - Ec
    if Oall < MIN_EVENTS or Ec < MIN_EXPECTED or En <= 0:
        res["status"] = "small"
        return res
    rc, rn = Oc / Ec, (Oall - Oc) / En
    q = Ec / Oall
    p = binom.sf(Oc - 1, Oall, q) if e == "higher" else binom.cdf(Oc, Oall, q)
    res.update(mean_cond=round(rc, 4), mean_other=round(rn, 4), ratio=round(rc / rn, 4) if rn else None,
               p=round(float(p), 4), direction_ok=(rc > rn) if e == "higher" else (rc < rn))
    return res


def store_simulate(sd, conds, o, e, lo, hi, latest_label):
    """시·군·구별 TOP5: 이력 점수 vs 이력 점수 × 가설 가중 — 1등 적중 수 비교 (확인 구간)"""
    base = {"round": latest_label, "unit": "store"}
    boost = SIM_BOOST if e == "higher" else 1 / SIM_BOOST
    diffs, hb, hh = [], 0, 0
    reg = sd.region_of
    for t in range(max(lo, sd.T0 + 1), min(hi, sd.latest) + 1):
        y = sd.first[sd.ti(t)].astype(bool)
        if not y.any():
            continue
        b = sd.baseline(t)
        m = sd.mask(conds, t)
        hits = []
        for score in (b, np.where(m, b * boost, b)):
            order = np.lexsort((-score, reg))         # 지역별 점수 높은 순
            r_sorted = reg[order]
            start = np.r_[0, np.nonzero(np.diff(r_sorted))[0] + 1]
            rank = np.arange(len(order)) - np.repeat(start, np.diff(np.r_[start, len(order)]))
            top = order[rank < SIM_TOP]
            hits.append(int(y[top].sum()))
        hb += hits[0]
        hh += hits[1]
        diffs.append(hits[1] - hits[0])
    if len(diffs) < 10:
        return dict(base, status="small", note="모의할 회차가 부족합니다")
    d = np.array(diffs, dtype=float)
    se = d.std(ddof=1) / math.sqrt(len(d))
    md = float(d.mean())
    lo_ci, hi_ci = md - 1.96 * se, md + 1.96 * se
    # 적중 상승 = 회차별 차이 신뢰구간 하한 > 0 이면서 전체 적중이 2% 이상(최소 5곳) 늘었을 때 — 1~2곳 차이는 우연으로 본다
    up = lo_ci > 0 and (hh - hb) >= max(MIN_SIM_GAIN, SIM_GAIN_RATE * hb)
    return dict(base, status="done", rounds=len(diffs), hits_base=hb, hits_hyp=hh,
                lift=round(hh / hb, 4) if hb else None, diff=round(md, 4), ci=[round(lo_ci, 4), round(hi_ci, 4)], raised=up,
                note=(f"모의에서 적중 상승 — 시·군·구 TOP5 1등 적중 {hh}곳 vs 이력만 {hb}곳 ({len(diffs)}회차)" if up else
                      f"적중 상승 없음 — 시·군·구 TOP5 1등 적중 {hh}곳 vs 이력만 {hb}곳 ({len(diffs)}회차)"))
