"use client";

import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { useState } from "react";
import { useRouter } from "next/navigation";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const [showProfile, setShowProfile] = useState(false);
  const [profileName, setProfileName] = useState("");
  const router = useRouter();

  const handleProfileChange = (value: string) => {
    setProfileName(value);
    if (value === "공룡로또") {
      setShowProfile(false);
      setProfileName("");
      router.push("/admin");
    }
  };

  return (
    <html
      lang="ko"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="flex flex-col h-screen bg-gray-50 overflow-hidden">
        {/* 헤더 (고정) */}
        <header className="fixed top-0 left-0 right-0 bg-white shadow-md z-40 h-16 flex items-center px-4">
          <div className="flex-1">
            <h1 className="text-xl font-bold text-green-600">
              🍀 복권명당 {profileName && <span className="text-gray-600 text-lg ml-2">{profileName}</span>}
            </h1>
          </div>
          <button
            onClick={() => setShowProfile(!showProfile)}
            className="text-gray-600 text-2xl hover:text-gray-800 transition"
          >
            ⚙️
          </button>
        </header>

        {/* 프로필 모달 (중앙) */}
        {showProfile && (
          <div className="fixed inset-0 bg-black bg-opacity-50 z-[9997] flex items-center justify-center">
            <div className="bg-white rounded-2xl p-8 w-full max-w-sm shadow-xl">
              <div className="flex justify-between items-center mb-6">
                <h2 className="text-2xl font-bold">프로필 설정</h2>
                <button
                  onClick={() => setShowProfile(false)}
                  className="text-gray-600 text-2xl hover:text-gray-800"
                >
                  ✕
                </button>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-2">
                    프로필 이름
                  </label>
                  <input
                    type="text"
                    value={profileName}
                    onChange={(e) => {
                      const value = e.target.value;
                      setProfileName(value);
                      if (value === "공룡로또") {
                        setShowProfile(false);
                        router.push("/admin");
                      }
                    }}
                    placeholder="프로필 이름을 입력하세요"
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-green-500"
                    autoFocus
                  />
                </div>

                <button
                  onClick={() => {
                    setShowProfile(false);
                  }}
                  className="w-full bg-green-500 hover:bg-green-600 text-white font-bold py-2 px-4 rounded-lg transition"
                >
                  완료
                </button>
              </div>
            </div>
          </div>
        )}

        {/* 메인 콘텐츠 */}
        <main className="flex-1 overflow-y-auto pt-16 pb-24 mt-0">
          {children}
        </main>

        {/* 배너 광고 (고정) */}
        <div className="fixed bottom-16 left-0 right-0 bg-gradient-to-r from-blue-500 to-purple-600 h-20 flex items-center justify-center text-white font-bold shadow-lg z-30">
          📢 광고 배너
        </div>

        {/* 하단 메뉴 (고정) */}
        <nav className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-200 h-16 flex justify-around items-center z-40">
          <a href="/" className="flex flex-col items-center gap-1 flex-1 py-2 hover:bg-gray-50">
            <span className="text-2xl">📊</span>
            <span className="text-xs font-medium">홈</span>
          </a>
          <a href="/map" className="flex flex-col items-center gap-1 flex-1 py-2 hover:bg-gray-50">
            <span className="text-2xl">🗺️</span>
            <span className="text-xs font-medium">주변당첨지점</span>
          </a>
          <a href="/hotspots" className="flex flex-col items-center gap-1 flex-1 py-2 hover:bg-gray-50">
            <span className="text-2xl">📍</span>
            <span className="text-xs font-medium">지역별</span>
          </a>
          <a href="/recommendation" className="flex flex-col items-center gap-1 flex-1 py-2 hover:bg-gray-50">
            <span className="text-2xl">🎯</span>
            <span className="text-xs font-medium">추천</span>
          </a>
        </nav>
      </body>
    </html>
  );
}
