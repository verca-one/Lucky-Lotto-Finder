"use client";

import { useState, useEffect } from "react";
import { useParams, useRouter } from "next/navigation";
import { db } from "@/lib/firebase";
import { doc, getDoc } from "firebase/firestore";

interface LottoRecord {
  round: number;
  numbers: number[];
  bonus: number;
  lottery_type: string;
}

export default function RoundDetailPage() {
  const params = useParams();
  const router = useRouter();
  const round = params.round as string;

  const [record, setRecord] = useState<LottoRecord | null>(null);
  const [loading, setLoading] = useState(true);
  const [collecting, setCollecting] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    const fetchRecord = async () => {
      try {
        const docRef = doc(db, "lotto_records", `round_${round}`);
        const docSnap = await getDoc(docRef);
        if (docSnap.exists()) {
          setRecord(docSnap.data() as LottoRecord);
        }
      } catch (error) {
        console.error("Error fetching record:", error);
      } finally {
        setLoading(false);
      }
    };

    fetchRecord();
  }, [round]);

  const handleCollectStores = async () => {
    setCollecting(true);
    setMessage("당첨지점을 수집중입니다...");

    try {
      const response = await fetch("/api/crawl-stores-by-round", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ round: parseInt(round) }),
      });

      const data = await response.json();

      if (response.ok) {
        setMessage(`✅ ${data.count}개 당첨지점 수집 완료!`);
        setTimeout(() => {
          router.push("/");
        }, 2000);
      } else {
        setMessage(`❌ 수집 실패: ${data.error}`);
      }
    } catch (error) {
      setMessage(`❌ 오류: ${error}`);
    } finally {
      setCollecting(false);
    }
  };

  if (loading) {
    return <div className="p-8 text-center">로딩 중...</div>;
  }

  if (!record) {
    return <div className="p-8 text-center text-red-500">당첨번호를 찾을 수 없습니다</div>;
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-green-50 to-blue-50 p-8">
      <div className="max-w-2xl mx-auto bg-white rounded-2xl shadow-xl p-8">
        {/* 제목 */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-800 mb-2">
            {record.lottery_type === "pension" ? "연금복권" : "로또"} {record.round}회
          </h1>
          <p className="text-gray-500">당첨지점 수집</p>
        </div>

        {/* 당첨번호 표시 */}
        <div className="bg-gradient-to-r from-purple-50 to-blue-50 rounded-xl p-6 mb-8">
          <p className="text-sm text-gray-600 mb-3">당첨번호</p>
          <div className="flex flex-wrap gap-3 items-center">
            {record.numbers.map((num, idx) => (
              <div
                key={idx}
                className="w-12 h-12 bg-gradient-to-br from-blue-400 to-blue-600 rounded-full flex items-center justify-center text-white font-bold text-lg shadow-lg"
              >
                {num}
              </div>
            ))}
            <span className="text-2xl text-gray-400">+</span>
            <div className="w-12 h-12 bg-gradient-to-br from-red-400 to-red-600 rounded-full flex items-center justify-center text-white font-bold text-lg shadow-lg">
              {record.bonus}
            </div>
          </div>
        </div>

        {/* 안내문 */}
        <div className="bg-blue-50 border-l-4 border-blue-400 p-4 mb-8 rounded">
          <p className="text-blue-800">
            💡 <strong>당첨지점을 수집중입니다</strong><br/>
            아래 버튼을 클릭하면 이 회차의 1등, 2등 당첨지점을 자동으로 수집합니다.
          </p>
        </div>

        {/* 메시지 */}
        {message && (
          <div className={`p-4 rounded-lg mb-6 text-center font-semibold ${
            message.includes("✅") ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"
          }`}>
            {message}
          </div>
        )}

        {/* 수집 버튼 */}
        <button
          onClick={handleCollectStores}
          disabled={collecting}
          className="w-full bg-gradient-to-r from-green-400 to-blue-500 hover:from-green-500 hover:to-blue-600 disabled:from-gray-400 disabled:to-gray-500 text-white font-bold py-4 px-6 rounded-lg transition duration-200 transform hover:scale-105 disabled:scale-100"
        >
          {collecting ? "수집 중..." : "🚀 당첨지점 수집"}
        </button>

        {/* 돌아가기 */}
        <button
          onClick={() => router.push("/")}
          className="w-full mt-4 bg-gray-200 hover:bg-gray-300 text-gray-800 font-bold py-3 px-6 rounded-lg transition"
        >
          돌아가기
        </button>
      </div>
    </div>
  );
}
