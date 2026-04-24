"use client";

import dynamic from "next/dynamic";
import { useEffect, useRef, useState } from "react";
import { db } from "@/lib/firebase";
import { collection, getDocs } from "firebase/firestore";
import { useRouter } from "next/navigation";

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

interface StoreWithDistance extends Store {
  distance: number;
}

const MapContent = dynamic(() => import("@/components/MapContent"), { ssr: false });

export default function MapPage() {
  const [stores, setStores] = useState<StoreWithDistance[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedStore, setSelectedStore] = useState<StoreWithDistance | null>(null);
  const router = useRouter();

  // 거리 계산 (Haversine 공식)
  const calculateDistance = (lat1: number, lng1: number, lat2: number, lng2: number) => {
    const R = 6371; // 지구 반지름 (km)
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLng = ((lng2 - lng1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLng / 2) *
        Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  };

  useEffect(() => {
    const loadData = async () => {
      try {
        // 로컬 캐시 확인 (1시간마다만 새로 로드)
        const cachedData = localStorage.getItem("storesCache");
        const cachedTime = localStorage.getItem("storesCacheTime");
        const now = Date.now();

        let allStoresRaw: Store[] = [];

        if (cachedData && cachedTime && now - parseInt(cachedTime) < 3600000) {
          // 캐시 사용 (1시간 이내)
          allStoresRaw = JSON.parse(cachedData);
        } else {
          // 캐시 없거나 만료됨 → Firestore에서 로드
          const snapshot = await getDocs(collection(db, "stores"));
          allStoresRaw = snapshot.docs
            .map((doc) => doc.data() as Store)
            .filter((store) => store.lat && store.lng);

          // 캐시 저장
          localStorage.setItem("storesCache", JSON.stringify(allStoresRaw));
          localStorage.setItem("storesCacheTime", now.toString());
        }

        // 중복 제거 (store_id 기준)
        const seenIds = new Set<string>();
        const allStores = allStoresRaw.filter((store) => {
          if (seenIds.has(store.store_id)) return false;
          seenIds.add(store.store_id);
          return true;
        });

        // 기본 위치 (서울 시청)
        let latitude = 37.5665;
        let longitude = 126.978;

        // 사용자 위치 가져오기 시도 (타임아웃 3초)
        if ("geolocation" in navigator) {
          const locationPromise = new Promise<{ latitude: number; longitude: number }>((resolve) => {
            navigator.geolocation.getCurrentPosition(
              (position) => {
                latitude = position.coords.latitude;
                longitude = position.coords.longitude;
                resolve({ latitude, longitude });
              },
              () => {
                resolve({ latitude, longitude });
              }
            );

            setTimeout(() => {
              resolve({ latitude, longitude });
            }, 3000);
          });

          await locationPromise;
        }

        // 거리 계산
        const storesData = allStores
          .map((store) => ({
            ...store,
            distance: calculateDistance(latitude, longitude, store.lat!, store.lng!),
          }))
          .sort((a, b) => a.distance - b.distance);

        setStores(storesData);
        setLoading(false);
      } catch (error) {
        console.error("데이터 로딩 에러:", error);
        setLoading(false);
      }
    };

    loadData();
  }, []);

  if (loading) return <div className="p-8 text-center">지도 로딩 중...</div>;

  return <MapContent stores={stores} />;
}
