// 공식 최종 예측 결정 규칙 (순수 함수) · 판매 마감 시각 · 출처 줄 단위 테스트 (DB 접근 없음)
import 'package:flutter_app/services/research/final_recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 1246회: 1245회까지 반영(latestDrawn 1245), 1246회 판매 마감 2026-10-17 20:00 KST
  final close1246 = DateTime.utc(2026, 10, 17, 11);
  final beforeDraw = DateTime.utc(2026, 10, 12, 3);
  final afterClose = DateTime.utc(2026, 10, 17, 12);

  group('decideOfficialAction', () {
    test('실측 상황: number_base 1245 학습, fr 은 1244 스냅샷만 → 추첨 전이면 1245 기준 새 스냅샷', () {
      final d = decideOfficialAction(
        targetRound: 1246, latestTrain: 1245, storedTrainings: const [1244], latestDrawn: 1245,
        salesCloseUtc: close1246, nowUtc: beforeDraw,
      );
      expect(d.action, OfficialAction.buildNew);
      expect(d.training, 1245);
      expect(d.isPreDraw, isTrue);
    });

    test('최신 학습 회차 스냅샷이 이미 있으면 그대로 사용 (새로 만들지 않음)', () {
      final d = decideOfficialAction(
        targetRound: 1246, latestTrain: 1245, storedTrainings: const [1245, 1244], latestDrawn: 1245,
        salesCloseUtc: close1246, nowUtc: beforeDraw,
      );
      expect(d.action, OfficialAction.useStored);
      expect(d.training, 1245);
    });

    test('추첨 후 저장된 최신 학습 스냅샷은 그대로 사용 (사전 실전 아님)', () {
      final d = decideOfficialAction(
        targetRound: 1245, latestTrain: 1244, storedTrainings: const [1244], latestDrawn: 1245,
      );
      expect(d.action, OfficialAction.useStored);
      expect(d.training, 1244);
      expect(d.isPreDraw, isFalse);
    });

    test('추첨 후 + 최신 학습 스냅샷 없음 → 재생성 없이 최신 저장본 (postDrawNoRebuild)', () {
      final d = decideOfficialAction(
        targetRound: 1245, latestTrain: 1244, storedTrainings: const [1243, 1242], latestDrawn: 1245,
      );
      expect(d.action, OfficialAction.latestStoredPostDraw);
      expect(d.training, 1243);
      expect(d.isPreDraw, isFalse);
    });

    test('판매 마감이 지났으면 당첨번호가 아직 DB 에 없어도 새로 만들지 않음', () {
      final d = decideOfficialAction(
        targetRound: 1246, latestTrain: 1245, storedTrainings: const [1244], latestDrawn: 1245,
        salesCloseUtc: close1246, nowUtc: afterClose,
      );
      expect(d.action, OfficialAction.latestStoredPostDraw);
      expect(d.training, 1244);
      expect(d.isPreDraw, isFalse);
    });

    test('최신 추첨 회차를 모르면(조회 실패) 새로 만들지 않고 최신 저장본, 추첨 후로 표시하지 않음', () {
      final d = decideOfficialAction(
        targetRound: 1246, latestTrain: 1245, storedTrainings: const [1244], latestDrawn: null,
      );
      expect(d.action, OfficialAction.latestStored);
      expect(d.training, 1244);
      expect(d.isPreDraw, isFalse);
    });

    test('추첨 전 · 기본 후보 없음 + 직전 회차 이전 저장본만 → 엔진 반영 대기 (이전 학습 번호로 대체하지 않음)', () {
      final d = decideOfficialAction(
        targetRound: 1246, latestTrain: null, storedTrainings: const [1243, 1244], latestDrawn: 1245,
        salesCloseUtc: close1246, nowUtc: beforeDraw,
      );
      expect(d.action, OfficialAction.awaitingEngine);
      expect(d.training, isNull);
    });

    test('추첨 후 · 기본 후보 없음 + 저장본 있음 → 재생성 없이 최신 저장본', () {
      final d = decideOfficialAction(
        targetRound: 1245, latestTrain: null, storedTrainings: const [1243, 1244], latestDrawn: 1245,
      );
      expect(d.action, OfficialAction.latestStoredPostDraw);
      expect(d.training, 1244);
    });

    test('실측 사고: 1246회 추첨 후 엔진이 1246회를 반영하기 전 → 1247회는 1245회 학습 번호를 쓰지 않고 대기', () {
      final close1247 = DateTime.utc(2026, 10, 24, 11);
      final sunday = DateTime.utc(2026, 10, 17, 20);
      final d = decideOfficialAction(
        targetRound: 1247, latestTrain: 1245, storedTrainings: const [1244, 1245], latestDrawn: 1246,
        salesCloseUtc: close1247, nowUtc: sunday,
      );
      expect(d.action, OfficialAction.awaitingEngine);
      expect(d.isPreDraw, isTrue);
      // 엔진이 1246회까지 학습한 기본 후보를 만들면 그때 1247회 공식 번호 생성
      final d2 = decideOfficialAction(
        targetRound: 1247, latestTrain: 1246, storedTrainings: const [1244, 1245], latestDrawn: 1246,
        salesCloseUtc: close1247, nowUtc: sunday,
      );
      expect(d2.action, OfficialAction.buildNew);
      expect(d2.training, 1246);
    });

    test('아무것도 없으면 준비 중 (다른 회차로 대체하지 않음)', () {
      final d = decideOfficialAction(
        targetRound: 1251, latestTrain: null, storedTrainings: const [], latestDrawn: 1245,
      );
      expect(d.action, OfficialAction.awaitingEngine); // 추첨 전 미래 회차 — 직전 회차 반영 대기
      expect(d.training, isNull);
    });

    test('추첨 후 + 기본 후보만 있고 저장본 없음 → 준비 중 (사후 생성 금지)', () {
      final d = decideOfficialAction(
        targetRound: 1245, latestTrain: 1244, storedTrainings: const [], latestDrawn: 1245,
      );
      expect(d.action, OfficialAction.preparing);
    });

    test('두 회차 이상 뒤(1247~1251)는 직전 회차가 추첨·반영되기 전까지 공식 번호 없음', () {
      for (final t in [1247, 1248, 1249, 1250, 1251]) {
        final d = decideOfficialAction(
          targetRound: t, latestTrain: 1245, storedTrainings: const [1244, 1245], latestDrawn: 1245,
          salesCloseUtc: lottoSalesCloseUtc(t, knownRound: 1245, knownDrawDate: '2026-10-10'), nowUtc: beforeDraw,
        );
        expect(d.action, OfficialAction.awaitingEngine, reason: '$t');
        expect(d.training, isNull, reason: '$t');
        expect(d.isPreDraw, isTrue, reason: '$t');
      }
    });
  });

  group('lottoSalesCloseUtc', () {
    test('기준 회차 추첨일에서 주 단위 · 토 20:00 KST(11:00 UTC)', () {
      expect(lottoSalesCloseUtc(1246, knownRound: 1245, knownDrawDate: '2026-10-10'), DateTime.utc(2026, 10, 17, 11));
      expect(lottoSalesCloseUtc(1251, knownRound: 1245, knownDrawDate: '2026.10.10'), DateTime.utc(2026, 11, 21, 11));
    });
    test('해석 불가 = null', () {
      expect(lottoSalesCloseUtc(1246, knownRound: 1245, knownDrawDate: ''), isNull);
    });
  });

  group('출처 줄', () {
    FinalRecommendation rec({String? id}) => FinalRecommendation(
          targetRound: 1246, trainingEndRound: 1245, version: kFinalRecVersion, baseModelVersion: '2.1',
          generatedAt: DateTime.utc(2026, 10, 12, 3, 4), baseGeneratedAt: DateTime.utc(2026, 10, 11, 11, 10),
          sets: const [[1, 2, 3, 4, 5, 6]], setScores: const [1.0], pool: const [], rules: const [], signals: const {},
          verifiedEdge: false, note: '', snapshotId: id,
        );
    OfficialPrediction official({String? id, String status = kOfficialStatusOk}) => OfficialPrediction(
          status: status, action: OfficialAction.useStored, targetRound: 1246, isPreDraw: true,
          rec: rec(id: id), latestTrain: 1245);

    test('관리자 출처 줄 — 버전 · 학습 → 목표 · 스냅샷 · 생성 시각', () {
      final o = official(id: '0f1e2d3c-aaaa-bbbb-cccc-123456789abc');
      expect(officialProvenanceLine(o),
          '공식 최종 추천번호 · fr-1.0 · 1245회까지 학습 → 1246회 · 스냅샷 #0f1e2d3c · 생성 '
          '${officialTimeLabel(DateTime.utc(2026, 10, 12, 3, 4))}');
    });

    test('저장 안 된 스냅샷은 미저장으로 표시', () {
      expect(officialProvenanceLine(official()), contains('스냅샷 미저장'));
    });

    test('일반 사용자 줄 — 엔진 내부 정보 없음', () {
      final line = officialPublicLine(official(id: 'abc'));
      expect(line, '1246회 · 1245회까지 반영');
      expect(line, isNot(contains('fr-')));
      expect(line, isNot(contains('스냅샷')));
      expect(line, isNot(contains('Number')));
    });

    test('추첨 후 재생성 안 함 상태 안내', () {
      final o = official(id: 'x', status: kOfficialStatusPostDraw);
      expect(o.postDrawNoRebuild, isTrue);
      expect(o.statusNote, contains('추첨 후'));
      expect(o.statusNote, isNot(contains('사전 실전')));
      expect(official(id: 'x').statusNote, isNull);
    });
  });
}
