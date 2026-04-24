"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

interface Store {
  store_id: string;
  store_name: string;
  address: string;
  lat?: number;
  lng?: number;
  lotto_wins?: number[];
  pension_wins?: number[];
}

interface StoreWithDistance extends Store {
  distance: number;
}

interface Props {
  stores: StoreWithDistance[];
}

export default function MapContent({ stores }: Props) {
  const mapRef = useRef<HTMLDivElement>(null);
  const mapInstance = useRef<any>(null);
  const [selectedStore, setSelectedStore] = useState<StoreWithDistance | null>(null);
  const [areaStores, setAreaStores] = useState<StoreWithDistance[]>([]);
  const [showSearchButton, setShowSearchButton] = useState(false);
  const [showList, setShowList] = useState(false);
  const [showReportModal, setShowReportModal] = useState(false);
  const [reportReasons, setReportReasons] = useState<string[]>([]);
  const [reportStore, setReportStore] = useState<StoreWithDistance | null>(null);
  const [reportSubmitting, setReportSubmitting] = useState(false);
  const router = useRouter();

  const goToCurrentLocation = () => {
    if (mapInstance.current && "geolocation" in navigator) {
      navigator.geolocation.getCurrentPosition((position) => {
        const { latitude, longitude } = position.coords;
        mapInstance.current.setView([latitude, longitude], 15);
      });
    }
  };

  const handleReportSubmit = async () => {
    if (reportReasons.length === 0 || !reportStore) {
      alert("신고 항목을 선택해주세요");
      return;
    }

    setReportSubmitting(true);
    try {
      const { addDoc, collection, serverTimestamp } = await import("firebase/firestore");
      const { db: firebaseDb } = await import("@/lib/firebase");

      await addDoc(collection(firebaseDb, "reports"), {
        store_id: reportStore.store_id,
        store_name: reportStore.store_name,
        address: reportStore.address,
        content: reportReasons.join(", "),
        createdAt: new Date(),
      });
      alert("신고가 접수되었습니다");
      setReportReasons([]);
      setShowReportModal(false);
      setReportStore(null);
    } catch (error) {
      console.error("신고 실패:", error);
      alert("신고 접수에 실패했습니다");
    } finally {
      setReportSubmitting(false);
    }
  };

  const markerGroupRef = useRef<any>(null);
  const leafletRef = useRef<any>(null);
  const markersRef = useRef<Map<string, any>>(new Map());

  const updateMapMarkers = (map: any, L: any, storesToShow: StoreWithDistance[]) => {
    // 기존 마커들 제거
    if (markerGroupRef.current) {
      markerGroupRef.current.clearLayers();
    } else {
      markerGroupRef.current = L.featureGroup().addTo(map);
    }

    // 마커 맵 초기화
    markersRef.current.clear();

    // 상위 20개만 표시 (성능 최적화)
    const visibleStores = storesToShow.slice(0, 20);

    // 파란색 마커 아이콘
    const blueIcon = L.icon({
      iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
      shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      shadowSize: [41, 41]
    });

    // 새 마커 추가 (파란 마커 핀)
    visibleStores.forEach((store) => {
      const totalWins = (store.lotto_wins?.length || 0) + (store.pension_wins?.length || 0);
      const marker = L.marker([store.lat!, store.lng!], { icon: blueIcon })
        .addTo(markerGroupRef.current)
        .bindPopup(
          `<div style="padding: 10px; width: 240px;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
              <strong style="font-size: 15px;">${store.store_name}</strong>
              <span style="font-size: 12px; color: #666;">${store.distance.toFixed(1)}km</span>
            </div>
            <div style="background: #f0f0f0; padding: 8px; border-radius: 4px; margin-bottom: 8px; font-size: 12px;">
              <div style="margin-bottom: 4px;"><strong>로또:</strong> 1등 ${(store.lotto_wins?.filter((w: any) => w.rank === 1).length || 0)}회, 2등 ${(store.lotto_wins?.filter((w: any) => w.rank === 2).length || 0)}회</div>
              <div><strong>연금:</strong> ${store.pension_wins?.length || 0}회</div>
            </div>
            <div style="display: flex; gap: 6px; margin-bottom: 8px;">
              <button onclick="window.open('https://map.naver.com/?lat=${store.lat}&lng=${store.lng}&title=${store.store_name}', '_blank')" style="background: #2DBE60; color: white; border: none; padding: 6px; border-radius: 3px; font-size: 10px; cursor: pointer; flex: 1;">네이버지도</button>
              <button onclick="window.open('https://map.kakao.com/link/map/${store.store_name},${store.lat},${store.lng}', '_blank')" style="background: #FFE812; color: #333; border: none; padding: 6px; border-radius: 3px; font-size: 10px; cursor: pointer; flex: 1;">카카오지도</button>
            </div>
            <button class="map-report-btn" data-store-id="${store.store_id}" data-store-name="${store.store_name}" data-store-address="${store.address}" style="width: 100%; background: #EF4444; color: white; border: none; padding: 8px; border-radius: 3px; font-size: 10px; cursor: pointer; font-weight: bold;">📢 신고하기</button>
          </div>`,
          { maxWidth: 260 }
        );

      // 마커 저장
      markersRef.current.set(store.store_id, marker);

      // Popup 열릴 때 신고 버튼 이벤트 리스너 추가
      marker.on('popupopen', () => {
        const reportBtn = document.querySelector(`[data-store-id="${store.store_id}"]`) as HTMLButtonElement;
        if (reportBtn) {
          reportBtn.addEventListener('click', () => {
            setReportStore(store);
            setShowReportModal(true);
            marker.closePopup();
          });
        }
      });
    });
  };

  useEffect(() => {
    const initMap = async () => {
      if (!mapRef.current) return;

      try {
        const L = (await import("leaflet")).default;
        await import("leaflet/dist/leaflet.css");
        leafletRef.current = L;

        if (mapInstance.current) return;

        // 기본 위치
        const latitude = stores.length > 0 ? stores[0].lat || 37.5665 : 37.5665;
        const longitude = stores.length > 0 ? stores[0].lng || 126.978 : 126.978;

        const map = L.map(mapRef.current, {
          zoomControl: false,
          minZoom: 10,
          maxZoom: 19,
        }).setView([latitude, longitude], 13);

        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution: "&copy; OpenStreetMap contributors",
          maxZoom: 19,
        }).addTo(map);

        // 확대 버튼만 추가 (축소 버튼 제외)
        L.control.zoom({ position: 'topright' }).addTo(map);

        // 초기에는 마커 표시 안함 (버튼 클릭 시 표시)

        // 거리 계산
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

        // 지도 이동/줌 시 마커 업데이트
        const updateMarkers = () => {
          const bounds = map.getBounds();
          const center = map.getCenter();
          const zoom = map.getZoom();

          let inBoundsStores: StoreWithDistance[] = [];

          if (zoom >= 13) {
            // 줌인 상태: 현재 보이는 bounds 내의 모든 판매점
            inBoundsStores = stores.filter((store) => {
              const lat = store.lat!;
              const lng = store.lng!;
              return bounds.contains([lat, lng]);
            });
          } else {
            // 줌아웃 상태: 화면 중앙의 20% 범위만 (약 20km)
            inBoundsStores = stores.filter((store) => {
              const distance = calculateDistance(center.lat, center.lng, store.lat!, store.lng!);
              return distance <= 20; // 20km 범위
            });
          }

          if (inBoundsStores.length > 0) {
            setAreaStores(inBoundsStores);
            setShowSearchButton(true);
            updateMapMarkers(map, L, inBoundsStores);
          } else {
            setShowSearchButton(false);
            updateMapMarkers(map, L, []);
          }
        };

        map.on("moveend", updateMarkers);
        map.on("zoom", updateMarkers);

        // 현재위치 버튼 추가
        const LocationControl = L.Control.extend({
          onAdd: () => {
            const container = L.DomUtil.create("div", "leaflet-bar leaflet-control");
            container.style.backgroundColor = "white";
            container.style.border = "2px solid rgba(0,0,0,0.2)";
            container.style.borderRadius = "4px";

            const button = L.DomUtil.create("a", "", container);
            button.href = "#";
            button.title = "현재위치로 이동";
            button.innerHTML = "◉";
            button.style.width = "36px";
            button.style.height = "36px";
            button.style.lineHeight = "36px";
            button.style.textAlign = "center";
            button.style.textDecoration = "none";
            button.style.color = "#2563eb";
            button.style.display = "block";
            button.style.fontSize = "20px";
            button.style.fontWeight = "bold";

            L.DomEvent.on(button, "click", (e) => {
              L.DomEvent.preventDefault(e);
              goToCurrentLocation();
            });

            return container;
          },
        });

        new LocationControl({ position: "bottomright" }).addTo(map);

        mapInstance.current = map;
      } catch (error) {
        console.error("지도 초기화 에러:", error);
      }
    };

    initMap();
  }, [stores]);

  // 중복 제거 (store_id와 store_name으로 확인)
  const uniqueStores = (storeList: StoreWithDistance[]) => {
    const seen = new Set<string>();
    return storeList.filter((store) => {
      // store_id로 먼저 확인
      if (seen.has(store.store_id)) return false;
      seen.add(store.store_id);

      // store_name으로도 확인 (같은 이름이면 첫 번째만 표시)
      if (seen.has(`name:${store.store_name}`)) return false;
      seen.add(`name:${store.store_name}`);

      return true;
    });
  };

  const displayStores = showSearchButton && areaStores.length > 0
    ? uniqueStores(areaStores).filter(store => store.lat && store.lng).slice(0, 20)
    : uniqueStores(stores).filter(store => store.lat && store.lng).slice(0, 20);

  const displayTitle = showSearchButton && areaStores.length > 0
    ? `📍 이 지역의 당첨판매점 (${displayStores.length}개)`
    : "📍 근처 당첨판매점";

  return (
    <div className="bg-gray-100 flex flex-col h-full">
      {/* 지도 */}
      <div ref={mapRef} style={{ height: "50vh", width: "100%" }} />

      {/* 지역 검색 버튼 (지도 상단 중앙) */}
      <button
        onClick={() => {
          if (mapInstance.current && leafletRef.current) {
            const bounds = mapInstance.current.getBounds();
            const center = mapInstance.current.getCenter();
            const zoom = mapInstance.current.getZoom();
            const L = leafletRef.current;

            // 거리 계산 함수
            const calculateDistance = (lat1: number, lng1: number, lat2: number, lng2: number) => {
              const R = 6371;
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

            let inBoundsStores: StoreWithDistance[] = [];

            // 3km 범위 내의 판매점 검색
            inBoundsStores = stores.filter((store) => {
              const distance = calculateDistance(center.lat, center.lng, store.lat!, store.lng!);
              return distance <= 3;
            });

            if (inBoundsStores.length > 0) {
              setAreaStores(inBoundsStores);
              setShowSearchButton(true);
              updateMapMarkers(mapInstance.current, L, inBoundsStores);
            }
          }
        }}
        style={{ zIndex: 9999, top: "80px" }}
        className="fixed left-1/2 transform -translate-x-1/2 bg-blue-500 text-white px-6 py-2 rounded-lg font-bold hover:bg-blue-600 shadow-lg"
      >
        🔍 주변 검색
      </button>

      {/* 하단 지점 목록 */}
      <div className="bg-white shadow-lg rounded-t-2xl p-4 overflow-y-auto flex-1">
        <h2 className="font-bold mb-3">{displayTitle}</h2>
        <div className="space-y-2">
          {displayStores.map((store, idx) => (
            <div
              key={store.store_id}
              onClick={() => {
                if (mapInstance.current && store.lat && store.lng) {
                  mapInstance.current.setView([store.lat, store.lng], 16);
                  // 지도 이동 후 팝업 열기 (더 긴 딜레이)
                  setTimeout(() => {
                    try {
                      if (!mapInstance.current || !mapInstance.current._container) return;

                      let marker = markersRef.current.get(store.store_id);
                      if (!marker && leafletRef.current && mapInstance.current) {
                        // 마커가 없으면 새로 생성
                        const L = leafletRef.current;
                        const totalWins = (store.lotto_wins?.length || 0) + (store.pension_wins?.length || 0);
                        const blueIcon = L.icon({
                          iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
                          shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
                          iconSize: [25, 41],
                          iconAnchor: [12, 41],
                          popupAnchor: [1, -34],
                          shadowSize: [41, 41]
                        });
                        marker = L.marker([store.lat!, store.lng!], { icon: blueIcon })
                          .addTo(mapInstance.current)
                          .bindPopup(
                            `<div style="padding: 10px; width: 240px;">
                              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                                <strong style="font-size: 15px;">${store.store_name}</strong>
                                <span style="font-size: 12px; color: #666;">${store.distance.toFixed(1)}km</span>
                              </div>
                              <div style="background: #f0f0f0; padding: 8px; border-radius: 4px; margin-bottom: 8px; font-size: 12px;">
                                <div style="margin-bottom: 4px;"><strong>로또:</strong> 1등 ${(store.lotto_wins?.filter((w: any) => w.rank === 1).length || 0)}회, 2등 ${(store.lotto_wins?.filter((w: any) => w.rank === 2).length || 0)}회</div>
                                <div><strong>연금:</strong> ${store.pension_wins?.length || 0}회</div>
                              </div>
                              <div style="display: flex; gap: 6px;">
                                <button onclick="window.open('https://map.naver.com/?lat=${store.lat}&lng=${store.lng}&title=${store.store_name}', '_blank')" style="background: #2DBE60; color: white; border: none; padding: 6px; border-radius: 3px; font-size: 10px; cursor: pointer; flex: 1;">네이버지도</button>
                                <button onclick="window.open('https://map.kakao.com/link/map/${store.store_name},${store.lat},${store.lng}', '_blank')" style="background: #FFE812; color: #333; border: none; padding: 6px; border-radius: 3px; font-size: 10px; cursor: pointer; flex: 1;">카카오지도</button>
                              </div>
                            </div>`,
                            { maxWidth: 260 }
                          );
                        markersRef.current.set(store.store_id, marker);
                      }
                      if (marker && mapInstance.current) {
                        marker.openPopup();
                      }
                    } catch (error) {
                      console.error('팝업 열기 오류:', error);
                    }
                  }, 500);
                }
              }}
              className="bg-gray-50 p-3 rounded-lg cursor-pointer hover:bg-blue-50 transition border-l-4 border-yellow-400"
            >
              <div className="flex justify-between items-start">
                <div className="flex-1">
                  <p className="font-bold text-sm">
                    {idx + 1}. {store.store_name}
                  </p>
                  <p className="text-xs text-gray-500">{store.address}</p>

                  {/* 배지 - 주소 바로 아래 */}
                  <div className="flex gap-2 mt-2 flex-wrap">
                    {(store.lotto_wins?.filter((w: any) => w.rank === 1).length || 0) > 0 && (
                      <span className="bg-yellow-500 text-white px-2 py-1 rounded text-xs font-bold">
                        로또1등 {store.lotto_wins?.filter((w: any) => w.rank === 1).length}회
                      </span>
                    )}
                    {(store.lotto_wins?.filter((w: any) => w.rank === 2).length || 0) > 0 && (
                      <span className="bg-red-500 text-white px-2 py-1 rounded text-xs font-bold">
                        로또2등 {store.lotto_wins?.filter((w: any) => w.rank === 2).length}회
                      </span>
                    )}
                    {(store.pension_wins?.length || 0) > 0 && (
                      <span className="bg-blue-500 text-white px-2 py-1 rounded text-xs font-bold">
                        연금 {store.pension_wins?.length}회
                      </span>
                    )}
                  </div>

                  {/* 분석 정보 */}
                  {(store.lotto_wins?.length || 0) > 0 && (() => {
                    // 회차 정보가 있는 당첨 기록 필터링
                    const winsWithDrawNumber = store.lotto_wins?.filter((w: any) => w.draw_number) || [];
                    let intervalText = '';

                    if (winsWithDrawNumber.length >= 2) {
                      // 회차 간격 계산
                      const drawNumbers = winsWithDrawNumber
                        .map((w: any) => w.draw_number)
                        .sort((a: number, b: number) => b - a); // 내림차순 정렬

                      const intervals: number[] = [];
                      for (let i = 0; i < drawNumbers.length - 1; i++) {
                        intervals.push(drawNumbers[i] - drawNumbers[i + 1]);
                      }

                      // 평균 간격 계산
                      const avgInterval = Math.round(intervals.reduce((a, b) => a + b, 0) / intervals.length);

                      // 간격이 일정한지 확인 (오차 범위 ±10%)
                      const isConsistent = intervals.every(
                        interval => Math.abs(interval - avgInterval) <= avgInterval * 0.1
                      );

                      intervalText = isConsistent
                        ? `${avgInterval}회 주기로 당첨됨`
                        : `약 ${avgInterval}회 간격으로 당첨됨`;
                    } else {
                      // 회차 정보가 없으면 총 개수 기반
                      intervalText = `약 ${Math.round(1220 / (store.lotto_wins?.length || 1))}회마다 당첨됨`;
                    }

                    return (
                      <div className="mt-2 text-xs text-orange-600 font-semibold">
                        📊 지난 당첨 기간패턴상 {intervalText}, 이번주 당첨확률있음
                      </div>
                    );
                  })()}
                </div>
                <div className="text-right">
                  <p className="font-bold text-blue-600">
                    {store.distance.toFixed(1)}km
                  </p>
                  <p className="text-xs text-gray-400">거리</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* 선택된 지점 상세 팝업 */}
      {selectedStore && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-end z-[9998]">
          <div className="bg-white w-full rounded-t-2xl p-6 max-h-96 overflow-y-auto">
            <div className="flex justify-between items-start mb-4">
              <div>
                <h2 className="text-2xl font-bold">{selectedStore.store_name}</h2>
                <p className="text-gray-600 text-sm mt-1">{selectedStore.address}</p>
              </div>
              <button
                onClick={() => setSelectedStore(null)}
                className="text-gray-400 hover:text-gray-600 text-2xl"
              >
                ✕
              </button>
            </div>

            <div className="grid grid-cols-2 gap-4 mb-6">
              <div className="bg-yellow-50 p-4 rounded-lg text-center">
                <p className="text-sm text-gray-600">로또</p>
                <p className="text-2xl font-bold text-yellow-600">
                  {selectedStore.lotto_wins?.length || 0}회
                </p>
              </div>
              <div className="bg-blue-50 p-4 rounded-lg text-center">
                <p className="text-sm text-gray-600">연금</p>
                <p className="text-2xl font-bold text-blue-600">
                  {selectedStore.pension_wins?.length || 0}회
                </p>
              </div>
            </div>

            <div className="space-y-3">
              <button
                onClick={() => {
                  const { lat, lng } = selectedStore;
                  window.open(
                    `https://map.kakao.com/link/map/${selectedStore.store_name},${lat},${lng}`,
                    "_blank"
                  );
                }}
                className="w-full bg-yellow-400 text-black py-3 rounded-lg font-bold hover:bg-yellow-500"
              >
                카카오맵으로 보기
              </button>
              <button
                onClick={() => {
                  const { lat, lng } = selectedStore;
                  window.open(
                    `https://map.naver.com/?lat=${lat}&lng=${lng}&title=${selectedStore.store_name}`,
                    "_blank"
                  );
                }}
                className="w-full bg-green-500 text-white py-3 rounded-lg font-bold hover:bg-green-600"
              >
                네이버맵으로 보기
              </button>
              <button
                onClick={() => router.push(`/${selectedStore.store_id}`)}
                className="w-full bg-blue-500 text-white py-3 rounded-lg font-bold hover:bg-blue-600"
              >
                상세 정보 보기
              </button>
              <button
                onClick={() => router.push(`/${selectedStore.store_id}?tab=report`)}
                className="w-full bg-red-500 text-white py-3 rounded-lg font-bold hover:bg-red-600"
              >
                🚨 신고하기
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 신고 모달 */}
      {showReportModal && reportStore && (
        <div className="fixed inset-0 bg-black bg-opacity-50 z-[9999] flex items-center justify-center p-4">
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
              <p className="font-bold text-gray-800">{reportStore.store_name}</p>
              <p className="text-sm text-gray-600 mb-4">{reportStore.address}</p>
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
