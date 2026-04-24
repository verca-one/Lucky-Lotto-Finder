"use client";

import { useEffect, useState } from "react";
import { db } from "@/lib/firebase";
import { collection, getDocs, query, where, orderBy } from "firebase/firestore";
import { useRouter } from "next/navigation";

interface Rule {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
}

interface WinHistory {
  numbers?: number[];
  crawled_at?: string;
}

interface RecommendedNumbers {
  rule_id: string;
  rule_name: string;
  numbers: number[];
  reason: string;
}

export default function RecommendationPage() {
  const [rules, setRules] = useState<Rule[]>([]);
  const [recommendations, setRecommendations] = useState<RecommendedNumbers[]>([]);
  const [selectedRule, setSelectedRule] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  // AI 추천 번호 생성 함수
  const generateRecommendation = (
    ruleName: string,
    historyData: WinHistory[]
  ): { numbers: number[]; reason: string } => {
    // 모든 번호 빈도 계산
    const numberCount: { [key: number]: number } = {};
    const allNumbers = new Set<number>();

    historyData.forEach((h) => {
      if (h.numbers) {
        h.numbers.forEach((num) => {
          numberCount[num] = (numberCount[num] || 0) + 1;
          allNumbers.add(num);
        });
      }
    });

    // 규칙별 추천 번호 생성
    if (ruleName.includes("핫") || ruleName.includes("자주")) {
      // 가장 자주 나온 번호
      const sorted = Object.entries(numberCount)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 6)
        .map((item) => parseInt(item[0]));

      return {
        numbers: sorted.length === 6 ? sorted : [],
        reason: "최근 당첨 데이터에서 가장 자주 나온 번호들입니다.",
      };
    } else if (ruleName.includes("균형")) {
      // 홀짝, 고저 균형
      const sorted = Object.entries(numberCount)
        .sort((a, b) => b[1] - a[1])
        .map((item) => parseInt(item[0]));

      // 홀짝 균형 (홀수 3개, 짝수 3개)
      const odd = sorted.filter((n) => n % 2 === 1).slice(0, 3);
      const even = sorted.filter((n) => n % 2 === 0).slice(0, 3);
      const balanced = [...odd, ...even].sort((a, b) => a - b);

      return {
        numbers: balanced.length === 6 ? balanced : [],
        reason: "홀짝과 고저가 균형잡힌 번호입니다.",
      };
    } else if (ruleName.includes("최신")) {
      // 최근 30일
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

      const recentNumbers: { [key: number]: number } = {};
      historyData
        .filter((h) => {
          const hDate = new Date(h.crawled_at || "");
          return hDate > thirtyDaysAgo;
        })
        .forEach((h) => {
          if (h.numbers) {
            h.numbers.forEach((num) => {
              recentNumbers[num] = (recentNumbers[num] || 0) + 1;
            });
          }
        });

      const sorted = Object.entries(recentNumbers)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 6)
        .map((item) => parseInt(item[0]));

      return {
        numbers: sorted.length === 6 ? sorted : [],
        reason: "최근 30일 당첨 데이터로 분석한 번호입니다.",
      };
    } else if (ruleName.includes("중간")) {
      // 중간대 번호 (15~30)
      const midNumbers = Object.entries(numberCount)
        .filter((item) => {
          const num = parseInt(item[0]);
          return num >= 15 && num <= 30;
        })
        .sort((a, b) => b[1] - a[1])
        .slice(0, 6)
        .map((item) => parseInt(item[0]))
        .sort((a, b) => a - b);

      return {
        numbers: midNumbers.length === 6 ? midNumbers : [],
        reason: "중간대(15~30번) 번호 위주로 추천합니다.",
      };
    }

    // 기본: 랜덤
    const randomNumbers = Array.from(allNumbers)
      .sort((a, b) => (numberCount[b] || 0) - (numberCount[a] || 0))
      .slice(0, 6);

    return {
      numbers: randomNumbers.length === 6 ? randomNumbers : [],
      reason: "통계 기반 추천 번호입니다.",
    };
  };

  useEffect(() => {
    const fetchData = async () => {
      // 1. 활성화된 규칙 조회
      const rulesSnapshot = await getDocs(
        query(collection(db, "admin_rules"), where("enabled", "==", true))
      );
      const rulesData = rulesSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      } as Rule));
      setRules(rulesData);

      // 2. 당첨 번호 데이터 조회
      const historySnapshot = await getDocs(collection(db, "win_history"));
      const historyData = historySnapshot.docs.map((doc) => doc.data() as WinHistory);

      // 3. 각 규칙별 추천 번호 생성
      const recs: RecommendedNumbers[] = rulesData.map((rule) => {
        const { numbers, reason } = generateRecommendation(rule.name, historyData);
        return {
          rule_id: rule.id,
          rule_name: rule.name,
          numbers,
          reason,
        };
      });

      setRecommendations(recs);
      if (recs.length > 0) {
        setSelectedRule(recs[0].rule_id);
      }

      setLoading(false);
    };

    fetchData();
  }, []);

  if (loading) return <div className="p-8 text-center">로딩 중...</div>;

  const selectedRecommendation = recommendations.find(
    (r) => r.rule_id === selectedRule
  );

  return (
    <div className="bg-gradient-to-br from-purple-50 to-indigo-100 p-6">
      {/* 규칙 선택 */}
      {rules.length === 0 ? (
        <div className="bg-white rounded-xl shadow p-8 text-center mb-6">
          <p className="text-gray-500 mb-4">추천 규칙이 없습니다.</p>
          <p className="text-sm text-gray-400">
            관리자가 규칙을 추가하면 추천 번호를 받을 수 있습니다.
          </p>
        </div>
      ) : (
        <>
          {/* 규칙 탭 */}
          <div className="bg-white rounded-xl shadow p-4 mb-6 overflow-x-auto">
            <div className="flex gap-2">
              {rules.map((rule) => (
                <button
                  key={rule.id}
                  onClick={() => setSelectedRule(rule.id)}
                  className={`px-4 py-2 rounded-lg whitespace-nowrap font-medium transition ${
                    selectedRule === rule.id
                      ? "bg-purple-500 text-white shadow-lg"
                      : "bg-gray-100 text-gray-700 hover:bg-gray-200"
                  }`}
                >
                  {rule.name}
                </button>
              ))}
            </div>
          </div>

          {/* 추천 번호 */}
          {selectedRecommendation && selectedRecommendation.numbers.length > 0 ? (
            <div className="bg-white rounded-xl shadow-lg p-8 mb-6">
              <h2 className="text-xl font-bold mb-2 text-center">
                {selectedRecommendation.rule_name}
              </h2>
              <p className="text-sm text-gray-600 text-center mb-8">
                {selectedRecommendation.reason}
              </p>

              {/* 번호 표시 */}
              <div className="grid grid-cols-6 gap-3 mb-8">
                {selectedRecommendation.numbers.map((num, idx) => (
                  <div
                    key={idx}
                    className="bg-gradient-to-br from-purple-400 to-purple-600 rounded-full w-16 h-16 flex items-center justify-center mx-auto shadow-lg hover:shadow-xl transform hover:scale-110 transition"
                  >
                    <span className="text-white font-bold text-2xl">{num}</span>
                  </div>
                ))}
              </div>

              {/* 번호 복사 */}
              <button
                onClick={() => {
                  const numberText = selectedRecommendation.numbers.join(", ");
                  navigator.clipboard.writeText(numberText);
                  alert("번호가 복사되었습니다!");
                }}
                className="w-full bg-purple-500 text-white font-bold py-4 rounded-lg hover:bg-purple-600 transition shadow-lg"
              >
                📋 번호 복사
              </button>
            </div>
          ) : (
            <div className="bg-white rounded-xl shadow p-8 text-center mb-6">
              <p className="text-gray-500">추천 번호를 생성할 수 없습니다.</p>
              <p className="text-sm text-gray-400 mt-2">
                충분한 데이터가 필요합니다.
              </p>
            </div>
          )}

          {/* 규칙 설명 */}
          <div className="space-y-3">
            {rules.map((rule) => (
              <div
                key={rule.id}
                className="bg-white rounded-lg shadow p-4 border-l-4 border-purple-500"
              >
                <p className="font-bold text-sm">{rule.name}</p>
                {rule.description && (
                  <p className="text-xs text-gray-600 mt-1">{rule.description}</p>
                )}
              </div>
            ))}
          </div>

          {/* 팁 */}
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mt-6">
            <p className="text-sm font-bold text-blue-900 mb-2">💡 팁</p>
            <ul className="text-xs text-blue-800 space-y-1">
              <li>• 여러 규칙의 추천 번호를 참고해보세요</li>
              <li>• 관리자가 추가한 규칙들을 활용하세요</li>
              <li>• 추천은 통계 기반이며, 당첨을 보장하지 않습니다</li>
            </ul>
          </div>
        </>
      )}
    </div>
  );
}
