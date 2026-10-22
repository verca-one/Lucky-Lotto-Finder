// 스피또 브리핑 — 관리자 엔진 브리핑 '스피또' 탭 · 일반 모드 추천 '스피또' 탭
// 현재 DB 의 스피또 '1등 판매점' 기록은 회차마다 같은 판매점 목록이 반복 저장돼 회차별 연구에 쓸 수 없다 (2026-10-22 확인).
// 기존 스피또 크롤러는 건드리지 않는다. 회차별 1등 판매점 · 게임별 판매 현황(출고율 · 남은 1등) 수집이 승인되면 영역을 채운다.
import 'package:flutter/material.dart';

const kSpeettoColor = Color(0xFF00897B);

class SpeettoBriefingView extends StatelessWidget {
  final bool admin;
  const SpeettoBriefingView({super.key, this.admin = true});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('스피또 500 · 1000 · 2000', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          Text('스피또 추천', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        ]),
      ),
      const SizedBox(height: 12),
      _area('1', '스피또 명당', admin
          ? '데이터 미확보 — DB 의 스피또 1등 판매점 기록이 회차마다 같은 판매점 목록으로 반복 저장되어 있습니다 '
              '(예: 스피또1000 50회·100회 모두 같은 589곳). 회차별 1등 판매점을 다시 받아야 명당 연구를 할 수 있습니다.'
          : '스피또 명당 추천을 준비하고 있습니다.'),
      const SizedBox(height: 12),
      _area('2', '게임별 판매 현황 (출고율 · 남은 1등)', admin
          ? '데이터 미확보 — 출고율이 높은데 1등이 많이 남은 게임일수록 한 장의 기대가 올라갑니다. 서버 수집 승인 후 표시합니다.'
          : '게임별 남은 1등 정보를 준비하고 있습니다.'),
      if (admin) ...[
        const SizedBox(height: 12),
        _area('3', '스피또 가설 트랙 — 제미나이', '위 두 데이터가 생기면 제미나이 스피또 가설로 게임·명당을 고릅니다.'),
      ],
      if (admin) ...[
        const SizedBox(height: 12),
        Text('기존 스피또 크롤러·테이블은 건드리지 않습니다. 새 수집은 서버(GitHub Actions)에서 별도 파일로만 하며, 승인 후 진행합니다.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
      ],
    ]);
  }

  Widget _area(String no, String title, String text) => Container(
        key: ValueKey('speetto_area_$no'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kSpeettoColor.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 26, height: 26, alignment: Alignment.center,
              decoration: BoxDecoration(color: kSpeettoColor, borderRadius: BorderRadius.circular(8)),
              child: Text(no, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.45)),
        ]),
      );
}
