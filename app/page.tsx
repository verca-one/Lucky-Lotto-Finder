"use client";

import React, { useEffect, useState } from "react";
import { db } from "@/lib/firebase";
import { collection, getDocs, doc, getDoc, addDoc, setDoc } from "firebase/firestore";
import { useRouter } from "next/navigation";

interface WinHistory {
  round: number;
  lottery_type: string;
  numbers?: number[];
  bonus?: number;
  store_id?: string;
  crawled_at?: string;
  rank?: number;
}

interface Store {
  store_id: string;
  store_name: string;
  address: string;
  method?: string;
  lotto_wins?: number[];
  lotto_2nd_wins?: number[];
  pension_wins?: number[];
  speeto_wins?: number[];
}

export default function HomePage() {
  const [activeTab, setActiveTab] = useState<"lotto" | "pension" | "speeto">("lotto");
  const [lottoRound, setLottoRound] = useState<number | null>(null);
  const [lottoNumbers, setLottoNumbers] = useState<number[]>([]);
  const [lottoBonus, setLottoBonus] = useState<number | number[] | null>(null);
  const [pensionWinners, setPensionWinners] = useState<Record<string, { group: string; balls: number[] }> | null>(null);
  const [winStores, setWinStores] = useState<(Store & { draw_date?: string })[]>([]);
  const [rank2Stores, setRank2Stores] = useState<(Store & { draw_date?: string })[]>([]);
  const [selectedStore, setSelectedStore] = useState<(Store & { draw_date?: string }) | null>(null);
  const [adminDate, setAdminDate] = useState<string | null>(null);
  const [showReportModal, setShowReportModal] = useState(false);
  const [reportReasons, setReportReasons] = useState<string[]>([]);
  const [reportSubmitting, setReportSubmitting] = useState(false);
  const [storeRatings, setStoreRatings] = useState<Record<string, Record<string, 'like' | 'dislike'>>>({});
  const [ratingCounts, setRatingCounts] = useState<Record<string, Record<string, { like: number; dislike: number }>>>({});
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    const fetchData = async () => {
      try {
        // 1. 최신 기록 조회 (관리자 페이지에서 입력한 데이터)
        const { query, orderBy } = await import("firebase/firestore");
        const q = query(collection(db, "lotto_records"), orderBy("round", "desc"));
        const recordsSnapshot = await getDocs(q);

        if (!recordsSnapshot.empty) {
          // 해당 탭의 최신 기록 찾기
          const latestRecord = recordsSnapshot.docs.find(
            (doc) => (doc.data().lottery_type || "lotto") === activeTab
          );

          if (latestRecord) {
            const data = latestRecord.data();
            setLottoRound(data.round);

            // 연금복권인 경우
            if (activeTab === "pension") {
              setPensionWinners(data.winners || null);
              setLottoNumbers([]);
              setLottoBonus(null);
            } else {
              setLottoNumbers(data.numbers || []);
              setLottoBonus(data.bonus || null);
              setPensionWinners(null);
            }

            setAdminDate(data.date);

            // 2. 해당 라운드의 당첨지점 조회
            const historySnapshot = await getDocs(collection(db, "win_history"));
            const histories = historySnapshot.docs.map((doc) => doc.data() as WinHistory);

            const storesSnapshot = await getDocs(collection(db, "stores"));
            const storesMap = new Map(storesSnapshot.docs.map((doc) => [doc.id, doc.data() as Store]));

            // 1등 (rank가 없거나 rank=1)
            const rank1Histories = histories.filter(
              (h) => h.lottery_type === activeTab && h.round === data.round && (!h.rank || h.rank === 1)
            );
            const roundWinStores = rank1Histories
              .map((h) => storesMap.get(h.store_id!))
              .filter((store) => store !== undefined) as (Store & { draw_date?: string })[];

            // 2등 (rank=2)
            const rank2Histories = histories.filter(
              (h) => h.lottery_type === activeTab && h.round === data.round && h.rank === 2
            );
            const rank2StoresList = rank2Histories
              .map((h) => storesMap.get(h.store_id!))
              .filter((store) => store !== undefined) as (Store & { draw_date?: string })[];

            setWinStores(roundWinStores);
            setRank2Stores(rank2StoresList);
          } else {
            setLottoRound(null);
            setLottoNumbers([]);
            setLottoBonus(null);
            setAdminDate(null);
            setWinStores([]);
            setRank2Stores([]);
          }

          // 평가 데이터 로드
          const ratingsSnapshot = await getDocs(collection(db, "ratings"));
          const ratingsData: Record<string, Record<string, { like: number; dislike: number }>> = {};
          ratingsSnapshot.docs.forEach((doc) => {
            ratingsData[doc.id] = doc.data() as Record<string, { like: number; dislike: number }>;
          });
          setRatingCounts(ratingsData);
        }
      } catch (error) {
        console.error("데이터 로드 실패:", error);
      }

      setLoading(false);
    };

    fetchData();
  }, [activeTab]);

  const getNumberColor = (num: number) => {
    if (num >= 1 && num <= 10) return "bg-yellow-400";
    if (num >= 11 && num <= 20) return "bg-blue-400";
    if (num >= 21 && num <= 30) return "bg-red-400";
    if (num >= 31 && num <= 45) return "bg-gray-400";
    return "bg-yellow-400";
  };

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    const year = date.getFullYear();
    const month = date.getMonth() + 1;
    const day = date.getDate();
    return `${year}년 ${month}월 ${day}일`;
  };

  const calculateLottoDate = (round: number) => {
    // 로또 1회: 1992년 11월 7일 (토요일)
    const baseDate = new Date('1992-11-07');
    const days = (round - 1) * 7;
    baseDate.setDate(baseDate.getDate() + days);
    const year = baseDate.getFullYear();
    const month = baseDate.getMonth() + 1;
    const day = baseDate.getDate();
    return `${year}년 ${month}월 ${day}일`;
  };

  const handleRating = async (storeId: string, category: string, type: 'like' | 'dislike') => {
    const currentRating = storeRatings[storeId]?.[category];
    const isToggleOff = currentRating === type;

    setStoreRatings((prev) => ({
      ...prev,
      [storeId]: {
        ...prev[storeId],
        [category]: isToggleOff ? undefined : type,
      },
    }));

    setRatingCounts((prev) => {
      const current = prev[storeId]?.[category] || { like: 0, dislike: 0 };
      const newCounts = { ...current };

      if (isToggleOff) {
        newCounts[type]--;
      } else {
        if (currentRating) {
          newCounts[currentRating]--;
        }
        newCounts[type]++;
      }

      return {
        ...prev,
        [storeId]: {
          ...prev[storeId],
          [category]: newCounts,
        },
      };
    });

    // Firestore에 저장
    try {
      const ratingRef = doc(db, "ratings", storeId);
      const ratingDoc = await getDoc(ratingRef);
      const existingData = ratingDoc.exists() ? ratingDoc.data() : {};

      const current = existingData[category] || { like: 0, dislike: 0 };
      const newCounts = { ...current };

      if (isToggleOff) {
        newCounts[type]--;
      } else {
        if (currentRating) {
          newCounts[currentRating]--;
        }
        newCounts[type]++;
      }

      await setDoc(
        ratingRef,
        {
          [category]: newCounts,
        },
        { merge: true }
      );
    } catch (error) {
      console.error("평가 저장 실패:", error);
    }
  };

  const handleReportSubmit = async () => {
    if (reportReasons.length === 0 || !selectedStore) {
      alert("신고 항목을 선택해주세요");
      return;
    }

    setReportSubmitting(true);
    try {
      await addDoc(collection(db, "reports"), {
        store_id: selectedStore.store_id,
        store_name: selectedStore.store_name,
        address: selectedStore.address,
        content: reportReasons.join(", "),
        createdAt: new Date(),
      });
      alert("신고가 접수되었습니다");
      setReportReasons([]);
      setShowReportModal(false);
    } catch (error) {
      console.error("신고 실패:", error);
      alert("신고 접수에 실패했습니다");
    } finally {
      setReportSubmitting(false);
    }
  };

  if (loading) return <div className="p-8 text-center">로딩 중...</div>;

  return (
    <div className="bg-gradient-to-br from-blue-50 to-indigo-100 p-6 min-h-screen">
      {/* 탭 메뉴 */}
      <div className="flex gap-4 mb-8 border-b-2 border-gray-200">
        <button
          onClick={() => setActiveTab("lotto")}
          className={`font-bold py-3 px-6 transition ${
            activeTab === "lotto"
              ? "border-b-4 border-yellow-400 text-yellow-600"
              : "text-gray-600 hover:text-gray-800"
          }`}
        >
          로또
        </button>
        <button
          onClick={() => setActiveTab("pension")}
          className={`font-bold py-3 px-6 transition ${
            activeTab === "pension"
              ? "border-b-4 border-blue-400 text-blue-600"
              : "text-gray-600 hover:text-gray-800"
          }`}
        >
          연금복권
        </button>
        <button
          onClick={() => setActiveTab("speeto")}
          className={`font-bold py-3 px-6 transition ${
            activeTab === "speeto"
              ? "border-b-4 border-purple-400 text-purple-600"
              : "text-gray-600 hover:text-gray-800"
          }`}
        >
          스피또
        </button>
      </div>

      {/* 당첨번호 */}
      {lottoRound && (
        <div className="bg-white rounded-xl shadow-lg p-6 mb-8">
          <div className="text-center mb-8 space-y-3">
            <h2 className="text-4xl font-bold">
              {activeTab === "lotto" && `로또 ${lottoRound}회`}
              {activeTab === "pension" && `연금복권 ${lottoRound}회`}
              {activeTab === "speeto" && `스피또 ${lottoRound}회`}
            </h2>
            <p className="text-lg text-gray-600">
              ({adminDate ? formatDate(adminDate) : (lottoRound ? calculateLottoDate(lottoRound) : "날짜 정보 없음")})
            </p>
          </div>

          {/* 로또 & 스피또 */}
          {activeTab !== "pension" && (
            <div className="flex justify-center gap-3 flex-wrap">
              {lottoNumbers.map((num, index) => (
                <span
                  key={`lotto-${index}`}
                  className={`${getNumberColor(num)} text-white rounded-full w-16 h-16 flex items-center justify-center font-bold text-2xl`}
                >
                  {num}
                </span>
              ))}
              {lottoBonus && (
                <>
                  <span className="text-gray-400 flex items-center">+</span>
                  <span className="bg-green-500 text-white rounded-full w-16 h-16 flex items-center justify-center font-bold text-2xl">
                    {lottoBonus}
                  </span>
                </>
              )}
            </div>
          )}

          {/* 연금복권 */}
          {activeTab === "pension" && pensionWinners && (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <tbody>
                  {["1등", "2등", "3등", "4등", "5등", "6등", "7등"].map((rank) => (
                    pensionWinners[rank] && (
                      <tr key={rank} className={`border-b ${rank === "1등" ? "bg-blue-50" : "bg-yellow-50"}`}>
                        <td className="p-3 text-center">
                          <span className={`inline-block px-2 py-1 rounded text-xs font-bold ${
                            rank === "1등"
                              ? "bg-blue-200 text-blue-800"
                              : "bg-yellow-200 text-yellow-800"
                          }`}>
                            {rank}
                          </span>
                        </td>
                        <td className="p-3 text-center">
                          <span className={`text-xs font-bold ${
                            rank === "1등" ? "text-blue-700" : "text-gray-700"
                          }`}>
                            {pensionWinners[rank].group}
                          </span>
                        </td>
                        <td className="p-3">
                          <div className="flex gap-1 flex-wrap justify-center">
                            {pensionWinners[rank].balls && pensionWinners[rank].balls.map((num, idx) => (
                              <span
                                key={idx}
                                className={`text-white rounded-full w-7 h-7 flex items-center justify-center font-bold text-xs ${
                                  rank === "1등" ? "bg-blue-600" : "bg-yellow-400 text-gray-800"
                                }`}
                              >
                                {num}
                              </span>
                            ))}
                          </div>
                        </td>
                      </tr>
                    )
                  ))}
                  {/* 보너스 */}
                  {lottoBonus && (
                    <tr className="bg-green-50 border-b">
                      <td className="p-3 text-center">
                        <span className="inline-block px-2 py-1 rounded text-xs font-bold bg-green-200 text-green-800">
                          보너스
                        </span>
                      </td>
                      <td className="p-3 text-center">
                        <span className="text-xs font-bold text-gray-700">각조</span>
                      </td>
                      <td className="p-3">
                        <div className="flex gap-1 flex-wrap justify-center">
                          {Array.isArray(lottoBonus) && lottoBonus.map((num, idx) => (
                            <span
                              key={idx}
                              className="bg-green-600 text-white rounded-full w-7 h-7 flex items-center justify-center font-bold text-xs"
                            >
                              {num}
                            </span>
                          ))}
                        </div>
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* 당첨지점 목록 */}
      {winStores.length > 0 && (
        <div className="bg-white rounded-xl shadow-lg p-6">
          <h2 className="text-2xl font-bold mb-6">🥇 1등 ({winStores.length}개)</h2>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-600 border-b">
                <tr>
                  <th className="p-4 text-left">판매점명</th>
                  <th className="p-4 text-left">주소</th>
                </tr>
              </thead>
              <tbody>
                {winStores.map((store) => (
                  <React.Fragment key={store.store_id}>
                    <tr
                      onClick={() => setSelectedStore(selectedStore?.store_id === store.store_id ? null : store)}
                      className="border-t hover:bg-yellow-50 cursor-pointer transition"
                    >
                      <td className="p-4 font-bold text-gray-800">{store.store_name}</td>
                      <td className="p-4 text-gray-600 text-sm">{store.address}</td>
                      <td className="p-4 text-right">
                        <span className="text-lg font-bold px-3 py-1 rounded-full bg-blue-100 text-blue-800">
                          {store.method || "미정"}
                        </span>
                      </td>
                    </tr>

                    {/* 지점 상세 정보 - 클릭한 지점 바로 아래 */}
                    {selectedStore?.store_id === store.store_id && (
                      <tr key={`${store.store_id}-details`} className="bg-gradient-to-br from-yellow-50 to-orange-50">
                        <td colSpan={3} className="p-6">
                          <div className="space-y-4">
                            {/* 배찌 */}
                            <div className="flex flex-wrap gap-3">
                              {(store.lotto_wins?.length || 0) > 0 && (
                                <span className="bg-yellow-400 text-yellow-900 px-4 py-2 rounded-full font-bold text-sm">
                                  🎰 로또1등 {store.lotto_wins?.length || 0}회
                                </span>
                              )}
                              {(store.lotto_2nd_wins?.length || 0) > 0 && (
                                <span className="bg-amber-300 text-amber-900 px-4 py-2 rounded-full font-bold text-sm">
                                  🎰 로또2등 {store.lotto_2nd_wins?.length || 0}회
                                </span>
                              )}
                              {(store.pension_wins?.length || 0) > 0 && (
                                <span className="bg-blue-400 text-blue-900 px-4 py-2 rounded-full font-bold text-sm">
                                  💰 연금 {store.pension_wins?.length || 0}회
                                </span>
                              )}
                              {(store.speeto_wins?.length || 0) > 0 && (
                                <span className="bg-purple-400 text-purple-900 px-4 py-2 rounded-full font-bold text-sm">
                                  ✨ 스피또 {store.speeto_wins?.length || 0}회
                                </span>
                              )}
                            </div>

                            {/* 사용자 평가 */}
                            <div className="space-y-3">
                              {[
                                { icon: "📍", label: "주소", key: "address" },
                                { icon: "🅿️", label: "주차", key: "parking" },
                                { icon: "💳", label: "이체", key: "transfer" },
                                { icon: "💬", label: "친절", key: "kindness" },
                              ].map(({ icon, label, key }) => (
                                <div key={key} className="bg-white rounded-lg p-3">
                                  <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                      <span className="text-xl">{icon}</span>
                                      <h4 className="font-bold text-gray-800 text-sm">{label}</h4>
                                    </div>
                                    <div className="flex items-center gap-4">
                                      <button
                                        onClick={() => handleRating(store.store_id, key, 'like')}
                                        className={`flex items-center gap-1 hover:scale-110 transition ${
                                          storeRatings[store.store_id]?.[key] === 'like'
                                            ? 'text-blue-500'
                                            : 'text-gray-400'
                                        }`}
                                      >
                                        <span className={`text-xl ${
                                          storeRatings[store.store_id]?.[key] === 'like'
                                            ? 'text-blue-500'
                                            : 'text-gray-400'
                                        }`}>👍</span>
                                        <span
                                          className={`text-xs font-bold ${
                                            storeRatings[store.store_id]?.[key] === 'like'
                                              ? 'text-blue-500'
                                              : 'text-gray-500'
                                          }`}
                                        >
                                          {ratingCounts[store.store_id]?.[key]?.like || 0}
                                        </span>
                                      </button>
                                      <button
                                        onClick={() => handleRating(store.store_id, key, 'dislike')}
                                        className={`flex items-center gap-1 hover:scale-110 transition ${
                                          storeRatings[store.store_id]?.[key] === 'dislike'
                                            ? 'text-red-500'
                                            : 'text-gray-400'
                                        }`}
                                      >
                                        <span className={`text-xl ${
                                          storeRatings[store.store_id]?.[key] === 'dislike'
                                            ? 'text-red-500'
                                            : 'text-gray-400'
                                        }`}>👎</span>
                                        <span
                                          className={`text-xs font-bold ${
                                            storeRatings[store.store_id]?.[key] === 'dislike'
                                              ? 'text-red-500'
                                              : 'text-gray-500'
                                          }`}
                                        >
                                          {ratingCounts[store.store_id]?.[key]?.dislike || 0}
                                        </span>
                                      </button>
                                    </div>
                                  </div>
                                </div>
                              ))}
                            </div>

                            {/* 지도 버튼 */}
                            <div className="flex gap-4 justify-center">
                              <a
                                href={`https://map.kakao.com/link/search/${store.store_name}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="bg-yellow-400 hover:bg-yellow-500 text-yellow-900 font-bold py-3 px-6 rounded-lg transition"
                              >
                                🗺️ 카카오맵
                              </a>
                              <a
                                href={`https://map.naver.com/v5/search/${store.store_name}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="bg-green-500 hover:bg-green-600 text-white font-bold py-3 px-6 rounded-lg transition"
                              >
                                🗺️ 네이버맵
                              </a>
                            </div>

                            {/* 신고 버튼 */}
                            <div className="mt-4 flex justify-center">
                              <button
                                onClick={() => setShowReportModal(true)}
                                className="bg-red-500 hover:bg-red-600 text-white font-bold py-2 px-6 rounded-lg transition"
                              >
                                📢 신고하기
                              </button>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* 2등 당첨지점 목록 */}
      <div className="bg-white rounded-xl shadow-lg p-6 mt-8">
        <h2 className="text-2xl font-bold mb-6">🥈 2등 ({rank2Stores.length}개)</h2>
        {rank2Stores.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-600 border-b">
                <tr>
                  <th className="p-4 text-left">판매점명</th>
                  <th className="p-4 text-left">주소</th>
                </tr>
              </thead>
              <tbody>
                {rank2Stores.map((store) => (
                  <React.Fragment key={`2nd-${store.store_id}`}>
                    <tr
                      onClick={() => setSelectedStore(selectedStore?.store_id === store.store_id ? null : store)}
                      className="border-t hover:bg-yellow-50 cursor-pointer transition"
                    >
                      <td className="p-4 font-bold text-gray-800">{store.store_name}</td>
                      <td className="p-4 text-gray-600 text-sm">{store.address}</td>
                      <td className="p-4 text-right">
                        <span className="text-lg font-bold px-3 py-1 rounded-full bg-blue-100 text-blue-800">
                          {store.method || "미정"}
                        </span>
                      </td>
                    </tr>

                    {/* 지점 상세 정보 */}
                    {selectedStore?.store_id === store.store_id && (
                      <tr key={`2nd-${store.store_id}-details`} className="bg-gradient-to-br from-yellow-50 to-orange-50">
                        <td colSpan={3} className="p-6">
                          <div className="space-y-4">
                            {/* 배찌 */}
                            <div className="flex flex-wrap gap-3">
                              {(store.lotto_wins?.length || 0) > 0 && (
                                <span className="bg-yellow-400 text-yellow-900 px-4 py-2 rounded-full font-bold text-sm">
                                  🎰 로또1등 {store.lotto_wins?.length || 0}회
                                </span>
                              )}
                              {(store.lotto_2nd_wins?.length || 0) > 0 && (
                                <span className="bg-amber-300 text-amber-900 px-4 py-2 rounded-full font-bold text-sm">
                                  🎰 로또2등 {store.lotto_2nd_wins?.length || 0}회
                                </span>
                              )}
                              {(store.pension_wins?.length || 0) > 0 && (
                                <span className="bg-blue-400 text-blue-900 px-4 py-2 rounded-full font-bold text-sm">
                                  💰 연금 {store.pension_wins?.length || 0}회
                                </span>
                              )}
                              {(store.speeto_wins?.length || 0) > 0 && (
                                <span className="bg-purple-400 text-purple-900 px-4 py-2 rounded-full font-bold text-sm">
                                  ✨ 스피또 {store.speeto_wins?.length || 0}회
                                </span>
                              )}
                            </div>

                            {/* 사용자 평가 */}
                            <div className="space-y-3">
                              {[
                                { icon: "📍", label: "주소", key: "address" },
                                { icon: "🅿️", label: "주차", key: "parking" },
                                { icon: "💳", label: "이체", key: "transfer" },
                                { icon: "💬", label: "친절", key: "kindness" },
                              ].map(({ icon, label, key }) => (
                                <div key={key} className="bg-white rounded-lg p-3">
                                  <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                      <span className="text-xl">{icon}</span>
                                      <h4 className="font-bold text-gray-800 text-sm">{label}</h4>
                                    </div>
                                    <div className="flex items-center gap-4">
                                      <button
                                        onClick={() => handleRating(store.store_id, key, 'like')}
                                        className={`flex items-center gap-1 hover:scale-110 transition ${
                                          storeRatings[store.store_id]?.[key] === 'like'
                                            ? 'text-blue-500'
                                            : 'text-gray-400'
                                        }`}
                                      >
                                        <span className={`text-xl ${
                                          storeRatings[store.store_id]?.[key] === 'like'
                                            ? 'text-blue-500'
                                            : 'text-gray-400'
                                        }`}>👍</span>
                                        <span
                                          className={`text-xs font-bold ${
                                            storeRatings[store.store_id]?.[key] === 'like'
                                              ? 'text-blue-500'
                                              : 'text-gray-500'
                                          }`}
                                        >
                                          {ratingCounts[store.store_id]?.[key]?.like || 0}
                                        </span>
                                      </button>
                                      <button
                                        onClick={() => handleRating(store.store_id, key, 'dislike')}
                                        className={`flex items-center gap-1 hover:scale-110 transition ${
                                          storeRatings[store.store_id]?.[key] === 'dislike'
                                            ? 'text-red-500'
                                            : 'text-gray-400'
                                        }`}
                                      >
                                        <span className={`text-xl ${
                                          storeRatings[store.store_id]?.[key] === 'dislike'
                                            ? 'text-red-500'
                                            : 'text-gray-400'
                                        }`}>👎</span>
                                        <span
                                          className={`text-xs font-bold ${
                                            storeRatings[store.store_id]?.[key] === 'dislike'
                                              ? 'text-red-500'
                                              : 'text-gray-500'
                                          }`}
                                        >
                                          {ratingCounts[store.store_id]?.[key]?.dislike || 0}
                                        </span>
                                      </button>
                                    </div>
                                  </div>
                                </div>
                              ))}
                            </div>

                            {/* 지도 버튼 */}
                            <div className="flex gap-4 justify-center">
                              <a
                                href={`https://map.kakao.com/link/search/${store.store_name}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="bg-yellow-400 hover:bg-yellow-500 text-yellow-900 font-bold py-3 px-6 rounded-lg transition"
                              >
                                🗺️ 카카오맵
                              </a>
                              <a
                                href={`https://map.naver.com/v5/search/${store.store_name}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="bg-green-500 hover:bg-green-600 text-white font-bold py-3 px-6 rounded-lg transition"
                              >
                                🗺️ 네이버맵
                              </a>
                            </div>

                            {/* 신고 버튼 */}
                            <div className="mt-4 flex justify-center">
                              <button
                                onClick={() => setShowReportModal(true)}
                                className="bg-red-500 hover:bg-red-600 text-white font-bold py-2 px-6 rounded-lg transition"
                              >
                                📢 신고하기
                              </button>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-center text-gray-500">2등 당첨 지점이 없습니다.</p>
        )}
      </div>

      {winStores.length === 0 && rank2Stores.length === 0 && !loading && (
        <div className="bg-white rounded-xl shadow-lg p-6 text-center">
          <p className="text-gray-500">이번 주 당첨지점을 업로드 중입니다.</p>
        </div>
      )}

      {/* 신고 모달 */}
      {showReportModal && selectedStore && (
        <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-xl shadow-2xl p-6 w-full max-w-md">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-2xl font-bold text-gray-800">신고하기</h2>
              <button
                onClick={() => setShowReportModal(false)}
                className="text-gray-400 hover:text-gray-600 text-2xl"
              >
                ✕
              </button>
            </div>

            <div className="mb-4">
              <p className="text-sm text-gray-600 mb-2">지점명</p>
              <p className="font-bold text-gray-800">{selectedStore.store_name}</p>
              <p className="text-sm text-gray-600 mb-4">{selectedStore.address}</p>
            </div>

            <div className="mb-4">
              <label className="block text-sm font-bold text-gray-700 mb-3">
                신고 사유 (중복 선택 가능)
              </label>
              <div className="space-y-2">
                {[
                  "주소가 정확하지않음",
                  "없는 지점임",
                  "로또를 판매하지않음",
                  "당첨회차내용이 다름",
                  "당첨등수가 잘못됨",
                ].map((reason) => (
                  <label key={reason} className="flex items-center">
                    <input
                      type="checkbox"
                      checked={reportReasons.includes(reason)}
                      onChange={(e) => {
                        if (e.target.checked) {
                          setReportReasons([...reportReasons, reason]);
                        } else {
                          setReportReasons(reportReasons.filter((r) => r !== reason));
                        }
                      }}
                      className="w-4 h-4 text-red-500 rounded focus:ring-2 focus:ring-red-500 cursor-pointer"
                    />
                    <span className="ml-3 text-sm text-gray-700 cursor-pointer">{reason}</span>
                  </label>
                ))}
              </div>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setShowReportModal(false)}
                className="flex-1 bg-gray-300 hover:bg-gray-400 text-gray-800 font-bold py-2 px-4 rounded-lg transition"
              >
                취소
              </button>
              <button
                onClick={handleReportSubmit}
                disabled={reportSubmitting}
                className="flex-1 bg-red-500 hover:bg-red-600 disabled:bg-gray-400 text-white font-bold py-2 px-4 rounded-lg transition"
              >
                {reportSubmitting ? "제출 중..." : "신고"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
