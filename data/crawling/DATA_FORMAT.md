# 당첨지점 데이터 표준 양식 (누적 데이터 포함)

## 저장 파일명
- `lotto_stores_{round}.json` - 로또 당첨지점
- `pension_stores_{round}.json` - 연금복권 당첨지점  
- `speeto_stores_{round}.json` - 스피또 당첨지점

## 데이터 구조 (JSON 배열)

```json
[
  {
    "lottery_type": "lotto",
    "round": 1220,
    "rank": 1,
    "store_name": "황금복권마트",
    "address": "경기 이천시 증신로325번길 5 1층",
    "method": "자동",
    "region": "경기",
    "lat": 37.299417,
    "lng": 127.43798,
    
    "total_wins": 5,
    "rank1_wins": 2,
    "rank2_wins": 3,
    "win_history": [
      { "round": 1220, "rank": 1, "date": "2026-04-25" },
      { "round": 1215, "rank": 2, "date": "2026-03-21" }
    ],
    "last_win_round": 1220,
    "last_win_date": "2026-04-25",
    "days_since_last_win": 0,
    
    "naver_map_url": "https://map.naver.com/v5/search/황금복권마트",
    "kakao_map_url": "https://map.kakao.com/link/search/황금복권마트",
    
    "crawled_at": "2026-04-25T12:34:56Z"
  }
]
```

## 필드 설명

### 기본 정보
| 필드 | 타입 | 필수 | 설명 | 예시 |
|------|------|------|------|------|
| `lottery_type` | string | ✅ | 복권 종류 | `"lotto"` \| `"pension"` \| `"speeto"` |
| `round` | number | ✅ | 회차 번호 | `1220` |
| `rank` | number | ✅ | 상금등급 | `1` \| `2` |
| `store_name` | string | ✅ | 판매점명 | `"황금복권마트"` |
| `address` | string | ✅ | 주소 | `"경기 이천시 증신로325번길 5 1층"` |
| `method` | string | ✅ | 구매방식 | `"자동"` \| `"반자동"` \| `"수동"` \| `"없음"` |
| `region` | string | ✅ | 광역시도 | `"경기"` |
| `lat` | number | ❌ | 위도 | `37.299417` |
| `lng` | number | ❌ | 경도 | `127.43798` |

### 누적 당첨 데이터
| 필드 | 타입 | 설명 | 예시 |
|------|------|------|------|
| `total_wins` | number | 총 당첨 횟수 | `5` |
| `rank1_wins` | number | 1등 당첨 횟수 | `2` |
| `rank2_wins` | number | 2등 당첨 횟수 | `3` |
| `win_history` | array | 당첨 이력 배열 | `[{round, rank, date}]` |
| `last_win_round` | number | 최근 당첨 회차 | `1220` |
| `last_win_date` | string | 최근 당첨 날짜 (YYYY-MM-DD) | `"2026-04-25"` |
| `days_since_last_win` | number | 최근 당첨 이후 경과일 | `0`, `7`, `14` |

### 외부 링크
| 필드 | 타입 | 설명 | 예시 |
|------|------|------|------|
| `naver_map_url` | string | 네이버지도 링크 | `"https://map.naver.com/v5/search/..."` |
| `kakao_map_url` | string | 카카오지도 링크 | `"https://map.kakao.com/link/search/..."` |

### 기타
| 필드 | 타입 | 설명 |
|------|------|------|
| `crawled_at` | string | 수집 시간 (ISO 8601) |

## 수집 로직

### 1. 공식 페이지 크롤링
```
https://dhlottery.co.kr/gameResult.do?method=viewResult&drwNo={round}&gameName=LO
```

### 2. 데이터 추출
- 당첨지점명, 주소, 판매방식 → HTML 파싱
- 지역 → 주소에서 추출
- 좌표 → 지오코딩 (나중)

### 3. 누적 데이터 계산
- Firebase에서 기존 당첨 기록 조회
- 신규 당첨 지점 추가
- 기존 지점의 당첨 횟수 업데이트
- win_history에 새로운 당첨 기록 추가

### 4. 외부 링크 생성
```
네이버: https://map.naver.com/v5/search/{store_name}
카카오: https://map.kakao.com/link/search/{store_name}
```
