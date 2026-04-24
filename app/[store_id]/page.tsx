"use client";

import { useEffect, useState } from "react";
import { db } from "@/lib/firebase";
import { doc, getDoc, collection, query, where, getDocs, orderBy, addDoc, Timestamp } from "firebase/firestore";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import dynamic from "next/dynamic";

interface Store {
  store_id: string;
  store_name: string;
  address: string;
  lat?: number;
  lng?: number;
  region?: string;
  lotto_wins?: number[];
  pension_wins?: number[];
}

interface WinHistory {
  id?: string;
  round: number;
  lottery_type: string;
  method?: string;
  prize?: number;
  crawled_at: string;
}

interface Report {
  id?: string;
  reason: string;
  content: string;
  status: string;
  created_at: string;
}

const SimpleMap = dynamic(() => import("@/components/SimpleMap"), { ssr: false });

const TAB_LIST = [
  { key: "lotto", label: "로또6/45" },
  { key: "pension", label: "연금복권" },
];

// 회차를 날짜로 변환 (로또 기준: 2002.12.07부터 시작)
function roundToDate(round: number): string {
  const firstDate = new Date(2002, 11, 7);
  const date = new Date(firstDate.getTime() + (round - 1) * 7 * 24 * 60 * 60 * 1000);
  return `${date.getFullYear()}.${String(date.getMonth() + 1).padStart(2, "0")}.${String(date.getDate()).padStart(2, "0")}`;
}

export default function StoreDetailPage() {
  const { store_id } = useParams();
  const searchParams = useSearchParams();
  const router = useRouter();
  const [store, setStore] = useState<Store | null>(null);
  const [history, setHistory] = useState<WinHistory[]>([]);
  const [reports, setReports] = useState<Report[]>([]);
  const [activeTab, setActiveTab] = useState("lotto");
  const [loading, setLoading] = useState(true);
  const [showReportModal, setShowReportModal] = useState(searchParams.get("tab") === "report");
  const [reportForm, setReportForm] = useState({ reason: "", content: "" });

  useEffect(() => {
    const fetchData = async () => {
      // 지점 정보 조회
      const storeDoc = await getDoc(doc(db, "stores", store_id as string));
      if (storeDoc.exists()) {
        setStore(storeDoc.data() as Store);
      }

      // 당첨 이력 조회
      const historySnapshot = await getDocs(
        query(
          collection(db, "win_history"),
          where("store_id", "==", store_id),
          orderBy("round", "desc")
        )
      );
      setHistory(
        historySnapshot.docs.map((doc) => ({
          id: doc.id,
          ...doc.data(),
        } as WinHistory))
      );

      // 신고 목록 조회
      const reportsSnapshot = await getDocs(
        query(
          collection(db, "reports"),
          where("store_id", "==", store_id),
          orderBy("created_at", "desc")
        )
      );
      setReports(
        reportsSnapshot.docs.map((doc) => ({
          id: doc.id,
          ...doc.data(),
        } as Report))
      );

      setLoading(false);
    };

    if (store_id) {
      fetchData();
    }
  }, [store_id]);

  const handleSubmitReport = async () => {
    if (!reportForm.reason.trim() || !reportForm.content.trim()) {
      alert("신고 사유와 내용을 모두 입력해주세요");
      return;
    }

    try {
      const newReport = {
        store_id,
        reason: reportForm.reason,
        content: reportForm.content,
        status: "대기",
        created_at: new Date().toISOString(),
      };

      await addDoc(collection(db, "reports"), newReport);
      alert("신고가 접수되었습니다. 검토 후 처리하겠습니다.");
      setReportForm({ reason: "", content: "" });
      setShowReportModal(false);

      // 신고 목록 새로고침
      const reportsSnapshot = await getDocs(
        query(
          collection(db, "reports"),
          where("store_id", "==", store_id),
          orderBy("created_at", "desc")
        )
      );
      setReports(
        reportsSnapshot.docs.map((doc) => ({
          id: doc.id,
          ...doc.data(),
        } as Report))
      );
    } catch (error) {
      console.error(error);
      alert("신고 접수 실패");
    }
  };

  if (loading) return <div className="p-8 text-center">로딩 중...</div>;
  if (!store) return <div className="p-8 text-center">지점을 찾을 수 없습니다.</div>;

  const lottoWins = store.lotto_wins || [];
  const pensionWins = store.pension_wins || [];

  const filteredHistory = history.filter((h) => {
    if (activeTab === "lotto") return h.lottery_type === "lotto";
    if (activeTab === "pension") return h.lottery_type === "pension";
    return false;
  });

  return (
    <div className="min-h-screen bg-gray-100 pb-20">
      {/* 헤더 */}
      <div className="sticky top-0 bg-white shadow p-4 z-10">
        <button onClick={() => router.back()} className="text-blue-500 font-bold">
          ← 뒤로
        </button>
      </div>

      {/* 지점 정보 */}
      <div className="bg-white m-4 rounded-xl shadow p-6">
        <h1 className="text-3xl font-bold mb-2">{store.store_name}</h1>
        <p className="text-gray-600 mb-4">{store.address}</p>

        {/* 지도 */}
        {store.lat && store.lng && (
          <div className="w-full h-48 rounded-lg overflow-hidden mb-4 bg-gray-100">
            <SimpleMap lat={store.lat} lng={store.lng} zoom={16} />
          </div>
        )}

        {/* 통계 */}
        <div className="grid grid-cols-2 gap-4 mb-6">
          <div className="bg-yellow-50 p-4 rounded-lg text-center">
            <p className="text-sm text-gray-600 mb-1">로또</p>
            <p className="text-3xl font-bold text-yellow-600">{lottoWins.length}</p>
            <p className="text-xs text-gray-500 mt-1">회</p>
          </div>
          <div className="bg-blue-50 p-4 rounded-lg text-center">
            <p className="text-sm text-gray-600 mb-1">연금</p>
            <p className="text-3xl font-bold text-blue-600">{pensionWins.length}</p>
            <p className="text-xs text-gray-500 mt-1">회</p>
          </div>
        </div>

        {/* 액션 버튼 */}
        <div className="grid grid-cols-2 gap-3 mb-6">
          <button
            onClick={() => {
              if (store.lat && store.lng) {
                window.open(
                  `https://map.kakao.com/link/map/${store.store_name},${store.lat},${store.lng}`,
                  "_blank"
                );
              }
            }}
            className="bg-yellow-400 text-black font-bold py-3 rounded-lg hover:bg-yellow-500 transition"
          >
            카카오맵
          </button>
          <button
            onClick={() => {
              if (store.lat && store.lng) {
                window.open(
                  `https://map.naver.com/index.nhn?lat=${store.lat}&lng=${store.lng}`,
                  "_blank"
                );
              }
            }}
            className="bg-green-500 text-white font-bold py-3 rounded-lg hover:bg-green-600 transition"
          >
            네이버맵
          </button>
        </div>

        <button
          onClick={() => setShowReportModal(true)}
          className="w-full bg-red-500 text-white font-bold py-3 rounded-lg hover:bg-red-600 transition"
        >
          🚨 신고하기
        </button>
      </div>

      {/* 당첨 이력 탭 */}
      <div className="bg-white m-4 rounded-xl shadow overflow-hidden">
        <div className="flex border-b">
          {TAB_LIST.map((tab) => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className={`flex-1 px-4 py-3 text-sm font-medium transition ${
                activeTab === tab.key
                  ? "border-b-2 border-blue-500 text-blue-600"
                  : "text-gray-500 hover:text-gray-700"
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* 이력 목록 */}
        <div className="divide-y">
          {filteredHistory.length === 0 ? (
            <p className="p-4 text-center text-gray-400 text-sm">당첨 이력이 없습니다.</p>
          ) : (
            filteredHistory.map((h) => (
              <div key={h.id} className="p-4 hover:bg-gray-50 transition">
                <div className="flex justify-between items-start">
                  <div>
                    <p className="font-bold text-lg">{h.round}회</p>
                    <p className="text-sm text-gray-600 mt-1">
                      {roundToDate(h.round)}
                    </p>
                    {h.method && (
                      <p className="text-xs text-gray-500 mt-1">{h.method}</p>
                    )}
                  </div>
                  <div className="text-right">
                    {h.prize ? (
                      <>
                        <p className="font-bold text-lg text-green-600">
                          {h.prize.toLocaleString()}원
                        </p>
                        <p className="text-xs text-gray-500">당첨금</p>
                      </>
                    ) : (
                      <p className="text-gray-400 text-sm">-</p>
                    )}
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* 신고 목록 */}
      <div className="bg-white m-4 rounded-xl shadow overflow-hidden">
        <div className="p-4 border-b font-semibold bg-gray-50">
          신고 현황
          <span className="ml-2 text-sm text-red-500">
            {reports.filter((r) => r.status === "대기").length}건 대기중
          </span>
        </div>

        {reports.length === 0 ? (
          <p className="p-4 text-center text-gray-400 text-sm">신고 내역이 없습니다.</p>
        ) : (
          <div className="divide-y">
            {reports.map((r) => (
              <div key={r.id} className="p-4 hover:bg-gray-50 transition">
                <div className="flex justify-between items-start mb-2">
                  <p className="font-bold">{r.reason}</p>
                  <span
                    className={`px-2 py-1 rounded-full text-xs font-medium ${
                      r.status === "대기"
                        ? "bg-red-100 text-red-600"
                        : "bg-green-100 text-green-600"
                    }`}
                  >
                    {r.status}
                  </span>
                </div>
                <p className="text-sm text-gray-600">{r.content}</p>
                <p className="text-xs text-gray-400 mt-2">
                  {new Date(r.created_at).toLocaleDateString("ko-KR")}
                </p>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* 신고 모달 */}
      {showReportModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl p-6 w-full max-w-md max-h-96 overflow-y-auto">
            <div className="flex justify-between items-center mb-4">
              <h2 className="text-xl font-bold">신고하기</h2>
              <button
                onClick={() => setShowReportModal(false)}
                className="text-gray-400 hover:text-gray-600 text-2xl"
              >
                ✕
              </button>
            </div>

            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                신고 사유 *
              </label>
              <select
                value={reportForm.reason}
                onChange={(e) => setReportForm({ ...reportForm, reason: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500"
              >
                <option value="">선택하세요</option>
                <option value="부정 정보">부정 정보</option>
                <option value="영업 중단">영업 중단</option>
                <option value="잘못된 위치">잘못된 위치</option>
                <option value="기타">기타</option>
              </select>
            </div>

            <div className="mb-6">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                상세 내용 *
              </label>
              <textarea
                value={reportForm.content}
                onChange={(e) => setReportForm({ ...reportForm, content: e.target.value })}
                placeholder="신고 내용을 입력해주세요"
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500 resize-none"
                rows={4}
              />
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setShowReportModal(false)}
                className="flex-1 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50"
              >
                취소
              </button>
              <button
                onClick={handleSubmitReport}
                className="flex-1 px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 font-bold"
              >
                신고 접수
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
