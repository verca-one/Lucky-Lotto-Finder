/**
 * test-dhlottery-access
 * 당첨 판매점 API 접근 테스트 (당첨번호 API와 완전 분리)
 * - 로또: selectLtWnShp.do (1232회, 1등/2등)
 * - 연금: selectPtWnShp.do (323회)
 */

const BASE = "https://www.dhlottery.co.kr/wnprchsplcsrch";

const HEADERS: Record<string, string> = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
  Accept: "application/json, text/javascript, */*; q=0.01",
  "Accept-Language": "ko-KR,ko;q=0.9",
  "X-Requested-With": "XMLHttpRequest",
  Referer: "https://www.dhlottery.co.kr/wnprchsplcsrch/selectWnPrchsPlcList.do",
  "Cache-Control": "no-cache",
};

async function testEndpoint(
  label: string,
  url: string,
  params: Record<string, string>
): Promise<Record<string, unknown>> {
  const qs = new URLSearchParams(params).toString();
  const fullUrl = `${url}?${qs}`;
  const result: Record<string, unknown> = {
    label,
    url: fullUrl,
    params,
    status: null,
    finalUrl: null,
    contentType: null,
    responseLength: null,
    isJson: false,
    storeCount: 0,
    sampleNames: [],
    sampleAddresses: [],
    error: null,
    rawPreview: null,
  };

  try {
    const res = await fetch(fullUrl, { headers: HEADERS, redirect: "follow" });
    const body = await res.text();

    result.status = res.status;
    result.finalUrl = res.url;
    result.contentType = res.headers.get("content-type") ?? "";
    result.responseLength = new TextEncoder().encode(body).length;
    result.rawPreview = body.slice(0, 400).replace(/\s+/g, " ").trim();

    // JSON 파싱 시도
    try {
      const json = JSON.parse(body);
      result.isJson = true;
      const list: unknown[] = json?.data?.list ?? json?.list ?? [];
      result.storeCount = list.length;
      result.sampleNames = list.slice(0, 3).map((s: unknown) => (s as Record<string,string>).shpNm ?? (s as Record<string,string>).shpNmDtl ?? "");
      result.sampleAddresses = list.slice(0, 3).map((s: unknown) => (s as Record<string,string>).shpAddr ?? (s as Record<string,string>).rdnmadr ?? "");
      result.fullStructureKeys = list[0] ? Object.keys(list[0] as object) : [];
    } catch {
      result.isJson = false;
    }
  } catch (e) {
    result.error = e instanceof Error ? e.message : String(e);
  }

  return result;
}

Deno.serve(async (_req: Request) => {
  const LOTTO_ROUND = 1232;
  const PENSION_ROUND = 323;

  const [lotto1, lotto2, pension] = await Promise.all([
    testEndpoint("로또 1232회 1등", `${BASE}/selectLtWnShp.do`, {
      srchWnShpRnk: "1",
      srchLtEpsd: String(LOTTO_ROUND),
      srchShpLctn: "",
    }),
    testEndpoint("로또 1232회 2등", `${BASE}/selectLtWnShp.do`, {
      srchWnShpRnk: "2",
      srchLtEpsd: String(LOTTO_ROUND),
      srchShpLctn: "",
    }),
    testEndpoint("연금복권 323회 전체", `${BASE}/selectPtWnShp.do`, {
      srchWnShpRnk: "all",
      srchLtEpsd: String(PENSION_ROUND),
      srchShpLctn: "",
    }),
  ]);

  // "all" 파라미터도 테스트 (로또)
  const lottoAll = await testEndpoint("로또 1232회 전체(all)", `${BASE}/selectLtWnShp.do`, {
    srchWnShpRnk: "all",
    srchLtEpsd: String(LOTTO_ROUND),
    srchShpLctn: "",
  });

  const summary = {
    테스트일시: new Date().toISOString(),
    results: {
      lotto_rank1: lotto1,
      lotto_rank2: lotto2,
      lotto_all: lottoAll,
      pension_all: pension,
    },
  };

  return new Response(JSON.stringify(summary, null, 2), {
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
});
