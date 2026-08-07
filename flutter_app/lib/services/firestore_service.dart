import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lotto_winning_number.dart';

/// Firebase Firestore - lotto_draws 컬렉션 단일 진실 공급원
class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'lotto_draws';

  // ── 저장 (관리자 전용) ────────────────────────────────────────
  static Future<void> saveLottoDraw(LottoWinningNumber item) async {
    await _db.collection(_col).doc('${item.round}').set({
      'round': item.round,
      'numbers': item.numbers,
      'bonus': item.bonusNumber,
      'drawDate': item.drawDate,
    });
  }

  // ── 삭제 (관리자 전용) ────────────────────────────────────────
  static Future<void> deleteLottoDraw(int round) async {
    await _db.collection(_col).doc('$round').delete();
  }

  // ── 전체 조회 (round 오름차순) ────────────────────────────────
  static Future<List<LottoWinningNumber>> getAllLottoDraws() async {
    final snap = await _db
        .collection(_col)
        .orderBy('round', descending: false)
        .get();
    return snap.docs.map(_docToModel).toList();
  }

  // ── 최신 회차 조회 ─────────────────────────────────────────────
  static Future<LottoWinningNumber?> getLatestDraw() async {
    final snap = await _db
        .collection(_col)
        .orderBy('round', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return _docToModel(snap.docs.first);
  }

  // ── 특정 회차 조회 ─────────────────────────────────────────────
  static Future<LottoWinningNumber?> getDrawByRound(int round) async {
    final doc = await _db.collection(_col).doc('$round').get();
    if (!doc.exists) return null;
    return _docToModel(doc);
  }

  static LottoWinningNumber _docToModel(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return LottoWinningNumber(
      round: (d['round'] as num).toInt(),
      numbers: (d['numbers'] as List<dynamic>).map((e) => (e as num).toInt()).toList(),
      bonusNumber: (d['bonus'] as num).toInt(),
      drawDate: d['drawDate'] as String? ?? '',
    );
  }
}
