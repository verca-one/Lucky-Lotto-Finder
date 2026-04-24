"use client";

import { useState, useEffect } from "react";
import { db } from "@/lib/firebase";
import { collection, addDoc, getDocs, deleteDoc, doc, query, orderBy, writeBatch } from "firebase/firestore";
import { useRouter } from "next/navigation";

interface LottoRecord {
  id: string;
  round: number;
  date: string;
  numbers: number[];
  bonus: number;
  createdAt: any;
}

interface Report {
  id: string;
  store_id: string;
  store_name: string;
  address: string;
  content: string;
  createdAt: any;
}

export default function AdminPage() {
  const [authenticated, setAuthenticated] = useState(false);
  const [password, setPassword] = useState("");
  const [passwordError, setPasswordError] = useState("");

  const [round, setRound] = useState("");
  const [date, setDate] = useState("");
  const [numbers, setNumbers] = useState<number[]>([]);
  const [bonus, setBonus] = useState("");
  const [pensionGroup, setPensionGroup] = useState(""); // 1등 조 (예: 2조)
  const [pensionRank1, setPensionRank1] = useState<number[]>([0, 0, 0, 0, 0, 0]); // 1등 숫자
  const [pensionBonus, setPensionBonus] = useState<number[]>([0, 0, 0, 0, 0, 0]);
  const [records, setRecords] = useState<LottoRecord[]>([]);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [activeTab, setActiveTab] = useState<"lotto" | "pension" | "speeto" | "reports" | "upload">("lotto");
  const [reports, setReports] = useState<Report[]>([]);
  const [selectedReport, setSelectedReport] = useState<Report | null>(null);
  const router = useRouter();

  const ADMIN_PASSWORD = "admin@2018!";
  const [imageProcessing, setImageProcessing] = useState(false);

  const getNumberColor = (num: number) => {
    if (num >= 1 && num <= 10) return "bg-yellow-400";
    if (num >= 11 && num <= 20) return "bg-blue-400";
    if (num >= 21 && num <= 30) return "bg-red-400";
    if (num >= 31 && num <= 45) return "bg-gray-400";
    return "bg-yellow-400";
  };

  // 1등 숫자로부터 자동으로 2등~7등 생성
  const generatePensionWinners = () => {
    const winners: Record<string, { group: string; balls: number[] }> = {
      "1등": { group: pensionGroup, balls: pensionRank1 },
      "2등": { group: `${pensionGroup} 외`, balls: pensionRank1 }, // 조 외, 숫자는 동일
      "3등": { group: "각조", balls: pensionRank1.slice(1) }, // 첫번째 제외
      "4등": { group: "각조", balls: pensionRank1.slice(2) }, // 처음 2개 제외
      "5등": { group: "각조", balls: pensionRank1.slice(3) }, // 처음 3개 제외
      "6등": { group: "각조", balls: pensionRank1.slice(4) }, // 처음 4개 제외
      "7등": { group: "각조", balls: pensionRank1.slice(5) }, // 처음 5개 제외
    };
    return winners;
  };

  // 비밀번호 확인
  const handlePasswordSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (password === ADMIN_PASSWORD) {
      setAuthenticated(true);
      setPasswordError("");
      fetchRecords();
      fetchReports();
    } else {
      setPasswordError("비밀번호가 틀렸습니다");
      setPassword("");
    }
  };

  // activeTab 변경 시 데이터 다시 로드
  useEffect(() => {
    if (authenticated && activeTab !== "reports") {
      fetchRecords();
    }
  }, [activeTab]);

  // Tesseract.js CDN 로드
  useEffect(() => {
    if (!authenticated) return;

    const script = document.createElement("script");
    script.src = "https://cdn.jsdelivr.net/npm/tesseract.js@5.0.4/dist/tesseract.min.js";
    script.async = true;
    document.head.appendChild(script);

    return () => {
      document.head.removeChild(script);
    };
  }, [authenticated]);

  // 이미지에서 로또번호 추출
  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setImageProcessing(true);
    try {
      const reader = new FileReader();
      reader.onload = async (event) => {
        const imageSrc = event.target?.result as string;

        // 동적으로 Tesseract 로드
        const Tesseract = (window as any).Tesseract;
        if (!Tesseract) {
          throw new Error("Tesseract 라이브러리가 로드되지 않았습니다");
        }

        // Tesseract로 이미지에서 텍스트 추출
        const { data: { text } } = await Tesseract.recognize(imageSrc, "eng");

        // 숫자만 추출 (1-45 범위)
        const numberMatches = text.match(/\d+/g) || [];
        const validNumbers = numberMatches
          .map(n => parseInt(n))
          .filter(n => n >= 1 && n <= 45);

        if (validNumbers.length >= 7) {
          // 처음 6개는 로또번호, 마지막 1개는 보너스
          const lottoNumbers = validNumbers.slice(0, 6);
          const bonusNumber = validNumbers[6];

          setNumbers(lottoNumbers);
          setBonus(bonusNumber.toString());
          setMessage("✅ 이미지에서 번호를 인식했습니다!");
          setTimeout(() => setMessage(""), 3000);
        } else {
          setMessage("❌ 이미지에서 로또번호를 찾을 수 없습니다.");
          setTimeout(() => setMessage(""), 3000);
        }
      };
      reader.readAsDataURL(file);
    } catch (error) {
      console.error("이미지 처리 실패:", error);
      setMessage("❌ 이미지 처리 실패");
      setTimeout(() => setMessage(""), 3000);
    } finally {
      setImageProcessing(false);
    }
  };

  // 로또 데이터 로드
  const fetchRecords = async () => {
    if (activeTab === "reports") return;

    setLoading(true);
    try {
      const q = query(collection(db, "lotto_records"), orderBy("round", "desc"));
      const snapshot = await getDocs(q);
      const data = snapshot.docs
        .map((doc) => ({
          id: doc.id,
          ...doc.data(),
        } as LottoRecord & { lottery_type?: string }))
        .filter((record) => (record.lottery_type || "lotto") === activeTab);
      setRecords(data as LottoRecord[]);
    } catch (error) {
      console.error("데이터 로드 실패:", error);
    }
    setLoading(false);
  };

  // 신고 데이터 로드
  const fetchReports = async () => {
    setLoading(true);
    try {
      const q = query(collection(db, "reports"), orderBy("createdAt", "desc"));
      const snapshot = await getDocs(q);
      const data = snapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      } as Report));
      setReports(data);
    } catch (error) {
      console.error("신고 데이터 로드 실패:", error);
    }
    setLoading(false);
  };

  // 숫자 입력 처리
  const handleNumbersChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const input = e.target.value;
    const nums = input.split(",").map((n) => parseInt(n.trim())).filter((n) => !isNaN(n));
    setNumbers(nums);
  };

  // 저장
  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!round || !date) {
      setMessage("❌ 회차와 날짜를 입력하세요");
      return;
    }

    if (activeTab !== "pension" && (numbers.length === 0 || !bonus)) {
      setMessage("❌ 모든 필드를 입력하세요");
      return;
    }

    setSaving(true);
    try {
      if (activeTab === "pension") {
        // 연금복권 저장 - 자동 분류된 데이터 사용
        await addDoc(collection(db, "lotto_records"), {
          lottery_type: "pension",
          round: parseInt(round),
          date: date,
          winners: generatePensionWinners(),
          bonus: pensionBonus,
          createdAt: new Date(),
        });
        setMessage("✅ 저장되었습니다!");
        setRound("");
        setDate("");
        setPensionGroup("");
        setPensionRank1([0, 0, 0, 0, 0, 0]);
        setPensionBonus([0, 0, 0, 0, 0, 0]);
      } else {
        // 로또/스피또 저장
        await addDoc(collection(db, "lotto_records"), {
          lottery_type: activeTab,
          round: parseInt(round),
          date: date,
          numbers: numbers,
          bonus: parseInt(bonus),
          createdAt: new Date(),
        });
        setMessage("✅ 저장되었습니다!");
        setRound("");
        setDate("");
        setNumbers([]);
        setBonus("");
      }
      fetchRecords();
      setTimeout(() => setMessage(""), 3000);
    } catch (error) {
      console.error("저장 실패:", error);
      setMessage("❌ 저장 실패");
    } finally {
      setSaving(false);
    }
  };

  // 로또 기록 삭제
  const handleDelete = async (id: string) => {
    if (window.confirm("정말 삭제하시겠습니까?")) {
      try {
        await deleteDoc(doc(db, "lotto_records", id));
        setMessage("✅ 삭제되었습니다!");
        fetchRecords();
        setTimeout(() => setMessage(""), 3000);
      } catch (error) {
        console.error("삭제 실패:", error);
        setMessage("❌ 삭제 실패");
      }
    }
  };

  // 신고 처리
  const handleReportProcessed = async (id: string) => {
    try {
      await deleteDoc(doc(db, "reports", id));
      setMessage("✅ 신고가 처리되었습니다!");
      setSelectedReport(null);
      fetchReports();
      setTimeout(() => setMessage(""), 3000);
    } catch (error) {
      console.error("처리 실패:", error);
      setMessage("❌ 처리 실패");
    }
  };

  // 크롤링 데이터 JSON 파일 업로드
  const handleJsonFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setSaving(true);
    try {
      const text = await file.text();
      const stores = JSON.parse(text);

      if (!Array.isArray(stores)) {
        setMessage("❌ 올바른 JSON 배열 형식이 아닙니다");
        setSaving(false);
        return;
      }

      // Firestore 배치 작업
      const batch = writeBatch(db);
      let storeCount = 0;
      let historyCount = 0;

      for (const store of stores) {
        // store_id 생성 또는 기존 ID 사용
        let storeId = store.store_id;

        if (!storeId) {
          // store_id가 없으면 이름과 주소로 간단한 ID 생성
          const text = `${store.store_name}_${store.address}`;
          let hash = 0;
          for (let i = 0; i < text.length; i++) {
            const char = text.charCodeAt(i);
            hash = ((hash << 5) - hash) + char;
            hash = hash & hash;
          }
          storeId = Math.abs(hash).toString(36).substring(0, 12);
        }

        // 1. stores 컬렉션에 저장
        const storeRef = doc(db, "stores", storeId);
        const lottery_type = store.lottery_type || "lotto";
        const winField = `${lottery_type}_wins`;

        batch.set(
          storeRef,
          {
            store_id: storeId,
            store_name: store.store_name,
            address: store.address,
            region: store.region || "",
            lat: store.lat || null,
            lng: store.lng || null,
            method: store.method || "",
            updated_at: new Date(),
            [winField]: [store.round],
            last_win_round: store.round,
          },
          { merge: true }
        );
        storeCount++;

        // 2. win_history 컬렉션에 저장
        const historyId = `${storeId}_${lottery_type}_${store.round}`;
        const historyRef = doc(db, "win_history", historyId);

        batch.set(historyRef, {
          store_id: storeId,
          lottery_type: lottery_type,
          round: store.round,
          rank: store.rank || 1,
          method: store.method || "",
          crawled_at: store.crawled_at || new Date(),
        });
        historyCount++;
      }

      await batch.commit();
      setMessage(`✅ 업로드 완료! (지점: ${storeCount}개, 기록: ${historyCount}개)`);
      setTimeout(() => setMessage(""), 3000);
    } catch (error) {
      console.error("JSON 파일 업로드 실패:", error);
      setMessage("❌ 파일 업로드 실패");
    } finally {
      setSaving(false);
    }
  };

  // 비밀번호 페이지
  if (!authenticated) {
    return (
      <div className="bg-gradient-to-br from-blue-50 to-indigo-100 p-6 min-h-screen flex items-center justify-center">
        <div className="bg-white rounded-xl shadow-2xl p-8 w-full max-w-sm">
          <h1 className="text-3xl font-bold text-center mb-8 text-gray-800">🎰 관리자 페이지</h1>
          <form onSubmit={handlePasswordSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-bold text-gray-700 mb-2">비밀번호</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full px-4 py-3 border-2 border-gray-300 rounded-lg focus:border-yellow-400 focus:outline-none"
                placeholder="비밀번호를 입력하세요"
                autoFocus
              />
            </div>
            {passwordError && <p className="text-red-500 text-sm font-bold">{passwordError}</p>}
            <button
              type="submit"
              className="w-full bg-yellow-400 hover:bg-yellow-500 text-yellow-900 font-bold py-3 px-6 rounded-lg transition"
            >
              확인
            </button>
          </form>
        </div>
      </div>
    );
  }

  // 관리자 페이지
  return (
    <div className="bg-gradient-to-br from-blue-50 to-indigo-100 p-6 min-h-screen">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold text-gray-800">🎰 관리자 페이지</h1>
          <button
            onClick={() => router.push("/")}
            className="bg-gray-400 hover:bg-gray-500 text-white font-bold py-2 px-4 rounded-lg transition"
          >
            홈으로
          </button>
        </div>

        {/* 탭 */}
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
          <button
            onClick={() => setActiveTab("upload")}
            className={`font-bold py-3 px-6 transition ${
              activeTab === "upload"
                ? "border-b-4 border-green-400 text-green-600"
                : "text-gray-600 hover:text-gray-800"
            }`}
          >
            크롤링 데이터
          </button>
          <button
            onClick={() => setActiveTab("reports")}
            className={`font-bold py-3 px-6 transition ${
              activeTab === "reports"
                ? "border-b-4 border-red-400 text-red-600"
                : "text-gray-600 hover:text-gray-800"
            }`}
          >
            신고 ({reports.length})
          </button>
        </div>

        {/* 당첨번호 입력 탭 */}
        {(activeTab === "lotto" || activeTab === "pension" || activeTab === "speeto") && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
            {/* 입력 폼 */}
            <div className="bg-white rounded-xl shadow-lg p-6">
            <h2 className="text-2xl font-bold mb-6 text-gray-800">당첨번호 입력</h2>

            {/* 이미지 업로드 */}
            <div className="mb-6 p-4 bg-blue-50 rounded-lg border-2 border-blue-300">
              <label className="block text-sm font-bold text-gray-700 mb-3">📸 로또 사진 업로드 (자동 인식)</label>
              <input
                type="file"
                accept="image/*"
                onChange={handleImageUpload}
                disabled={imageProcessing}
                className="w-full px-4 py-2 border-2 border-gray-300 rounded-lg focus:border-blue-400 focus:outline-none"
              />
              {imageProcessing && <p className="text-sm text-blue-600 mt-2">🔄 이미지 분석 중...</p>}
            </div>

            <form onSubmit={handleSave} className="space-y-4">

              <div>
                <label className="block text-sm font-bold text-gray-700 mb-2">회차</label>
                <input
                  type="number"
                  value={round}
                  onChange={(e) => setRound(e.target.value)}
                  className="w-full px-4 py-2 border-2 border-gray-300 rounded-lg focus:border-yellow-400 focus:outline-none"
                  placeholder="예: 1220"
                />
              </div>

              <div>
                <label className="block text-sm font-bold text-gray-700 mb-2">당첨 날짜</label>
                <input
                  type="date"
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                  className="w-full px-4 py-2 border-2 border-gray-300 rounded-lg focus:border-yellow-400 focus:outline-none"
                />
              </div>

              {/* 로또 & 스피또 */}
              {activeTab !== "pension" && (
                <>
                  <div>
                    <label className="block text-sm font-bold text-gray-700 mb-3">로또 번호</label>
                    <div className="grid grid-cols-3 gap-2">
                      {[0, 1, 2, 3, 4, 5].map((index) => (
                        <input
                          key={index}
                          type="number"
                          value={numbers[index] || ""}
                          onChange={(e) => {
                            const newNumbers = [...numbers];
                            newNumbers[index] = parseInt(e.target.value) || 0;
                            setNumbers(newNumbers);
                          }}
                          min="1"
                          max="45"
                          className="px-3 py-2 border-2 border-gray-300 rounded-lg focus:border-yellow-400 focus:outline-none text-center"
                          placeholder={`번호 ${index + 1}`}
                        />
                      ))}
                    </div>
                  </div>

                  <div>
                    <label className="block text-sm font-bold text-gray-700 mb-2">보너스 번호</label>
                    <input
                      type="number"
                      value={bonus}
                      onChange={(e) => setBonus(e.target.value)}
                      min="1"
                      max="45"
                      className="w-full px-4 py-2 border-2 border-gray-300 rounded-lg focus:border-yellow-400 focus:outline-none"
                      placeholder="보너스"
                    />
                  </div>
                </>
              )}

              {/* 연금복권 */}
              {activeTab === "pension" && (
                <div className="space-y-4">
                  {/* 1등 조 입력 */}
                  <div>
                    <label className="block text-sm font-bold text-gray-700 mb-2">1등 조</label>
                    <input
                      type="text"
                      value={pensionGroup}
                      onChange={(e) => setPensionGroup(e.target.value)}
                      placeholder="예: 2조"
                      className="w-full px-4 py-2 border-2 border-gray-300 rounded-lg focus:border-blue-400 focus:outline-none"
                    />
                  </div>

                  {/* 1등 숫자 입력 (6개) - 이것으로 2등~7등이 자동 생성됨 */}
                  <div>
                    <label className="block text-sm font-bold text-gray-700 mb-3">1등 당첨번호 (6개)</label>
                    <div className="grid grid-cols-3 gap-2">
                      {[0, 1, 2, 3, 4, 5].map((index) => (
                        <input
                          key={index}
                          type="number"
                          value={pensionRank1[index] === 0 ? "" : pensionRank1[index]}
                          onChange={(e) => {
                            const newRank1 = [...pensionRank1];
                            newRank1[index] = parseInt(e.target.value) || 0;
                            setPensionRank1(newRank1);
                          }}
                          min="0"
                          max="9"
                          className="px-3 py-2 border-2 border-blue-300 rounded-lg focus:border-blue-600 focus:outline-none text-center font-bold"
                          placeholder="0"
                        />
                      ))}
                    </div>
                    <p className="text-xs text-gray-500 mt-2">💡 1등 숫자를 입력하면 2등~7등이 자동으로 분류됩니다</p>
                  </div>

                  {/* 자동 생성된 2등~7등 미리보기 */}
                  {pensionRank1.some(n => n !== 0) && (
                    <div className="bg-blue-50 p-4 rounded-lg border-2 border-blue-200 space-y-2">
                      <p className="text-sm font-bold text-gray-700">자동 분류된 당첨번호:</p>
                      {Object.entries(generatePensionWinners()).map(([rank, data]) => (
                        <div key={rank} className="flex gap-2 items-center text-sm">
                          <span className="font-bold w-12">{rank}</span>
                          <span className="bg-gray-200 px-2 py-1 rounded text-xs font-bold w-16">{data.group}</span>
                          <div className="flex gap-1">
                            {data.balls.map((num, idx) => (
                              <span key={idx} className="bg-yellow-400 text-gray-800 rounded-full w-6 h-6 flex items-center justify-center text-xs font-bold">
                                {num}
                              </span>
                            ))}
                          </div>
                        </div>
                      ))}
                    </div>
                  )}

                  {/* 보너스 (조 없음, 6개 숫자만) */}
                  <div>
                    <label className="block text-sm font-bold text-gray-700 mb-3">보너스 (6개)</label>
                    <div className="grid grid-cols-3 gap-2">
                      {[0, 1, 2, 3, 4, 5].map((index) => (
                        <input
                          key={index}
                          type="number"
                          value={pensionBonus[index] === 0 ? "" : pensionBonus[index]}
                          onChange={(e) => {
                            const newBonus = [...pensionBonus];
                            newBonus[index] = parseInt(e.target.value) || 0;
                            setPensionBonus(newBonus);
                          }}
                          min="0"
                          max="9"
                          className="px-3 py-2 border-2 border-green-300 rounded-lg focus:border-green-600 focus:outline-none text-center font-bold"
                          placeholder="0"
                        />
                      ))}
                    </div>
                  </div>
                </div>
              )}

              <button
                type="submit"
                disabled={saving}
                className="w-full bg-yellow-400 hover:bg-yellow-500 disabled:bg-gray-400 text-yellow-900 font-bold py-2 px-4 rounded-lg transition"
              >
                {saving ? "저장 중..." : "저장하기"}
              </button>
            </form>

            {message && (
              <div className="mt-4 p-3 bg-gray-100 rounded-lg text-center font-bold text-gray-800">
                {message}
              </div>
            )}
          </div>

          {/* 기록 목록 */}
          <div className="bg-white rounded-xl shadow-lg p-6">
            <h2 className="text-2xl font-bold mb-6 text-gray-800">
              {activeTab === "lotto" ? "로또 기록" : activeTab === "pension" ? "연금 기록" : "스피또 기록"}
            </h2>
            {loading ? (
              <p className="text-center text-gray-500">로딩 중...</p>
            ) : records.length === 0 ? (
              <p className="text-center text-gray-500">기록이 없습니다</p>
            ) : (
              <div className="space-y-4 max-h-96 overflow-y-auto">
                {records && Array.isArray(records) && records.map((record: any) => (
                  <div
                    key={record.id}
                    className="p-4 border-2 border-yellow-300 rounded-lg bg-yellow-50"
                  >
                    <div className="flex justify-between items-start mb-3">
                      <div>
                        <p className="font-bold text-lg text-gray-800">
                          {activeTab === "lotto" ? "로또" : activeTab === "pension" ? "연금복권" : "스피또"} {record.round}회
                        </p>
                        <p className="text-sm text-gray-600">{record.date}</p>
                      </div>
                      <button
                        onClick={() => handleDelete(record.id)}
                        className="bg-red-500 hover:bg-red-600 text-white font-bold py-1 px-3 rounded transition"
                      >
                        삭제
                      </button>
                    </div>

                    {/* 로또 데이터 */}
                    {record.numbers && Array.isArray(record.numbers) && (
                      <div className="flex gap-2 flex-wrap">
                        {record.numbers.map((num: number) => (
                          <span
                            key={num}
                            className={`${getNumberColor(num)} text-white rounded-full w-10 h-10 flex items-center justify-center font-bold text-sm`}
                          >
                            {num}
                          </span>
                        ))}
                        <span className="text-gray-400 flex items-center text-sm font-bold">+</span>
                        <span className="bg-green-500 text-white rounded-full w-10 h-10 flex items-center justify-center font-bold text-sm">
                          {record.bonus}
                        </span>
                      </div>
                    )}

                    {/* 연금복권 데이터 - winners 구조 */}
                    {record.winners && typeof record.winners === "object" && (
                      <div className="space-y-3">
                        {["1등", "2등", "3등", "4등", "5등", "6등", "7등"].map((rank) => (
                          record.winners[rank] && (
                            <div key={rank} className={`p-3 rounded ${
                              rank === "1등" ? "bg-blue-50 border-l-4 border-blue-600" : "bg-yellow-50 border-l-4 border-yellow-400"
                            }`}>
                              <div className="flex items-center justify-between mb-2">
                                <p className="text-sm font-bold text-gray-700">{rank}</p>
                                <p className={`text-xs font-bold px-2 py-1 rounded ${
                                  rank === "1등" ? "bg-blue-200 text-blue-800" : "bg-yellow-200 text-yellow-800"
                                }`}>{record.winners[rank].group}</p>
                              </div>
                              {record.winners[rank].balls && Array.isArray(record.winners[rank].balls) && record.winners[rank].balls.length > 0 && (
                                <div className="flex gap-1 flex-wrap">
                                  {record.winners[rank].balls.map((num: number, idx: number) => (
                                    <span
                                      key={idx}
                                      className={`text-white rounded-full w-8 h-8 flex items-center justify-center font-bold text-xs ${
                                        rank === "1등" ? "bg-blue-600" : "bg-yellow-400 text-gray-800"
                                      }`}
                                    >
                                      {num}
                                    </span>
                                  ))}
                                </div>
                              )}
                            </div>
                          )
                        ))}

                        {/* 보너스 공 표시 */}
                        {record.bonus && Array.isArray(record.bonus) && record.bonus.length > 0 && (
                          <div className="p-3 bg-green-50 rounded border-l-4 border-green-600">
                            <p className="text-sm font-bold text-gray-700 mb-2">보너스</p>
                            <div className="flex gap-1 flex-wrap">
                              {record.bonus.map((num: number, idx: number) => (
                                <span
                                  key={idx}
                                  className="bg-green-600 text-white rounded-full w-8 h-8 flex items-center justify-center font-bold text-xs"
                                >
                                  {num}
                                </span>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    )}

                    {/* 연금복권 데이터 - 구 구조 (balls 직접) */}
                    {record.balls && typeof record.balls === "object" && !record.winners && (
                      <div className="space-y-3">
                        {/* 1등 - 조 표시 */}
                        {record.group && (
                          <div className="p-2 bg-blue-50 rounded">
                            <p className="text-sm font-bold text-gray-700">1등</p>
                            <p className="text-base font-bold text-blue-600">{record.group}</p>
                          </div>
                        )}

                        {/* 2등~7등 공 표시 */}
                        {["2등", "3등", "4등", "5등", "6등", "7등"].map((rank) => (
                          record.balls[rank] && Array.isArray(record.balls[rank]) && record.balls[rank].length > 0 && (
                            <div key={rank} className="p-2 bg-gray-50 rounded">
                              <p className="text-sm font-bold text-gray-700 mb-2">{rank}</p>
                              <div className="flex gap-1 flex-wrap">
                                {record.balls[rank].map((num: number, idx: number) => (
                                  <span
                                    key={idx}
                                    className="bg-yellow-400 text-gray-800 rounded-full w-8 h-8 flex items-center justify-center font-bold text-xs"
                                  >
                                    {num}
                                  </span>
                                ))}
                              </div>
                            </div>
                          )
                        ))}

                        {/* 보너스 공 표시 */}
                        {record.bonus && Array.isArray(record.bonus) && record.bonus.length > 0 && (
                          <div className="p-2 bg-green-50 rounded">
                            <p className="text-sm font-bold text-gray-700 mb-2">보너스</p>
                            <div className="flex gap-1 flex-wrap">
                              {record.bonus.map((num: number, idx: number) => (
                                <span
                                  key={idx}
                                  className="bg-green-500 text-white rounded-full w-8 h-8 flex items-center justify-center font-bold text-xs"
                                >
                                  {num}
                                </span>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
        )}

        {/* 크롤링 데이터 탭 */}
        {activeTab === "upload" && (
          <div className="bg-white rounded-xl shadow-lg p-6">
            <h2 className="text-2xl font-bold mb-6 text-gray-800">크롤링 데이터 업로드</h2>
            <div className="p-6 bg-green-50 rounded-lg border-2 border-green-300">
              <label className="block text-sm font-bold text-gray-700 mb-3">
                📁 winner_stores.json 파일 선택
              </label>
              <input
                type="file"
                accept=".json"
                onChange={handleJsonFileUpload}
                disabled={saving}
                className="w-full px-4 py-3 border-2 border-gray-300 rounded-lg focus:border-green-400 focus:outline-none cursor-pointer"
              />
              <p className="text-xs text-gray-600 mt-3">
                💡 크롤링한 winner_stores.json 파일을 업로드하면 자동으로 stores와 win_history에 저장됩니다.
              </p>
              {saving && <p className="text-sm text-green-600 mt-2">⏳ 업로드 중...</p>}
              {message && activeTab === "upload" && (
                <div className="mt-4 p-3 bg-white rounded-lg text-center font-bold text-gray-800">
                  {message}
                </div>
              )}
            </div>
          </div>
        )}

        {/* 신고 탭 */}
        {activeTab === "reports" && (
          <div className="bg-white rounded-xl shadow-lg p-6">
            <h2 className="text-2xl font-bold mb-6 text-gray-800">신고 내역</h2>
            {loading ? (
              <p className="text-center text-gray-500">로딩 중...</p>
            ) : reports.length === 0 ? (
              <p className="text-center text-gray-500">신고가 없습니다</p>
            ) : (
              <div className="space-y-4">
                {/* 신고 목록 */}
                {!selectedReport && (
                  <div className="space-y-3 max-h-96 overflow-y-auto">
                    {reports.map((report) => (
                      <button
                        key={report.id}
                        onClick={() => setSelectedReport(report)}
                        className="w-full p-4 border-2 border-red-300 rounded-lg bg-red-50 hover:bg-red-100 transition text-left"
                      >
                        <p className="font-bold text-gray-800">{report.store_name}</p>
                        <p className="text-sm text-gray-600 mb-2">{report.address}</p>
                        <p className="text-xs text-gray-500">
                          {new Date(report.createdAt?.toDate?.() || report.createdAt).toLocaleString()}
                        </p>
                      </button>
                    ))}
                  </div>
                )}

                {/* 신고 상세 */}
                {selectedReport && (
                  <div className="p-6 border-2 border-red-400 rounded-lg bg-red-50">
                    <button
                      onClick={() => setSelectedReport(null)}
                      className="mb-4 text-blue-600 hover:text-blue-800 font-bold"
                    >
                      ← 목록으로
                    </button>
                    <div className="mb-4">
                      <p className="text-2xl font-bold text-gray-800 mb-2">
                        {selectedReport.store_name}
                      </p>
                      <p className="text-gray-600 mb-4">{selectedReport.address}</p>
                      <p className="text-xs text-gray-500 mb-6">
                        {new Date(selectedReport.createdAt?.toDate?.() || selectedReport.createdAt).toLocaleString()}
                      </p>
                    </div>
                    <div className="bg-white rounded-lg p-4 mb-6">
                      <p className="text-sm font-bold text-gray-700 mb-2">신고 내용</p>
                      <p className="text-gray-700 whitespace-pre-wrap">{selectedReport.content}</p>
                    </div>
                    <button
                      onClick={() => handleReportProcessed(selectedReport.id)}
                      className="w-full bg-green-500 hover:bg-green-600 text-white font-bold py-3 px-6 rounded-lg transition"
                    >
                      ✓ 처리 완료
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
