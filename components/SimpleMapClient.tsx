"use client";

import { useEffect, useRef } from "react";

interface SimpleMapProps {
  lat: number;
  lng: number;
  zoom?: number;
  onMarkerClick?: () => void;
}

export default function SimpleMapClient({ lat, lng, zoom = 15, onMarkerClick }: SimpleMapProps) {
  const mapRef = useRef<HTMLDivElement>(null);
  const mapInstance = useRef<any>(null);

  useEffect(() => {
    const initMap = async () => {
      if (!mapRef.current) return;

      // Leaflet 라이브러리 로드
      const L = (await import("leaflet")).default;
      await import("leaflet/dist/leaflet.css");

      if (!mapInstance.current) {
        // 지도 초기화
        const map = L.map(mapRef.current).setView([lat, lng], zoom);

        // OpenStreetMap 타일 레이어 추가
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution: '&copy; OpenStreetMap contributors',
          maxZoom: 19,
        }).addTo(map);

        // 마커 추가
        const marker = L.marker([lat, lng]).addTo(map);
        marker.bindPopup("당첨 지점");

        // 마커 클릭 이벤트
        if (onMarkerClick) {
          marker.on("click", onMarkerClick);
        }

        mapInstance.current = map;
      }
    };

    initMap();

    return () => {
      if (mapInstance.current) {
        mapInstance.current.remove();
        mapInstance.current = null;
      }
    };
  }, [lat, lng, zoom, onMarkerClick]);

  return <div ref={mapRef} style={{ width: "100%", height: "100%" }} />;
}
