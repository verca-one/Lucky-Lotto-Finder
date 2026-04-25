"use client";

import { useState, useEffect } from "react";
import { useParams, useRouter } from "next/navigation";
import { db } from "@/lib/firebase";
import { doc, getDoc, collection, query, where, getDocs } from "firebase/firestore";

interface LottoRecord {
  round: number;
  numbers: number[];
  bonus: number;
  lottery_type: string;
}

interface Store {
  rank: number;
  store_name: string;
  address: string;
  method: string;
  region: string;
}

export default function RoundDetailPage() {
  const params = useParams();
  const router = useRouter();
  const round = params.round as string;

  const [record, setRecord] = useState<LottoRecord | null>(null);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingStores, setLoadingStores] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    const fetchRecord = async () => {
      try {
        // 당첨번호 조회
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

  // 미리 수집해둔 당첨지점 로드
  const handleLoadStores = async () => {
    setLoadingStores(true);
    setMessage("당첨지점을 불러오는 중...");

    try {
      const storesRef = collection(db, "stores");
      const q = query(
        storesRef,
        where("round", "==", parseInt(round)),
        where("rank", "in", [1, 2])
      );

      const querySnapshot = await getDocs(q);
      const storesData: Store[] = [];

      querySnapshot.forEach((doc) => {
        storesData.push(doc.data() as Store);
      });

      setStores(storesData);

      if (storesData.length > 0) {
        setMessage(`✅ ${storesData.length}개 당첨지점 로드 완료!`);
        setTimeout(() => setMessage(""), 3000);
      } else {
        setMessage("⚠️ 아직 당첨지점이 수집되지 않았습니다. 나중에 다시 시도해주세요.");
      }
    } catch (error) {
      console.error("Error loading stores:", error);
      setMessage(`❌ 오류: ${error}`);
    } finally {
      setLoadingStores(false);
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
      <div className="max-w-3xl mx-auto bg-white rounded-2xl shadow-xl p-8">
        {/* 제목 */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-800 mb-2">
            {record.lottery_type === "pension" ? "연금복권" : "로또"} {record.round}회
          </h1>
          <p className="text-gray-500">당첨번호 및 당첨지점</p>
        </div>

        {/* 당첨번호 표시 */}
        <div className="bg-gradient-to-r from-purple-50 to-blue-50 rounded-xl p-6 mb-8">
          <p className="text-sm text-gray-600 mb-3 font-bold">당첨번호</p>
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
        {stores.length === 0 && (
          <div className="bg-blue-50 border-l-4 border-blue-400 p-4 mb-8 rounded">
            <p className="text-blue-800">
              💡 <strong>당첨지점을 불러옵니다</strong><br/>
              아래 버튼을 클릭하면 미리 수집해둔 이 회차의 1등, 2등 당첨지점을 표시합니다.
            </p>
          </div>
        )}

        {/* 메시지 */}
        {message && (
          <div className={`p-4 rounded-lg mb-6 text-center font-semibold ${
            message.includes("✅") ? "bg-green-100 text-green-800" : "bg-yellow-100 text-yellow-800"
          }`}>
            {message}
          </div>
        )}

        {/* 당첨지점 로드 버튼 */}
        {stores.length === 0 && (
          <button
            onClick={handleLoadStores}
            disabled={loadingStores}
            className="w-full bg-gradient-to-r from-green-400 to-blue-500 hover:from-green-500 hover:to-blue-600 disabled:from-gray-400 disabled:to-gray-500 text-white font-bold py-4 px-6 rounded-lg transition duration-200 transform hover:scale-105 disabled:scale-100 mb-6"
          >
            {loadingStores ? "로드 중..." : "🎯 당첨지점 불러오기"}
          </button>
        )}

        {/* 당첨지점 표시 */}
        {stores.length > 0 && (
          <div className="space-y-4 mb-6">
            <h2 className="text-2xl font-bold text-gray-800 mb-4">당첨지점</h2>

            {/* 1등 당첨지점 */}
            {stores.filter(s => s.rank === 1).length > 0 && (
              <div className="bg-gradient-to-r from-yellow-50 to-orange-50 rounded-xl p-6 border-2 border-yellow-300">
                <p className="text-lg font-bold text-yellow-800 mb-4">🏆 1등 당첨지점</p>
                <div className="space-y-3">
                  {stores.filter(s => s.rank === 1).map((store, idx) => (
                    <div key={idx} className="bg-white p-3 rounded-lg shadow">
                      <p className="font-bold text-gray-800">{store.store_name}</p>
                      <p className="text-sm text-gray-600">{store.address}</p>
                      <div className="flex gap-4 mt-2 text-xs text-gray-500">
                        <span className="bg-yellow-200 px-2 py-1 rounded">{store.region}</span>
                        <span className="bg-blue-200 px-2 py-1 rounded">{store.method}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* 2등 당첨지점 */}
            {stores.filter(s => s.rank === 2).length > 0 && (
              <div className="bg-gradient-to-r from-blue-50 to-indigo-50 rounded-xl p-6 border-2 border-blue-300">
                <p className="text-lg font-bold text-blue-800 mb-4">🎖️ 2등 당첨지점</p>
                <div className="space-y-3">
                  {stores.filter(s => s.rank === 2).map((store, idx) => (
                    <div key={idx} className="bg-white p-3 rounded-lg shadow">
                      <p className="font-bold text-gray-800">{store.store_name}</p>
                      <p className="text-sm text-gray-600">{store.address}</p>
                      <div className="flex gap-4 mt-2 text-xs text-gray-500">
                        <span className="bg-yellow-200 px-2 py-1 rounded">{store.region}</span>
                        <span className="bg-blue-200 px-2 py-1 rounded">{store.method}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* 돌아가기 */}
        <button
          onClick={() => router.push("/")}
          className="w-full bg-gray-200 hover:bg-gray-300 text-gray-800 font-bold py-3 px-6 rounded-lg transition"
        >
          돌아가기
        </button>
      </div>
    </div>
  );
}
