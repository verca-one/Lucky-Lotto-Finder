// 홈 '최신 당첨 회차' 겹침 카드 — 로또·연금복권 회차 상태 판단 (각 게임 독립)
//
// 데이터 출처 (모두 읽기 전용):
//   round_crawl_status  회차별 수집 상태(stores_status)와 실제 수집 성공 시각(stores_crawled_at)
//   winning_history     회차별 당첨 판매점 기록 → '수집 완료'의 검증 조건
//   crawl_logs          최근 수집 실행 성공/실패 → 새 회차 '데이터 오류' 판단
//   lotto_winning_numbers / pension_winning_numbers  DB 추첨일 (없으면 공식 추첨 일정으로 계산)
//
// 추첨일 도래만으로 '업데이트 완료'로 표시하지 않는다. 과거 회차·업데이트 시각을 만들어 내지 않는다.
import '../widgets/home_round_header.dart' show lottoDrawDateFor, pensionDrawDateFor, parseDrawDate;
import 'supabase_service.dart';

enum RoundStatus {
  scheduled('추첨 예정'),
  awaiting('결과 대기'),
  complete('업데이트 완료'),
  error('데이터 오류');

  final String label;
  const RoundStatus(this.label);
}

/// 공식 추첨 일정 (KST): 로또 매주 토 20:35, 연금복권720+ 매주 목 19:05
DateTime drawDateOf(String type, int round) => type == 'pension' ? pensionDrawDateFor(round) : lottoDrawDateFor(round);

/// 추첨 시각 (UTC)
DateTime drawTimeUtc(String type, int round) {
  final d = drawDateOf(type, round);
  return type == 'pension'
      ? DateTime.utc(d.year, d.month, d.day, 19 - 9, 5)
      : DateTime.utc(d.year, d.month, d.day, 20 - 9, 35);
}

/// 지금 시각 기준 KST 날짜
DateTime kstToday(DateTime nowUtc) {
  final k = nowUtc.toUtc().add(const Duration(hours: 9));
  return DateTime(k.year, k.month, k.day);
}

class RoundCrawlRow {
  final int round;
  final String storesStatus; // success / pending / empty / failed
  final DateTime? crawledAt; // 실제 수집 성공 시각 (UTC)
  const RoundCrawlRow(this.round, this.storesStatus, this.crawledAt);
}

/// 한 게임(로또 또는 연금)의 서버 데이터
class GameRoundData {
  final String type; // 'lotto' | 'pension'
  final List<RoundCrawlRow> crawlRows;
  final Set<int> roundsWithWinners;
  final Map<int, DateTime> dbDrawDates;
  final int? fallbackLatestRound; // round_crawl_status를 못 읽을 때 winning_history 최신 회차
  final DateTime? lastRunSuccessAt; // crawl_logs 최근 성공 (UTC)
  final DateTime? lastRunFailureAt; // crawl_logs 최근 실패 (UTC)

  const GameRoundData({
    required this.type,
    this.crawlRows = const [],
    this.roundsWithWinners = const {},
    this.dbDrawDates = const {},
    this.fallbackLatestRound,
    this.lastRunSuccessAt,
    this.lastRunFailureAt,
  });
}

class RoundCardInfo {
  final String type;
  final int round;
  final DateTime drawDate;
  final RoundStatus status;
  final DateTime? updatedAt; // 서버의 실제 수집 성공 시각 (없으면 null — 만들지 않음)
  const RoundCardInfo({
    required this.type,
    required this.round,
    required this.drawDate,
    required this.status,
    this.updatedAt,
  });
}

class RoundPair {
  final RoundCardInfo front;
  final RoundCardInfo? back;
  const RoundPair(this.front, this.back);
}

/// 앞 카드 = 최신 목표 회차, 뒤 카드 = 직전 회차.
///   L = 수집·검증 완료된 최신 회차 (stores_status=success + 당첨 판매점 기록 존재)
///   D = 오늘(KST) 기준 추첨일이 도래한 최신 회차
///   D > L 이면 앞 = D (추첨 예정/결과 대기/데이터 오류), 뒤 = L
///   아니면 앞 = L (업데이트 완료), 뒤 = L-1
RoundPair? decideRoundPair(GameRoundData d, DateTime nowUtc) {
  final rows = {for (final r in d.crawlRows) r.round: r};
  bool verified(int round) => rows[round]?.storesStatus == 'success' && d.roundsWithWinners.contains(round);

  int? latest;
  for (final r in rows.keys) {
    if (verified(r) && (latest == null || r > latest)) latest = r;
  }
  latest ??= d.fallbackLatestRound;
  if (latest == null || latest <= 0) return null;

  DateTime drawDate(int round) => d.dbDrawDates[round] ?? drawDateOf(d.type, round);
  RoundCardInfo done(int round) => RoundCardInfo(
        type: d.type,
        round: round,
        drawDate: drawDate(round),
        status: RoundStatus.complete,
        updatedAt: rows[round]?.crawledAt,
      );

  final today = kstToday(nowUtc);
  var target = latest;
  while (!drawDateOf(d.type, target + 1).isAfter(today)) {
    target++;
  }

  if (target == latest) {
    return RoundPair(done(latest), latest > 1 ? done(latest - 1) : null);
  }

  final RoundStatus status;
  final row = rows[target];
  final drawn = !nowUtc.toUtc().isBefore(drawTimeUtc(d.type, target));
  final runFailed = d.lastRunFailureAt != null &&
      !d.lastRunFailureAt!.isBefore(drawTimeUtc(d.type, target)) &&
      (d.lastRunSuccessAt == null || d.lastRunSuccessAt!.isBefore(d.lastRunFailureAt!));
  if (!drawn) {
    status = RoundStatus.scheduled;
  } else if (row?.storesStatus == 'failed' || row?.storesStatus == 'success' || runFailed) {
    // failed = 수집 실패, success인데 당첨 판매점 기록 없음 = 검증 불일치
    status = RoundStatus.error;
  } else {
    status = RoundStatus.awaiting;
  }
  return RoundPair(
    RoundCardInfo(type: d.type, round: target, drawDate: drawDateOf(d.type, target), status: status),
    done(latest),
  );
}

/// Supabase 조회 (읽기 전용) — 게임별로 독립 조회
class RoundStatusService {
  static Future<GameRoundData> load(String type, {List<Map<String, dynamic>> crawlLogs = const []}) async {
    final rowsRaw = await SupabaseService.getRoundCrawlStatus(type, limit: 6);
    final rows = [
      for (final r in rowsRaw)
        RoundCrawlRow(
          (r['round'] as num).toInt(),
          (r['stores_status'] ?? '').toString(),
          DateTime.tryParse((r['stores_crawled_at'] ?? '').toString())?.toUtc(),
        ),
    ];
    final rounds = rows.map((r) => r.round).toList();
    int? fallback;
    if (rows.isEmpty) fallback = await SupabaseService.getLatestRound(type);
    final probe = [...rounds, if (fallback != null) ...[fallback, fallback - 1]];
    final results = await Future.wait([
      SupabaseService.getRoundsWithWinners(type, probe),
      SupabaseService.getDrawDates(type, probe),
    ]);
    final rawDates = results[1] as Map<int, String>;

    DateTime? lastOf(String status) {
      DateTime? best;
      for (final l in crawlLogs) {
        if (l['lottery_type'] != type || l['status'] != status) continue;
        final t = DateTime.tryParse((l['completed_at'] ?? l['started_at'] ?? '').toString())?.toUtc();
        if (t != null && (best == null || t.isAfter(best))) best = t;
      }
      return best;
    }

    return GameRoundData(
      type: type,
      crawlRows: rows,
      roundsWithWinners: results[0] as Set<int>,
      dbDrawDates: {
        for (final e in rawDates.entries)
          if (parseDrawDate(e.value) != null) e.key: parseDrawDate(e.value)!,
      },
      fallbackLatestRound: fallback,
      lastRunSuccessAt: lastOf('success'),
      lastRunFailureAt: lastOf('failure') ?? lastOf('failed'),
    );
  }
}
