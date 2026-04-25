import type { NextApiRequest, NextApiResponse } from "next";
import { db } from "@/lib/firebase";
import { collection, addDoc, query, where, getDocs, writeBatch } from "firebase/firestore";

interface StoreData {
  lottery_type: string;
  round: number;
  rank: number;
  store_name: string;
  address: string;
  method: string;
  region: string;
  crawled_at: string;
}

// 당첨지점 크롤링 (Mock 데이터 - 실제로는 Python 스크립트 호출)
async function crawlStoresByRound(round: number): Promise<StoreData[]> {
  // 실제 구현: Python 스크립트 호출 또는 API 연동
  // 여기서는 저장된 당첨지점 데이터 중 해당 회차만 필터링

  const stores: StoreData[] = [];

  // 예시: 당첨지점 데이터 (실제로는 stores 컬렉션에서 조회)
  // 향후: Python 크롤링 스크립트 호출로 대체

  return stores;
}

export default async function handler(
  req: NextApiRequest,
  res: NextApiResponse
) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { round } = req.body;

  if (!round || isNaN(round)) {
    return res.status(400).json({ error: "Invalid round number" });
  }

  try {
    console.log(`📊 크롤링 시작: ${round}회`);

    // 저장된 stores 컬렉션에서 해당 회차의 1등, 2등만 조회
    const storesRef = collection(db, "stores");
    const q = query(
      storesRef,
      where("round", "==", round),
      where("rank", "in", [1, 2])
    );

    const querySnapshot = await getDocs(q);
    const stores: StoreData[] = [];

    querySnapshot.forEach((doc) => {
      stores.push(doc.data() as StoreData);
    });

    console.log(`✅ ${stores.length}개 당첨지점 발견`);

    // 응답
    return res.status(200).json({
      success: true,
      count: stores.length,
      stores: stores,
    });
  } catch (error) {
    console.error("❌ 크롤링 실패:", error);
    return res.status(500).json({
      error: "Failed to crawl stores",
      details: error instanceof Error ? error.message : "Unknown error",
    });
  }
}
