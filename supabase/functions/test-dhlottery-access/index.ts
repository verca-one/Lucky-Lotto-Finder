/**
 * test-dhlottery-access
 * Supabase Edge Function — 동행복권 접속 가능 여부 최소 테스트
 * 크롤링/파싱/DB 저장 없음. 단순 HTTP 접속 결과만 반환.
 */
import { DOMParser } from "https://deno.land/x/deno_dom@v0.1.45/deno-dom-wasm.ts";

const TARGET_URL =
  "https://www.dhlottery.co.kr/gameResult.do?method=byWin&drwNo=1232";

const REQUEST_HEADERS: Record<string, string> = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36",
  Accept:
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
  "Cache-Control": "no-cache",
  Pragma: "no-cache",
  Connection: "keep-alive",
  "Upgrade-Insecure-Requests": "1",
};

Deno.serve(async (_req: Request) => {
  const result: Record<string, unknown> = {
    success: false,
    requestedUrl: TARGET_URL,
    status: null,
    finalUrl: null,
    contentType: null,
    responseLength: null,
    isErrorPage: null,
    hasBall645: null,
    hasWinResult: null,
    preview: null,
    error: null,
  };

  try {
    const response = await fetch(TARGET_URL, {
      headers: REQUEST_HEADERS,
      redirect: "follow",
    });

    const finalUrl = response.url;
    const contentType = response.headers.get("content-type") ?? "";
    const body = await response.text();
    const bodyLen = new TextEncoder().encode(body).length;

    result.status = response.status;
    result.finalUrl = finalUrl;
    result.contentType = contentType;
    result.responseLength = bodyLen;
    result.preview = body.slice(0, 500).replace(/\s+/g, " ").trim();

    // errorPage 감지
    const isErrorPage =
      finalUrl.includes("errorPage") ||
      body.includes("errorPage") ||
      body.toLowerCase().includes("access denied") ||
      body.toLowerCase().includes("접근 제한") ||
      body.toLowerCase().includes("로그인이 필요");
    result.isErrorPage = isErrorPage;

    // HTML 파싱으로 ball_645 / win_result 확인
    if (contentType.includes("html")) {
      const doc = new DOMParser().parseFromString(body, "text/html");
      const balls = doc?.querySelectorAll(".ball_645") ?? [];
      const winResult = doc?.querySelector(".win_result");

      // 숫자인 ball 개수
      let numericBalls = 0;
      for (const el of balls) {
        if (/^\d+$/.test(el.textContent?.trim() ?? "")) numericBalls++;
      }

      result.hasBall645 = numericBalls >= 7;
      result.hasWinResult = winResult !== null;
      result.ballCount = numericBalls;
    } else {
      result.hasBall645 = false;
      result.hasWinResult = false;
    }

    // 최종 성공 판단
    result.success =
      response.status === 200 &&
      !isErrorPage &&
      result.hasBall645 === true;

  } catch (e) {
    result.error = e instanceof Error ? e.message : String(e);
    result.success = false;
  }

  return new Response(JSON.stringify(result, null, 2), {
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
});
