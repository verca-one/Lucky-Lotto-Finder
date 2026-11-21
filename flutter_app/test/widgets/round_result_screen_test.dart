// 회차 상세 — 게임별 색 머리띠 · 회차 크게 · 추첨 전 안내 (네트워크 없이 그려지는 상태만)
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/round_result_screen.dart';
import 'package:flutter_app/services/round_status_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final type in ['lotto', 'pension']) {
    testWidgets('$type 추첨 전 — 머리띠 · 회차 · 안내 (작은 화면에서도 넘침 없음)', (t) async {
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: RoundResultScreen(card: RoundCardInfo(
          type: type, round: type == 'lotto' ? 1251 : 343, drawDate: DateTime(2026, 11, 21), status: RoundStatus.scheduled))));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('round_hero')), findsOneWidget);
      expect(find.text(type == 'lotto' ? '1251' : '343'), findsOneWidget);
      expect(find.text('아직 추첨 전입니다.'), findsOneWidget);
    });
  }
}
