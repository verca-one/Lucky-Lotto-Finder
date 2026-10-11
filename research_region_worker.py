"""
research_region_worker.py — 전국 시·군·구 지역 연구 Worker (명당 가설 연구소 확장, 2026-10-11)

* 기존 크롤러·엔진과 독립. 기존 테이블은 읽기만 하고, research_v4_regions.sql 의 신규 테이블에만 쓴다.
* 앱이 꺼져 있어도 GitHub Actions('Research Worker' 워크플로)에서 실행 가능. 로컬 실행도 가능.
* 미래 데이터 누수 방지: 체크포인트 c 의 연구는 c 이하 회차만 사용. 가설은 발견 체크포인트 이후 회차로만 검증.

연구 내용
  1. 지역 단위 구성 (광역시: 구·군 / 도: 시·군 / 세종) + 인접 생활권
  2. 지역 통계 (체크포인트 500,550,…,1200 + 최신): 원시 빈도, 판매점 수 비례 무작위 기준, 계층적 축소추정,
     최근 추세, 휴면, 지역 내 집중도, 상위 판매점, 구매방식
  3. 지역 간·지역 내 전이 가설 (+1~+6회, 증가/감소, 자기 반복) — 체크포인트별 BH-FDR 발견 → 순방향 검증
  4. A→B→C 복합 전이
  5. 거리별 전이 (1/3/5/10/20km) — 원형 이동 순열 귀무분포
  6. 판매점 주기·유명/신흥 판매점, 주기성 예측 검증, 신흥 지속성 검증, 휴면 반등 검증
  7. 지역별 예측 난이도 (무작위 기준 vs 지역 빈도 축소추정 vs 최근 빈도, 순방향 log-loss)

가설 상태 규칙 (평가 전 고정)
  test_n == 0 → discovered,  test_n < 20 → researching,
  같은 방향 & 단측 p < 0.05 / (같은 체크포인트 발견 수) → passed (복합은 combined),
  같은 방향이나 유의하지 않음 → weakened,  반대 방향 → rejected

사용:
  python research_region_worker.py                 # 최신 회차까지, 이미 완료면 건너뜀
  python research_region_worker.py --force         # 강제 재실행
  python research_region_worker.py --dry-run --out region_research.json   # DB 쓰기 없이 결과 파일만
환경변수: SUPABASE_URL, SUPABASE_KEY
"""
import argparse, json, math, os, sys, time
from collections import Counter, defaultdict
from datetime import datetime, timezone

import numpy as np
import requests
from scipy.stats import binom, poisson

MODEL = "rg-1.0"
CHECKPOINT_START, CHECKPOINT_STEP = 500, 50
LAGS = range(1, 7)
DIST_BANDS = [1, 3, 5, 10, 20]
MIN_N_TRAIN = 15
SIDO_SHORT = ["서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종",
              "경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주"]
METRO = {"서울", "부산", "대구", "인천", "광주", "대전", "울산"}
LONG2SHORT = {
    "서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천", "광주광역시": "광주",
    "대전광역시": "대전", "울산광역시": "울산", "세종특별자치시": "세종", "경기도": "경기", "강원도": "강원",
    "강원특별자치도": "강원", "충청북도": "충북", "충청남도": "충남", "전라북도": "전북", "전북특별자치도": "전북",
    "전라남도": "전남", "경상북도": "경북", "경상남도": "경남", "제주특별자치도": "제주",
}
GWANGJU_GU = {"동구", "서구", "남구", "북구", "광산구"}


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ── REST ───────────────────────────────────────────────────────────
class Db:
    def __init__(self, url, key):
        self.base = url.rstrip("/") + "/rest/v1/"
        self.h = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}

    def select_all(self, table, params, page=1000):
        out, off = [], 0
        while True:
            h = dict(self.h, **{"Range-Unit": "items", "Range": f"{off}-{off + page - 1}"})
            r = requests.get(self.base + table, params=params, headers=h, timeout=60)
            if r.status_code not in (200, 206):
                raise RuntimeError(f"select {table} {r.status_code} {r.text[:200]}")
            rows = r.json()
            out.extend(rows)
            if len(rows) < page:
                return out
            off += page

    def exists(self, table):
        r = requests.get(self.base + table, params={"select": "*", "limit": 1}, headers=self.h, timeout=30)
        return r.status_code == 200

    def upsert(self, table, rows, on_conflict, ignore_duplicates=False, chunk=500):
        pref = "resolution=ignore-duplicates" if ignore_duplicates else "resolution=merge-duplicates"
        h = dict(self.h, Prefer=pref + ",return=minimal")
        for i in range(0, len(rows), chunk):
            for attempt in range(3):
                r = requests.post(self.base + table, params={"on_conflict": on_conflict},
                                  data=json.dumps(rows[i:i + chunk], ensure_ascii=False, default=_json_default).encode("utf-8"),
                                  headers=h, timeout=120)
                if r.status_code in (200, 201, 204):
                    break
                log(f"[warn] upsert {table} {r.status_code} {r.text[:200]} (attempt {attempt + 1})")
                time.sleep(3 * (attempt + 1))
            else:
                raise RuntimeError(f"upsert {table} failed")


def _json_default(o):
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        f = float(o)
        return None if math.isnan(f) or math.isinf(f) else f
    if isinstance(o, set):
        return sorted(o)
    raise TypeError(type(o))


def clean(x):
    """NaN/inf → None (JSON 안전)"""
    if isinstance(x, float) and (math.isnan(x) or math.isinf(x)):
        return None
    if isinstance(x, dict):
        return {k: clean(v) for k, v in x.items()}
    if isinstance(x, list):
        return [clean(v) for v in x]
    return x


# ── 지역 파싱 ──────────────────────────────────────────────────────
def is_internet(name, address):
    s = f"{name or ''} {address or ''}".lower()
    return "dhlottery" in s or "인터넷" in s or "동행복권(" in s


def parse_region(region, address, name):
    """(region_id, sido, unit_name, sub_unit) 또는 ('internet',...) / (None,...)"""
    if is_internet(name, address):
        return "internet", "internet", "인터넷 판매", None
    toks = (address or "").split()
    sido = None
    reg = (region or "").strip()
    if reg in SIDO_SHORT:
        sido = reg
    elif reg in LONG2SHORT:
        sido = LONG2SHORT[reg]
    elif toks and toks[0] in SIDO_SHORT:
        sido = toks[0]
    elif toks and toks[0] in LONG2SHORT:
        sido = LONG2SHORT[toks[0]]
    t1 = toks[1] if len(toks) > 1 else ""
    t2 = toks[2] if len(toks) > 2 else ""
    if reg == "전남광주" or (toks and toks[0] == "전남광주"):
        sido = "광주" if t1 in GWANGJU_GU else "전남"
    if sido is None:
        return None, None, None, None
    if sido == "세종":
        return "세종|세종시", "세종", "세종시", (t1 if t1.endswith(("읍", "면", "동")) else None)
    if sido in METRO:
        if t1.endswith(("구", "군")):
            return f"{sido}|{t1}", sido, t1, (t2 if t2.endswith(("동", "읍", "면")) else None)
        return None, sido, None, None
    # 도: 시·군 단위
    unit = None
    if t1.endswith(("시", "군")):
        unit = t1
    elif "시" in t1 and t1.endswith("구"):          # '수원시영통구' 붙여쓰기
        unit = t1[: t1.index("시") + 1]
        t2 = t1[t1.index("시") + 1:]
    if unit is None:
        return None, sido, None, None
    sub = t2 if t2.endswith(("구", "읍", "면", "동")) else None
    return f"{sido}|{unit}", sido, unit, sub


def hav_km(a_lat, a_lng, b_lat, b_lng):
    R = 6371.0088
    p1, p2 = np.radians(a_lat), np.radians(b_lat)
    dphi = p2 - p1
    dl = np.radians(b_lng) - np.radians(a_lng)
    h = np.sin(dphi / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * R * np.arcsin(np.sqrt(np.minimum(1.0, h)))


def valid_geo(lat, lng):
    return lat is not None and lng is not None and 33 <= lat <= 39 and 124 <= lng <= 132


# ── 통계 유틸 ──────────────────────────────────────────────────────
def bh(pvals):
    p = np.asarray(pvals, dtype=float)
    n = len(p)
    if n == 0:
        return p
    order = np.argsort(p)
    q = np.empty(n)
    prev = 1.0
    for rank in range(n, 0, -1):
        i = order[rank - 1]
        prev = min(prev, p[i] * n / rank)
        q[i] = prev
    return q


def one_sided_p(k, n, p0, direction):
    if n <= 0:
        return 1.0
    p0 = min(max(p0, 1e-9), 1 - 1e-9)
    return float(binom.sf(k - 1, n, p0)) if direction == "up" else float(binom.cdf(k, n, p0))


def status_of(test_n, test_k, test_base, direction, m_disc, combined=False):
    if test_n == 0:
        return "discovered", None
    p = one_sided_p(test_k, test_n, test_base, direction)
    if test_n < 20:
        return "researching", p
    rate = test_k / test_n
    same = rate > test_base if direction == "up" else rate < test_base
    if same and p < 0.05 / max(1, m_disc):
        return ("combined" if combined else "passed"), p
    if same:
        return "weakened", p
    return "rejected", p


# ── 메인 연구 ──────────────────────────────────────────────────────
def run(db, latest_override=None):
    t0 = time.time()
    log("[load] lottery_stores")
    stores = db.select_all("lottery_stores", {
        "select": "dhlottery_code,store_name,address,region,latitude,longitude", "lottery_type": "eq.lotto"})
    log(f"  stores {len(stores)}")
    log("[load] winning_history (lotto 1·2등)")
    hist = db.select_all("winning_history", {
        "select": "dhlottery_code,round,prize_tier,purchase_method", "lottery_type": "eq.lotto",
        "prize_tier": "in.(first,second)"})
    log(f"  history {len(hist)}")
    nums = db.select_all("lotto_winning_numbers", {"select": "round"})
    latest = max(r["round"] for r in nums)
    if latest_override:
        latest = min(latest, latest_override)
    prize = {}
    if db.exists("research_prize_stats"):
        for r in db.select_all("research_prize_stats", {"select": "round,rank1_winners"}):
            prize[r["round"]] = r["rank1_winners"]

    # 판매점 → 지역
    store_info = {}
    unit_stores = defaultdict(list)
    unit_meta = {}
    unparsed = 0
    for s in stores:
        code = s["dhlottery_code"]
        rid, sido, unit, sub = parse_region(s.get("region"), s.get("address"), s.get("store_name"))
        lat, lng = s.get("latitude"), s.get("longitude")
        try:
            lat = float(lat) if lat is not None else None
            lng = float(lng) if lng is not None else None
        except (TypeError, ValueError):
            lat = lng = None
        store_info[code] = {"name": s.get("store_name"), "rid": rid, "lat": lat, "lng": lng, "sub": sub}
        if rid is None:
            unparsed += 1
            continue
        unit_stores[rid].append(code)
        if rid not in unit_meta:
            unit_meta[rid] = {"sido": sido, "unit": unit, "subs": set()}
        if sub:
            unit_meta[rid]["subs"].add(sub)

    # 회차별 1등 판매점·지역 (인터넷/미매칭 제외)
    first_by_round = defaultdict(list)
    second_by_store = Counter()
    second_by_store_round = defaultdict(list)
    methods_by_store = defaultdict(Counter)
    unknown_winners = internet_winners = 0
    for h in hist:
        r = h["round"]
        if r > latest:
            continue
        code = h["dhlottery_code"]
        info = store_info.get(code)
        if h["prize_tier"] == "second":
            second_by_store[code] += 1
            second_by_store_round[code].append(r)
            continue
        m = (h.get("purchase_method") or "").strip() or "미기재"
        methods_by_store[code][m] += 1
        if info is None or info["rid"] is None:
            unknown_winners += 1
            continue
        if info["rid"] == "internet":
            internet_winners += 1
        first_by_round[r].append(code)
    first_rounds_all = sorted(first_by_round)
    r_min = first_rounds_all[0]
    # 유효 회차: 1등 기록이 있거나, 판매액 데이터상 1등 0명 확정
    valid_rounds = [r for r in range(r_min, latest + 1) if r in first_by_round or prize.get(r) == 0]
    missing_rounds = [r for r in range(r_min, latest + 1) if r not in first_by_round and prize.get(r) != 0]
    vr_set = set(valid_rounds)
    regions_by_round = {r: {store_info[c]["rid"] for c in first_by_round.get(r, []) if store_info[c]["rid"] != "internet"}
                        for r in valid_rounds}
    regional_count_by_round = {r: sum(1 for c in first_by_round.get(r, []) if store_info[c]["rid"] != "internet")
                               for r in valid_rounds}
    unit_ids = sorted(k for k in unit_stores if k != "internet")
    uidx = {u: i for i, u in enumerate(unit_ids)}
    U = len(unit_ids)
    total_reg_stores = sum(len(unit_stores[u]) for u in unit_ids)
    share = np.array([len(unit_stores[u]) / total_reg_stores for u in unit_ids])
    log(f"[prep] units {U}, rounds {r_min}~{latest} valid {len(valid_rounds)} missing {len(missing_rounds)}, "
        f"unknown winners {unknown_winners}, internet winners {internet_winners}, unparsed stores {unparsed}")

    # 회차×지역 출현 행렬
    R = len(valid_rounds)
    ridx = {r: i for i, r in enumerate(valid_rounds)}
    X = np.zeros((R, U), dtype=np.int8)
    for r in valid_rounds:
        for u in regions_by_round[r]:
            X[ridx[r], uidx[u]] = 1
    reg_counts = np.array([regional_count_by_round[r] for r in valid_rounds], dtype=float)

    # ── 1. 지역 단위 (중심·인접) ─────────────────────────────────
    cent = {}
    for u in unit_ids:
        pts = [(store_info[c]["lat"], store_info[c]["lng"]) for c in unit_stores[u] if valid_geo(store_info[c]["lat"], store_info[c]["lng"])]
        cent[u] = (float(np.mean([p[0] for p in pts])), float(np.mean([p[1] for p in pts])), len(pts)) if pts else (None, None, 0)
    units_rows = []
    sidos = sorted({unit_meta[u]["sido"] for u in unit_ids})
    for u in unit_ids:
        lat, lng, ng = cent[u]
        neigh = []
        if lat is not None:
            ds = []
            for v in unit_ids:
                if v == u or cent[v][0] is None:
                    continue
                d = float(hav_km(lat, lng, cent[v][0], cent[v][1]))
                ds.append((d, v))
            ds.sort()
            neigh = [{"region_id": v, "km": round(d, 1)} for d, v in ds if d <= 25][:8] or [{"region_id": v, "km": round(d, 1)} for d, v in ds[:3]]
        units_rows.append({"region_id": u, "sido": unit_meta[u]["sido"], "unit_name": unit_meta[u]["unit"], "level": "sigungu",
                           "parent_id": unit_meta[u]["sido"], "sub_units": sorted(unit_meta[u]["subs"]),
                           "store_count": len(unit_stores[u]), "geo_store_count": ng, "lat": lat, "lng": lng,
                           "neighbors": neigh, "model_version": MODEL})
    for sd in sidos:
        members = [u for u in unit_ids if unit_meta[u]["sido"] == sd]
        units_rows.append({"region_id": sd, "sido": sd, "unit_name": sd, "level": "sido", "parent_id": None,
                           "sub_units": [unit_meta[u]["unit"] for u in members],
                           "store_count": sum(len(unit_stores[u]) for u in members), "geo_store_count": sum(cent[u][2] for u in members),
                           "lat": None, "lng": None, "neighbors": [], "model_version": MODEL})
    if "internet" in unit_stores:
        units_rows.append({"region_id": "internet", "sido": "internet", "unit_name": "인터넷 판매", "level": "internet", "parent_id": None,
                           "sub_units": [], "store_count": len(unit_stores["internet"]), "geo_store_count": 0, "lat": None, "lng": None,
                           "neighbors": [], "model_version": MODEL})

    checkpoints = [c for c in range(CHECKPOINT_START, latest, CHECKPOINT_STEP)] + [latest]
    checkpoints = sorted({c for c in checkpoints if c >= r_min + 50})

    # ── 2. 지역 통계 ────────────────────────────────────────────
    def region_stats_at(c, with_difficulty=False):
        mask = np.array([r <= c for r in valid_rounds])
        n = int(mask.sum())
        Xc = X[mask]
        k = Xc.sum(axis=0).astype(float)
        lam = reg_counts[mask].mean() if n else 0.0
        base = 1 - np.exp(-lam * share)
        raw = k / max(n, 1)
        # 시도 수준 축소 → 지역 수준 축소 (경험적 베이즈, method of moments)
        def mom_k(obs, base_, n_):
            resid = (obs - base_) ** 2 - base_ * (1 - base_) / max(n_, 1)
            tau2 = max(float(np.mean(resid)), 1e-7)
            kk = np.clip(base_ * (1 - base_) / tau2 - 1, 5, 5000)
            return kk
        sido_of = np.array([sidos.index(unit_meta[u]["sido"]) for u in unit_ids])
        s_k = np.zeros(len(sidos)); s_base = np.zeros(len(sidos))
        for si in range(len(sidos)):
            m = sido_of == si
            s_k[si] = Xc[:, m].max(axis=1).sum() if n else 0
            s_base[si] = 1 - math.exp(-lam * share[m].sum())
        s_raw = s_k / max(n, 1)
        ks = mom_k(s_raw, s_base, n)
        s_shr = (s_k + ks * s_base) / (n + ks)
        ratio = np.where(s_base > 0, s_shr / s_base, 1.0)[sido_of]
        prior = np.clip(base * ratio, 1e-6, 0.999)
        kr = mom_k(raw, prior, n)
        shr = (k + kr * prior) / (n + kr)
        recent_mask_idx = np.where(mask)[0]
        r50 = Xc[-50:].mean(axis=0) if n >= 50 else raw
        last100 = Xc[-100:]; prior_part = Xc[:-100]
        p_recent = last100.mean(axis=0) if len(last100) else raw
        p_prior = prior_part.mean(axis=0) if len(prior_part) else raw
        pooled = (last100.sum(axis=0) + prior_part.sum(axis=0)) / max(n, 1)
        se = np.sqrt(np.maximum(pooled * (1 - pooled), 1e-9) * (1 / max(len(last100), 1) + 1 / max(len(prior_part), 1)))
        trend_z = (p_recent - p_prior) / se
        rows = []
        crounds = [r for r in valid_rounds if r <= c]
        for j, u in enumerate(unit_ids):
            col = Xc[:, j]
            idx = np.where(col == 1)[0]
            last = crounds[idx[-1]] if len(idx) else None
            codes = unit_stores[u]
            fc = Counter()
            for r in crounds:
                for cd in first_by_round.get(r, []):
                    if store_info[cd]["rid"] == u:
                        fc[cd] += 1
            sc = {cd: sum(1 for rr in second_by_store_round.get(cd, []) if rr <= c) for cd in codes}
            tot = sum(fc.values())
            hhi = sum((v / tot) ** 2 for v in fc.values()) if tot else None
            top = sorted(codes, key=lambda cd: (-fc.get(cd, 0), -sc.get(cd, 0), cd))[:5]
            pm = Counter()
            for cd in fc:
                pm.update(methods_by_store.get(cd, {}))
            rows.append({"region_id": u, "model_version": MODEL, "training_end_round": c,
                         "first_wins": int(tot), "second_wins": int(sum(sc.values())), "rounds_observed": n,
                         "rounds_with_first": int(k[j]), "win_round_rate": float(raw[j]), "baseline_rate": float(base[j]),
                         "shrunk_rate": float(shr[j]), "recent50_rate": float(r50[j]), "trend_z": float(trend_z[j]),
                         "last_first_round": last, "dormant_rounds": (c - last) if last else None,
                         "top_stores": [{"code": cd, "name": store_info[cd]["name"], "first": fc.get(cd, 0), "second": sc.get(cd, 0)}
                                        for cd in top if fc.get(cd, 0) or sc.get(cd, 0)],
                         "concentration_hhi": hhi, "purchase_methods": dict(pm), "difficulty": {}})
        return rows, shr, base

    stats_rows = []
    for c in checkpoints:
        rows, _, _ = region_stats_at(c)
        stats_rows.extend(rows)
    log(f"[stats] {len(stats_rows)} rows over {len(checkpoints)} checkpoints ({time.time() - t0:.0f}s)")

    # ── 7. 예측 난이도 (최신 행에 기록) ─────────────────────────
    test_from = 1001
    ll = {m: np.zeros(U) for m in ("m0", "m1", "m2")}
    tn = 0
    cum = np.zeros(U); seen = 0
    window = []
    for i, r in enumerate(valid_rounds):
        if seen >= 100 and r >= test_from:
            lam = reg_counts[max(0, i - 100):i].mean()
            p0 = np.clip(1 - np.exp(-lam * share), 1e-6, 1 - 1e-6)
            p1 = np.clip((cum + 100 * p0) / (seen + 100), 1e-6, 1 - 1e-6)
            rec = np.array(window[-50:]).mean(axis=0) if len(window) >= 50 else cum / max(seen, 1)
            p2 = np.clip((rec * 50 + 20 * p1) / (50 + 20), 1e-6, 1 - 1e-6)
            y = X[i].astype(float)
            for key, p in (("m0", p0), ("m1", p1), ("m2", p2)):
                ll[key] += -(y * np.log(p) + (1 - y) * np.log(1 - p))
            tn += 1
        cum += X[i]; seen += 1
        window.append(X[i].astype(float))
    diff_by_unit = {}
    m1_better = 0
    for j, u in enumerate(unit_ids):
        l0, l1, l2 = (ll[k][j] / max(tn, 1) for k in ("m0", "m1", "m2"))
        best = min((l0, "m0"), (l1, "m1"), (l2, "m2"))[1]
        gain = (l0 - min(l1, l2)) / l0 if l0 > 0 else 0.0
        if l1 < l0:
            m1_better += 1
        wins_test = int(X[[i for i, r in enumerate(valid_rounds) if r >= test_from], j].sum())
        diff_by_unit[u] = {"test_from": test_from, "test_n": tn, "ll_m0": l0, "ll_m1": l1, "ll_m2": l2, "best": best,
                           "gain_vs_m0": gain, "wins_in_test": wins_test,
                           "level": "예측 가능성 낮음(무작위 기준과 차이 없음)" if gain <= 0.002 else
                                    ("부분 예측 가능(판매량 차이 반영 가능성)" if gain < 0.02 else "기준 대비 개선"),
                           "note": "m0=판매점 수 비례 무작위 기준, m1=지역 빈도 축소추정, m2=최근 50회 빈도. "
                                   "m1 이 m0 보다 낫다는 것은 지역 판매량 차이를 반영할 뿐 당첨확률 우위가 아님"}
    for row in stats_rows:
        if row["training_end_round"] == latest:
            row["difficulty"] = diff_by_unit.get(row["region_id"], {})
    log(f"[difficulty] test rounds {tn}, m1<m0 in {m1_better}/{U} regions")

    # ── 3. 전이 가설 발견·검증 ──────────────────────────────────
    vr = np.array(valid_rounds)
    hyp_rows = {}
    disc_counts = Counter()

    def pair_counts(t_idx_mask, h):
        """t ∈ mask, t+h 유효 → (n_A, k_AB matrix, marginal of B over the same t+h set)"""
        src, dst = [], []
        for i in np.where(t_idx_mask)[0]:
            r2 = valid_rounds[i] + h
            if r2 in ridx:
                src.append(i); dst.append(ridx[r2])
        if not src:
            return np.zeros(U), np.zeros((U, U)), np.zeros(U), 0
        A = X[src].astype(np.int32); B = X[dst].astype(np.int32)
        return A.sum(axis=0), A.T @ B, B.mean(axis=0), len(src)

    discovered = {}
    for c in checkpoints[:-1] if len(checkpoints) > 1 else []:
        tests = []
        train_mask = vr <= c - max(LAGS)  # t+h ≤ c 보장
        for h in LAGS:
            tmask = (vr <= c - h)
            nA, K, margB, _ = pair_counts(tmask, h)
            # marginal of B among rounds ≤ c
            pB = X[vr <= c].mean(axis=0)
            for a in np.where(nA >= MIN_N_TRAIN)[0]:
                n = int(nA[a]); ks = K[a]
                exp_up = n * pB
                for b in range(U):
                    p0 = float(pB[b])
                    if p0 <= 0:
                        continue
                    k = int(ks[b])
                    if exp_up[b] >= 3:
                        tests.append((a, b, h, "up", n, k, p0))
                    if exp_up[b] >= 8:
                        tests.append((a, b, h, "down", n, k, p0))
        if not tests:
            continue
        pv = [one_sided_p(k, n, p0, d) for (a, b, h, d, n, k, p0) in tests]
        qv = bh(pv)
        # 발견 = FDR(q<0.05) 통과 + 탐색 후보(명목 p<0.001 상위 20개, FDR 미통과 표시). 둘 다 순방향 검증으로만 판정.
        order = sorted(range(len(tests)), key=lambda i: pv[i])
        explore = {i for i in order[:20] if pv[i] < 0.001}
        fdr_n = 0
        for i, ((a, b, h, d, n, k, p0), p, q) in enumerate(zip(tests, pv, qv)):
            if q >= 0.05 and i not in explore:
                continue
            A, B = unit_ids[a], unit_ids[b]
            hid = f"tr:{A}>{B}:h{h}:{d}"
            if hid in discovered:
                continue
            kind = "self_repeat" if A == B else ("transition_up" if d == "up" else "transition_down")
            discovered[hid] = dict(kind=kind, A=A, B=B, h=h, d=d, c=c, n=n, k=k, p0=p0, p=p, q=q, fdr=bool(q < 0.05), tests=len(tests))
            disc_counts[c] += 1
            fdr_n += int(q < 0.05)
        log(f"[transition] checkpoint {c}: tests {len(tests)}, new candidates {disc_counts[c]} (FDR pass {fdr_n})")

    # 순방향 검증 (발견 체크포인트 이후)
    for hid, hd in discovered.items():
        a, b, h, c = uidx[hd["A"]], uidx[hd["B"]], hd["h"], hd["c"]
        tmask = (vr > c) & (vr <= latest - h)
        nA, K, margB, nt = pair_counts(tmask, h)
        test_n, test_k = int(nA[a]), int(K[a, b])
        test_base = float(X[vr > c].mean(axis=0)[b]) if (vr > c).any() else hd["p0"]
        st, tp = status_of(test_n, test_k, test_base, hd["d"], disc_counts[c])
        hyp_rows[hid] = {
            "hypothesis_id": hid, "model_version": MODEL, "kind": hd["kind"], "from_region": hd["A"], "to_region": hd["B"],
            "via_region": None, "store_code": None, "horizon": h, "distance_km": None, "discovered_round": c,
            "condition": {"direction": hd["d"], "rule": f"{hd['A']} 1등 발생 회차 t → t+{h} 에 {hd['B']} 1등 {'증가' if hd['d']=='up' else '감소'}"},
            "train_n": hd["n"], "train_k": hd["k"], "train_rate": hd["k"] / hd["n"], "train_base": hd["p0"],
            "train_p": hd["p"], "train_q": hd["q"],
            "test_n": test_n, "test_k": test_k, "test_rate": (test_k / test_n) if test_n else None, "test_base": test_base,
            "test_p": tp, "status": st, "live_eligible": st == "passed",
            "evidence": {"m_discovered_at_checkpoint": disc_counts[c], "alpha_test": 0.05 / max(1, disc_counts[c]),
                         "fdr_pass_train": hd["fdr"], "tests_at_checkpoint": hd["tests"],
                         "origin": "FDR 통과 발견" if hd["fdr"] else "탐색 후보(명목 p<0.001, FDR 미통과)",
                         "lift_train": (hd["k"] / hd["n"]) / hd["p0"] if hd["p0"] else None,
                         "lift_test": ((test_k / test_n) / test_base) if (test_n and test_base) else None},
            "evaluated_round": latest,
        }

    # ── 4. 복합 전이 A→B→C (증가 방향, 구성 가설이 반대 방향으로 기각되지 않은 것) ──
    ups = [hd for hd in discovered.values() if hd["d"] == "up" and hyp_rows[f"tr:{hd['A']}>{hd['B']}:h{hd['h']}:up"]["status"] != "rejected"]
    by_from = defaultdict(list)
    for hd in ups:
        by_from[hd["A"]].append(hd)
    chains = []
    for h1 in ups:
        for h2 in by_from.get(h1["B"], []):
            if h2["B"] in (h1["A"], h1["B"]):
                continue
            chains.append((h1, h2))
    chains = chains[:300]
    chain_disc = Counter()
    chain_rows = []
    for h1, h2 in chains:
        c = max(h1["c"], h2["c"])
        a, b, cc = uidx[h1["A"]], uidx[h1["B"]], uidx[h2["B"]]
        L = h1["h"] + h2["h"]

        def chain_counts(mask):
            n = k = 0
            for i in np.where(mask)[0]:
                r = valid_rounds[i]
                if X[i, a] and (r + h1["h"]) in ridx and X[ridx[r + h1["h"]], b] and (r + L) in ridx:
                    n += 1; k += int(X[ridx[r + L], cc])
            return n, k
        tr_n, tr_k = chain_counts(vr <= c - L)
        te_n, te_k = chain_counts((vr > c) & (vr <= latest - L))
        pC_tr = float(X[vr <= c].mean(axis=0)[cc]); pC_te = float(X[vr > c].mean(axis=0)[cc]) if (vr > c).any() else pC_tr
        chain_disc[c] += 1
        chain_rows.append((h1, h2, c, tr_n, tr_k, pC_tr, te_n, te_k, pC_te))
    for h1, h2, c, tr_n, tr_k, pC_tr, te_n, te_k, pC_te in chain_rows:
        st, tp = status_of(te_n, te_k, pC_te, "up", chain_disc[c], combined=True)
        hid = f"ch:{h1['A']}>{h1['B']}>{h2['B']}:h{h1['h']}+{h2['h']}"
        hyp_rows[hid] = {
            "hypothesis_id": hid, "model_version": MODEL, "kind": "chain", "from_region": h1["A"], "to_region": h2["B"],
            "via_region": h1["B"], "store_code": None, "horizon": h1["h"] + h2["h"], "distance_km": None, "discovered_round": c,
            "condition": {"direction": "up", "rule": f"{h1['A']}(t) → {h1['B']}(t+{h1['h']}) → {h2['B']}(t+{h1['h'] + h2['h']})"},
            "train_n": tr_n, "train_k": tr_k, "train_rate": (tr_k / tr_n) if tr_n else None, "train_base": pC_tr,
            "train_p": one_sided_p(tr_k, tr_n, pC_tr, "up") if tr_n else None, "train_q": None,
            "test_n": te_n, "test_k": te_k, "test_rate": (te_k / te_n) if te_n else None, "test_base": pC_te, "test_p": tp,
            "status": st, "live_eligible": st == "combined", "evidence": {"components": [f"tr:{h1['A']}>{h1['B']}:h{h1['h']}:up", f"tr:{h2['A']}>{h2['B']}:h{h2['h']}:up"]},
            "evaluated_round": latest,
        }
    log(f"[chain] evaluated {len(chain_rows)}")

    # ── 5. 거리별 전이 (원형 이동 순열) ─────────────────────────
    coords_by_round = []
    for r in valid_rounds:
        pts = [(store_info[c]["lat"], store_info[c]["lng"]) for c in first_by_round.get(r, [])
               if store_info[c]["rid"] not in (None, "internet") and valid_geo(store_info[c]["lat"], store_info[c]["lng"])]
        coords_by_round.append(np.array(pts) if pts else np.zeros((0, 2)))

    def near_counts(shift, bands):
        """각 t 에 대해: t+shift 의 당첨점 중 t 의 당첨점과 d km 이내인 수 (bands 별), 그리고 t+shift 당첨점 수"""
        out = np.zeros((R, len(bands))); tot = np.zeros(R)
        for i in range(R):
            j = (i + shift) % R
            P, Q = coords_by_round[i], coords_by_round[j]
            if len(P) == 0 or len(Q) == 0:
                continue
            d = hav_km(Q[:, None, 0], Q[:, None, 1], P[None, :, 0], P[None, :, 1]).min(axis=1)
            tot[i] = len(Q)
            for bi, b in enumerate(bands):
                out[i, bi] = (d <= b).sum()
        return out, tot

    split = 1000
    tr_idx = np.array([r <= split - 6 for r in valid_rounds]); te_idx = np.array([split < r <= latest - 6 for r in valid_rounds])
    rng = np.random.default_rng(20261011)
    null_shifts = sorted(set(int(s) for s in rng.integers(40, R - 40, size=99)))
    obs = {h: near_counts(h, DIST_BANDS) for h in LAGS}
    null = [near_counts(s, DIST_BANDS) for s in null_shifts]
    for h in LAGS:
        oc, ot = obs[h]
        for bi, b in enumerate(DIST_BANDS):
            def frac(cnt, tot, m):
                return float(cnt[m, bi].sum() / max(tot[m].sum(), 1))
            f_tr, f_te = frac(oc, ot, tr_idx), frac(oc, ot, te_idx)
            n_tr = np.array([frac(nc, nt, tr_idx) for nc, nt in null])
            n_te = np.array([frac(nc, nt, te_idx) for nc, nt in null])
            # 순열 99회의 경험적 p 는 최소 0.01 이라 Bonferroni(0.05/30)를 넘을 수 없음 → 귀무분포 z 근사
            z_tr = (f_tr - n_tr.mean()) / max(n_tr.std(ddof=1), 1e-9)
            z_te = (f_te - n_te.mean()) / max(n_te.std(ddof=1), 1e-9)
            p_tr = float(1 - 0.5 * (1 + math.erf(z_tr / math.sqrt(2))))
            p_te = float(1 - 0.5 * (1 + math.erf(z_te / math.sqrt(2))))
            base_tr, base_te = float(n_tr.mean()), float(n_te.mean())
            disc = p_tr < 0.05 / (len(LAGS) * len(DIST_BANDS))
            if disc:
                st = "passed" if (p_te < 0.05 and f_te > base_te) else ("weakened" if f_te > base_te else "rejected")
            else:
                # 발견 기준 미달 탐색 후보: 순방향 결과로만 표시 (통과 불가)
                st = "weakened" if f_te > base_te else "rejected"
            hid = f"dist:h{h}:{b}km"
            hyp_rows[hid] = {
                "hypothesis_id": hid, "model_version": MODEL, "kind": "distance_band", "from_region": None, "to_region": None,
                "via_region": None, "store_code": None, "horizon": h, "distance_km": b, "discovered_round": split,
                "condition": {"rule": f"t 회차 1등 판매점 {b}km 이내에서 t+{h} 회차 1등 발생 비율", "null": f"원형 이동 순열 {len(null_shifts)}회",
                              "train_rounds": f"~{split}", "test_rounds": f"{split + 1}~{latest}"},
                "train_n": int(ot[tr_idx].sum()), "train_k": int(oc[tr_idx, bi].sum()), "train_rate": f_tr, "train_base": base_tr,
                "train_p": p_tr, "train_q": None, "test_n": int(ot[te_idx].sum()), "test_k": int(oc[te_idx, bi].sum()),
                "test_rate": f_te, "test_base": base_te, "test_p": p_te, "status": st, "live_eligible": st == "passed",
                "evidence": {"discovered_in_train": bool(disc), "alpha_train": 0.05 / (len(LAGS) * len(DIST_BANDS)),
                             "z_train": float(z_tr), "z_test": float(z_te), "null_shifts": len(null_shifts),
                             "note": "원형 이동은 공간 분포는 보존하고 시간 연관만 깨므로, 시기별 판매점 분포 변화(비정상성)가 남아 있으면 기준이 편향될 수 있음"},
                "evaluated_round": latest,
            }
    log(f"[distance] done ({time.time() - t0:.0f}s)")

    # ── 6. 판매점 주기·유명/신흥 ─────────────────────────────────
    first_rounds_by_store = defaultdict(list)
    for r in valid_rounds:
        for cd in first_by_round.get(r, []):
            first_rounds_by_store[cd].append(r)
    cycle_rows = []
    span_start = valid_rounds[0]
    for cd, rs in first_rounds_by_store.items():
        info = store_info[cd]
        if info["rid"] in (None, "internet"):
            continue
        rs = sorted(rs)
        recent100 = sum(1 for r in rs if r > latest - 100)
        prior_n = max(1, (latest - 100) - span_start + 1)
        prior_k = sum(1 for r in rs if r <= latest - 100)
        prior_rate, recent_rate = prior_k / prior_n, recent100 / 100
        em_p = float(poisson.sf(recent100 - 1, max(prior_rate * 100, 1e-6))) if recent100 > 0 else 1.0
        gaps = np.diff(rs) if len(rs) >= 2 else np.array([])
        cls = "famous" if len(rs) >= 5 else ("emerging" if recent100 >= 2 and em_p < 0.01 else ("regular" if len(rs) >= 2 else "sparse"))
        if len(rs) < 2 and recent100 == 0 and second_by_store.get(cd, 0) == 0:
            continue
        cycle_rows.append({
            "store_code": cd, "model_version": MODEL, "training_end_round": latest, "store_name": info["name"], "region_id": info["rid"],
            "lat": info["lat"], "lng": info["lng"], "first_count": len(rs), "second_count": int(second_by_store.get(cd, 0)),
            "first_rounds": rs[-30:],
            "gap_mean": float(gaps.mean()) if len(gaps) else None, "gap_median": float(np.median(gaps)) if len(gaps) else None,
            "gap_var": float(gaps.var()) if len(gaps) else None,
            "gap_cv": float(gaps.std() / gaps.mean()) if len(gaps) >= 2 and gaps.mean() > 0 else None,
            "rounds_since_last": latest - rs[-1], "recent100_first": recent100, "prior_rate": prior_rate, "recent_rate": recent_rate,
            "emerging_p": em_p, "class": cls, "purchase_methods": dict(methods_by_store.get(cd, {})),
        })
    log(f"[stores] cycle rows {len(cycle_rows)} (famous {sum(1 for r in cycle_rows if r['class']=='famous')}, "
        f"emerging {sum(1 for r in cycle_rows if r['class']=='emerging')})")

    # 주기성·신흥 지속성·휴면 반등 — 체크포인트별 집계 가설 (순방향)
    # 같은 검정을 체크포인트마다 반복하므로 체크포인트 수로 Bonferroni 보정
    m_cp = max(1, len(checkpoints) - 1)
    for c in checkpoints[:-1]:
        # (a) 주기 창 예측: 4회 이상 당첨 판매점, 다음 당첨이 [last+mean-sd/2, last+mean+sd/2] 창에 오는가
        n = k = 0; expct = 0.0
        for cd, rs in first_rounds_by_store.items():
            past = [r for r in rs if r <= c]
            if len(past) < 4 or store_info[cd]["rid"] in (None, "internet"):
                continue
            g = np.diff(past)
            lo, hi = past[-1] + g.mean() - g.std() / 2, past[-1] + g.mean() + g.std() / 2
            lo, hi = max(lo, c + 1), min(hi, latest)
            if hi < lo:
                continue
            rate = len(past) / max(1, c - span_start + 1)
            wlen = int(hi) - int(math.ceil(lo)) + 1
            if wlen <= 0:
                continue
            n += 1
            expct += 1 - (1 - rate) ** wlen
            k += int(any(lo <= r <= hi for r in rs if r > c))
        if n:
            base = expct / n
            st, tp = status_of(n, k, base, "up", m_cp)
            hid = f"cycle:c{c}"
            hyp_rows[hid] = {"hypothesis_id": hid, "model_version": MODEL, "kind": "store_cycle", "from_region": None, "to_region": None,
                             "via_region": None, "store_code": None, "horizon": None, "distance_km": None, "discovered_round": c,
                             "condition": {"rule": "4회 이상 1등 판매점의 다음 1등이 '마지막+평균간격±표준편차/2' 창에 온다", "stores": n},
                             "train_n": None, "train_k": None, "train_rate": None, "train_base": None, "train_p": None, "train_q": None,
                             "test_n": n, "test_k": k, "test_rate": k / n, "test_base": base, "test_p": tp, "status": st,
                             "live_eligible": False, "evidence": {"note": "판매량 미보정 — 통과해도 판매점 한 장당 확률 우위 아님"},
                             "evaluated_round": latest}
        # (b) 신흥 지속성: c 기준 최근 100회 신흥 판매점이 c 이후에도 '과거 평균'보다 자주 당첨되는가
        #     개업일 미확보 → 과거 평균은 첫 1등 이후 구간으로 계산(개업 전 기간 포함 시 기준이 0으로 왜곡됨).
        #     첫 1등이 최근 100회 안이면 같은 지역 판매점 평균 당첨률을 기준으로 사용.
        cidx_c = [i for i, r in enumerate(valid_rounds) if r <= c]
        reg_store_rate = {}
        for j, u in enumerate(unit_ids):
            reg_store_rate[u] = X[cidx_c, j].sum() / max(1, len(cidx_c)) / max(1, len(unit_stores[u]))
        exp_prior = 0.0; k2 = 0; n2 = 0
        for cd, rs in first_rounds_by_store.items():
            past = [r for r in rs if r <= c]
            rid = store_info[cd]["rid"]
            if not past or rid in (None, "internet"):
                continue
            rec = sum(1 for r in past if r > c - 100)
            pre = [r for r in past if r <= c - 100]
            if pre:
                pr_n = max(1, (c - 100) - pre[0] + 1)
                pr_rate = len(pre) / pr_n
            else:
                pr_rate = reg_store_rate.get(rid, 0.0)
            if rec >= 2 and poisson.sf(rec - 1, max(pr_rate * 100, 1e-6)) < 0.01:
                horizon = latest - c
                n2 += 1
                exp_prior += pr_rate * horizon
                k2 += sum(1 for r in rs if r > c)
        if n2:
            p_up = float(poisson.sf(k2 - 1, max(exp_prior, 1e-6)))
            st = "researching" if exp_prior < 5 else ("passed" if p_up < 0.05 / m_cp else ("weakened" if k2 > exp_prior else "rejected"))
            hid = f"emerging:c{c}"
            hyp_rows[hid] = {"hypothesis_id": hid, "model_version": MODEL, "kind": "emerging_store", "from_region": None, "to_region": None,
                             "via_region": None, "store_code": None, "horizon": None, "distance_km": None, "discovered_round": c,
                             "condition": {"rule": "최근 100회 급증(포아송 p<0.01) 판매점이 이후에도 과거 평균보다 자주 당첨", "stores": n2},
                             "train_n": None, "train_k": None, "train_rate": None, "train_base": None, "train_p": None, "train_q": None,
                             "test_n": n2, "test_k": k2, "test_rate": None, "test_base": exp_prior, "test_p": p_up, "status": st,
                             "live_eligible": False, "evidence": {"expected_wins_prior_rate": exp_prior, "observed_wins": k2,
                                                                  "note": "판매량 미보정 — 신흥은 판매량 증가로 설명될 수 있음"},
                             "evaluated_round": latest}
        # (c) 휴면 반등: c 시점 52회 이상 1등 없던 지역이 다음 10회 안에 1등 → 지역 축소추정 기대 대비
        _, shr_c, _ = region_stats_at(c)
        cidx = np.where(vr <= c)[0]
        n3 = k3 = 0; e3 = 0.0
        if len(cidx) >= 60:
            last_seen = {}
            for j in range(U):
                hits = np.where(X[cidx, j] == 1)[0]
                last_seen[j] = valid_rounds[cidx[hits[-1]]] if len(hits) else None
            fut = [i for i, r in enumerate(valid_rounds) if c < r <= c + 10]
            if len(fut) == 10:
                for j in range(U):
                    ls = last_seen[j]
                    if ls is None or c - ls < 52:
                        continue
                    n3 += 1
                    e3 += 1 - (1 - shr_c[j]) ** 10
                    k3 += int(X[fut, j].max())
        if n3 >= 5:
            st, tp = status_of(n3, k3, e3 / n3, "up", m_cp)
            hid = f"dormant:c{c}"
            hyp_rows[hid] = {"hypothesis_id": hid, "model_version": MODEL, "kind": "dormant_rebound", "from_region": None, "to_region": None,
                             "via_region": None, "store_code": None, "horizon": 10, "distance_km": None, "discovered_round": c,
                             "condition": {"rule": "52회 이상 1등 없던 지역이 다음 10회 안에 1등 (지역 기대보다 많은가 = 도박사의 오류 검정)", "regions": n3},
                             "train_n": None, "train_k": None, "train_rate": None, "train_base": None, "train_p": None, "train_q": None,
                             "test_n": n3, "test_k": k3, "test_rate": k3 / n3, "test_base": e3 / n3, "test_p": tp, "status": st,
                             "live_eligible": False, "evidence": {}, "evaluated_round": latest}

    hyps = list(hyp_rows.values())
    sc = Counter(h["status"] for h in hyps); kc = Counter(h["kind"] for h in hyps)
    tr_tested = [h for h in hyps if h["kind"] in ("transition_up", "transition_down", "self_repeat") and (h["test_n"] or 0) >= 20]
    same_dir = sum(1 for h in tr_tested if (h["test_rate"] - h["test_base"]) * (1 if h["condition"]["direction"] == "up" else -1) > 0)
    summary = {
        "model_version": MODEL, "latest_round": latest, "rounds_range": [r_min, latest], "valid_rounds": len(valid_rounds),
        "missing_rounds": len(missing_rounds), "units": U, "sidos": len(sidos), "stores_total": len(stores),
        "stores_unparsed": unparsed, "winners_unknown_store": unknown_winners, "winners_internet": internet_winners,
        "checkpoints": checkpoints, "hypotheses": len(hyps), "by_status": dict(sc), "by_kind": dict(kc),
        "transition_replication": {"tested_n20": len(tr_tested), "same_direction": same_dir,
                                   "same_direction_rate": (same_dir / len(tr_tested)) if tr_tested else None,
                                   "null_expectation": 0.5,
                                   "note": "발견 가설이 순방향에서 같은 방향으로 나타난 비율. 귀무가설(연관 없음)이면 약 50%"},
        "difficulty": {"test_rounds": tn, "m1_better_than_m0": m1_better, "units": U},
        "store_classes": dict(Counter(r["class"] for r in cycle_rows)),
        "elapsed_s": round(time.time() - t0, 1),
    }
    return {"units": units_rows, "stats": stats_rows, "hypotheses": hyps, "cycles": cycle_rows, "summary": summary}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out", default=None)
    ap.add_argument("--latest", type=int, default=None, help="연구 마지막 회차 상한 (기본: DB 최신)")
    ap.add_argument("--runner", default=os.getenv("RESEARCH_RUNNER", "local"))
    a = ap.parse_args()
    url, key = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY")
    if not url or not key:
        log("SUPABASE_URL / SUPABASE_KEY 환경변수가 필요합니다"); sys.exit(1)
    db = Db(url, key)
    tables_ok = all(db.exists(t) for t in ("research_region_units", "research_region_stats", "research_region_hypotheses",
                                           "research_store_cycles", "research_region_runs"))
    if not tables_ok and not a.dry_run:
        log("[error] research_v4_regions.sql 미적용 — 테이블이 없습니다. --dry-run 으로만 실행 가능"); sys.exit(2)

    latest = max(r["round"] for r in db.select_all("lotto_winning_numbers", {"select": "round"}))
    if a.latest:
        latest = min(latest, a.latest)
    if tables_ok and not a.force and not a.dry_run:
        done = db.select_all("research_region_runs", {"select": "status", "model_version": f"eq.{MODEL}",
                                                      "training_end_round": f"eq.{latest}"})
        if any(d["status"] == "completed" for d in done):
            print(json.dumps({"skipped": True, "reason": f"{latest}회 이미 완료"})); return
    if tables_ok and not a.dry_run:
        db.upsert("research_region_runs", [{"model_version": MODEL, "training_end_round": latest, "status": "running",
                                            "runner": a.runner, "started_at": datetime.now(timezone.utc).isoformat(),
                                            "completed_at": None, "error": None}], "model_version,training_end_round")
    try:
        res = run(db, latest_override=latest)
    except Exception as e:
        if tables_ok and not a.dry_run:
            db.upsert("research_region_runs", [{"model_version": MODEL, "training_end_round": latest, "status": "failed",
                                                "runner": a.runner, "error": str(e)[:500],
                                                "completed_at": datetime.now(timezone.utc).isoformat()}], "model_version,training_end_round")
        raise
    res = clean(res)
    if a.out:
        json.dump(res, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, default=_json_default)
    if not a.dry_run:
        log("[write] units"); db.upsert("research_region_units", res["units"], "region_id")
        log("[write] stats"); db.upsert("research_region_stats", res["stats"], "region_id,model_version,training_end_round", ignore_duplicates=True)
        log("[write] hypotheses"); db.upsert("research_region_hypotheses", res["hypotheses"], "hypothesis_id,model_version")
        log("[write] cycles"); db.upsert("research_store_cycles", res["cycles"], "store_code,model_version,training_end_round")
        db.upsert("research_results", [{"research_type": "region_research", "model_version": MODEL,
                                        "training_end_round": latest, "target_round": 0, "payload": res["summary"]}],
                  "research_type,model_version,training_end_round,target_round")
        db.upsert("research_region_runs", [{"model_version": MODEL, "training_end_round": latest, "status": "completed",
                                            "runner": a.runner, "stats": res["summary"], "error": None,
                                            "completed_at": datetime.now(timezone.utc).isoformat()}], "model_version,training_end_round")
    print(json.dumps(res["summary"], ensure_ascii=False))


if __name__ == "__main__":
    main()
