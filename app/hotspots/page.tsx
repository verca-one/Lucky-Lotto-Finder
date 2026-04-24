"use client";

import { useEffect, useState } from "react";
import { db } from "@/lib/firebase";
import { collection, getDocs } from "firebase/firestore";
import { useRouter } from "next/navigation";

interface Store {
  store_id: string;
  store_name: string;
  address: string;
  region?: string;
  lotto_wins?: number[];
  pension_wins?: number[];
}

interface CityStats {
  city: string;
  stores: Array<Store & { totalWins: number; rank: number }>;
  totalWins: number;
}

interface RegionStats {
  region: string;
  cities: CityStats[];
  totalWins: number;
}

export default function HotspotsPage() {
  const [regionStats, setRegionStats] = useState<RegionStats[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedRegion, setExpandedRegion] = useState<string | null>(null);
  const [expandedCity, setExpandedCity] = useState<string | null>(null);
  const router = useRouter();

  // address에서 시/구 추출
  const extractCity = (address: string): string => {
    const parts = address.split(" ");
    if (parts.length > 1) {
      return parts[1]; // 두 번째 요소가 시/구 (예: "수원시", "강남구")
    }
    return "미분류";
  };

  useEffect(() => {
    const fetchData = async () => {
      const snapshot = await getDocs(collection(db, "stores"));
      const stores = snapshot.docs.map((doc) => doc.data() as Store);

      // 지역 > 시 별로 그룹화
      const regionMap = new Map<string, Map<string, Store[]>>();
      stores.forEach((store) => {
        const region = store.region || "미분류";
        const city = extractCity(store.address);

        if (!regionMap.has(region)) {
          regionMap.set(region, new Map());
        }
        const cityMap = regionMap.get(region)!;
        if (!cityMap.has(city)) {
          cityMap.set(city, []);
        }
        cityMap.get(city)!.push(store);
      });

      // 지역별 통계 계산
      const stats: RegionStats[] = [];
      regionMap.forEach((cityMap, region) => {
        const cities: CityStats[] = [];
        let regionTotal = 0;

        cityMap.forEach((storeList, city) => {
          const storesWithWins = storeList
            .map((store) => {
              const totalWins = (store.lotto_wins?.length || 0) + (store.pension_wins?.length || 0);
              return { ...store, totalWins };
            })
            .sort((a, b) => b.totalWins - a.totalWins)
            .map((store, idx) => ({ ...store, rank: idx + 1 }));

          const cityTotal = storesWithWins.reduce((sum, s) => sum + s.totalWins, 0);
          regionTotal += cityTotal;

          cities.push({
            city,
            stores: storesWithWins,
            totalWins: cityTotal,
          });
        });

        // 시별로 당첨 횟수로 정렬
        cities.sort((a, b) => b.totalWins - a.totalWins);

        stats.push({
          region,
          cities,
          totalWins: regionTotal,
        });
      });

      // 지역별 총 당첨 횟수로 정렬
      stats.sort((a, b) => b.totalWins - a.totalWins);
      setRegionStats(stats);
      setLoading(false);
    };

    fetchData();
  }, []);

  if (loading) return <div className="p-8 text-center">로딩 중...</div>;

  return (
    <div className="bg-gray-100 p-4">
      {/* 페이지 정보 */}
      <div className="mb-4">
        <p className="text-sm text-gray-600">총 {regionStats.length}개 지역</p>
      </div>

      {/* 지역별 목록 */}
      <div className="space-y-3">
        {regionStats.map((region) => (
          <div key={region.region} className="bg-white rounded-lg shadow overflow-hidden">
            {/* 지역 헤더 */}
            <button
              onClick={() =>
                setExpandedRegion(expandedRegion === region.region ? null : region.region)
              }
              className="w-full p-5 bg-gradient-to-r from-blue-600 to-blue-700 hover:from-blue-700 hover:to-blue-800 flex justify-between items-center transition"
            >
              <div className="text-left flex-1">
                <h2 className="text-2xl font-bold text-white">{region.region}</h2>
                <p className="text-sm text-blue-100 mt-1">
                  {region.cities.length}개 시/구 • 총 {region.totalWins}회 당첨
                </p>
              </div>
              <div className="text-right mr-4">
                <p className="text-4xl font-bold text-white">{region.totalWins}</p>
                <p className="text-xs text-blue-100">당첨</p>
              </div>
              <div className="text-3xl text-white">{expandedRegion === region.region ? "▼" : "▶"}</div>
            </button>

            {/* 시/구 목록 */}
            {expandedRegion === region.region && (
              <div className="divide-y">
                {region.cities.map((city) => (
                  <div key={`${region.region}-${city.city}`} className="overflow-hidden">
                    {/* 시/구 헤더 */}
                    <button
                      onClick={() => {
                        const cityKey = `${region.region}-${city.city}`;
                        setExpandedCity(expandedCity === cityKey ? null : cityKey);
                      }}
                      className="w-full p-4 bg-gray-100 hover:bg-gray-150 flex justify-between items-center transition border-l-4 border-gray-400 ml-2"
                    >
                      <div className="text-left flex-1 ml-3">
                        <h3 className="font-bold text-gray-700 text-sm">{city.city}</h3>
                        <p className="text-xs text-gray-500 mt-1">
                          {city.stores.length}개 지점 • 총 {city.totalWins}회 당첨
                        </p>
                      </div>
                      <div className="text-right mr-3">
                        <p className="font-bold text-gray-700 text-base">{city.totalWins}</p>
                      </div>
                      <div className="text-gray-600">
                        {expandedCity === `${region.region}-${city.city}` ? "▼" : "▶"}
                      </div>
                    </button>

                    {/* 지점 목록 */}
                    {expandedCity === `${region.region}-${city.city}` && (
                      <div className="divide-y bg-white">
                        {city.stores.map((store) => (
                          <div
                            key={store.store_id}
                            onClick={() => router.push(`/${store.store_id}`)}
                            className="p-4 hover:bg-gray-50 transition cursor-pointer border-l-4 border-transparent hover:border-blue-500"
                          >
                            <div className="flex items-start justify-between">
                              <div className="flex-1">
                                <div className="flex items-center gap-2 mb-1">
                                  <span className="bg-blue-600 text-white rounded-full w-6 h-6 flex items-center justify-center text-xs font-bold">
                                    {store.rank}
                                  </span>
                                  <span className="font-bold text-gray-800">{store.store_name}</span>
                                </div>
                                <p className="text-xs text-gray-500 ml-8">{store.address}</p>
                                <div className="flex gap-3 mt-2 ml-8">
                                  <span className="text-xs">
                                    <span className="font-bold text-yellow-600">로또</span> {store.lotto_wins?.length || 0}회
                                  </span>
                                  <span className="text-xs">
                                    <span className="font-bold text-blue-600">연금</span> {store.pension_wins?.length || 0}회
                                  </span>
                                </div>
                              </div>
                              <div className="text-right">
                                <p className="text-2xl font-bold text-blue-600">{store.totalWins}</p>
                                <p className="text-xs text-gray-400">당첨</p>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* 빈 상태 */}
      {regionStats.length === 0 && (
        <div className="text-center py-12">
          <p className="text-gray-500">데이터가 없습니다.</p>
        </div>
      )}
    </div>
  );
}
