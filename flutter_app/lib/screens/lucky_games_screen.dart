// 복권연구 — 행운 게임 6개 (폰 안에서만 돎 · 서버 · 연구 데이터와 무관, '번호 맞히기'만 지난 당첨번호를 읽음)
//   로또 공 뽑기 · 긁는 복권 · 번호 맞히기 · 행운 룰렛 · 모의 추첨 · 오늘의 운세 번호
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/lotto_winning_number.dart';
import '../services/research/briefing_hit_check.dart' show lottoRank;
import '../services/supabase_service.dart';
import '../widgets/purchase_recommend_card.dart' show lottoBall;

// ── 공통 ─────────────────────────────────────────────────────────
class _Game {
  final String emoji, title, sub;
  final List<Color> colors;
  final Widget Function() page;
  const _Game(this.emoji, this.title, this.sub, this.colors, this.page);
}

final _games = <_Game>[
  _Game('🎱', '로또 공 뽑기', '추첨기를 돌려 공 6개를', [Color(0xFFFFE29F), Color(0xFFFFA99F)], () => const BallDrawGame()),
  _Game('🪙', '긁는 복권', '같은 그림 3개면 당첨!', [Color(0xFFC2E9FB), Color(0xFFA1C4FD)], () => const ScratchGame()),
  _Game('🎯', '번호 맞히기', '지난 회차를 몇 개나?', [Color(0xFFD4FC79), Color(0xFF96E6A1)], () => const GuessGame()),
  _Game('🎡', '행운 룰렛', '돌려서 행운 숫자 모으기', [Color(0xFFFBC2EB), Color(0xFFA6C1EE)], () => const RouletteGame()),
  _Game('🧪', '모의 추첨', '내 번호로 1,000번 추첨', [Color(0xFFE0C3FC), Color(0xFF8EC5FC)], () => const SimulateGame()),
  _Game('🔮', '오늘의 운세 번호', '생일로 보는 오늘의 운', [Color(0xFFFFDDE1), Color(0xFFEE9CA7)], () => const FortuneGame()),
];

const _ink = Color(0xFF3D3A50);

/// 복권연구 탭의 게임 카드 6개 (2열)
class LuckyGamesGrid extends StatelessWidget {
  const LuckyGamesGrid({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('lucky_games'),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🍀 행운 놀이터', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 2),
          Text('가볍게 즐기는 로또 게임이에요. 결과는 재미로만 봐 주세요!', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.98,
            children: [for (final g in _games) _card(context, g)],
          ),
        ]),
      );

  Widget _card(BuildContext context, _Game g) => GestureDetector(
        key: ValueKey('game_${g.title}'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _GamePage(game: g, child: g.page()))),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: g.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: g.colors.last.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52, height: 52, alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), shape: BoxShape.circle),
              child: Text(g.emoji, style: const TextStyle(fontSize: 28)),
            ),
            const Spacer(),
            Text(g.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 2),
            Text(g.sub, style: TextStyle(fontSize: 11.5, color: _ink.withValues(alpha: 0.7))),
          ]),
        ),
      );
}

class _GamePage extends StatelessWidget {
  final _Game game;
  final Widget child;
  const _GamePage({required this.game, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFFFBF5),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: _ink,
          title: Text('${game.emoji} ${game.title}', style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
          flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: game.colors))),
        ),
        body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: child)),
      );
}

Widget _cuteButton(String text, VoidCallback? onTap, {Color color = const Color(0xFFFF8A65), Key? key}) => SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        key: key,
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
    );

Widget _panel(Widget child, {Color color = Colors.white}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );

List<int> randomSix(Random rng) => (List<int>.generate(45, (i) => i + 1)..shuffle(rng)).take(6).toList()..sort();

/// 1~45 중 6개 고르기
class NumberPicker extends StatelessWidget {
  final Set<int> picked;
  final ValueChanged<int> onTap;
  final Set<int> hit;
  const NumberPicker({super.key, required this.picked, required this.onTap, this.hit = const {}});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (var n = 1; n <= 45; n++)
            GestureDetector(
              key: ValueKey('pick_$n'),
              onTap: () => onTap(n),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hit.contains(n) ? const Color(0xFFFFC107) : picked.contains(n) ? const Color(0xFF7E57C2) : const Color(0xFFF1EEF8),
                ),
                child: Text('$n', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                    color: picked.contains(n) || hit.contains(n) ? Colors.white : _ink.withValues(alpha: 0.75))),
              ),
            ),
        ],
      );
}

Set<int> _toggle(Set<int> s, int n) => s.contains(n) ? ({...s}..remove(n)) : s.length >= 6 ? s : {...s, n};

// ── 1. 로또 공 뽑기 ──────────────────────────────────────────────
class BallDrawGame extends StatefulWidget {
  const BallDrawGame({super.key});
  @override
  State<BallDrawGame> createState() => _BallDrawGameState();
}

class _BallDrawGameState extends State<BallDrawGame> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final _rng = Random();
  List<int> _target = const [];
  int _shown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _spin.dispose();
    super.dispose();
  }

  void _draw() {
    _timer?.cancel();
    setState(() {
      _target = randomSix(_rng);
      _shown = 0;
    });
    _spin.repeat();
    _timer = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (!mounted) return t.cancel();
      setState(() => _shown++);
      if (_shown >= 6) {
        t.cancel();
        _spin.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _panel(Column(children: [
          AnimatedBuilder(
            animation: _spin,
            builder: (_, _) => SizedBox(
              width: 200, height: 200,
              child: Stack(alignment: Alignment.center, children: [
                Container(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE3F2FD),
                    border: Border.all(color: const Color(0xFF90CAF9), width: 4))),
                for (var i = 0; i < 12; i++)
                  Transform.translate(
                    offset: Offset(cos(i * 0.52 + _spin.value * 2 * pi * (i.isEven ? 1 : -1)) * 60,
                        sin(i * 0.9 + _spin.value * 2 * pi) * 55),
                    child: Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle,
                        color: [Colors.amber, Colors.blue, Colors.red, Colors.grey, Colors.green][i % 5].withValues(alpha: 0.85))),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 6; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedScale(
                    scale: i < _shown ? 1 : 0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.elasticOut,
                    child: _target.length > i ? lottoBall(_target[i], size: 42) : const SizedBox(width: 42),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Text(_shown >= 6 ? '짜잔! 오늘의 공이에요 ✨' : _target.isEmpty ? '버튼을 눌러 추첨기를 돌려 보세요' : '두근두근… ${_shown + 1}번째 공',
              style: TextStyle(fontSize: 13, color: _ink.withValues(alpha: 0.7))),
        ])),
        const SizedBox(height: 18),
        _cuteButton(_target.isEmpty || _shown >= 6 ? '추첨기 돌리기' : '뽑는 중…', _target.isNotEmpty && _shown < 6 ? null : _draw,
            key: const ValueKey('ball_draw')),
      ]);
}

// ── 2. 긁는 복권 ────────────────────────────────────────────────
const _symbols = ['🍀', '💰', '⭐', '🐷', '💎'];

/// 6칸 그림 — 약 1/3 확률로 같은 그림 3개 이상 (당첨)
List<String> scratchCells(Random rng) {
  final win = rng.nextDouble() < 0.33;
  final out = <String>[];
  if (win) {
    final s = _symbols[rng.nextInt(_symbols.length)];
    out.addAll([s, s, s]);
  }
  while (out.length < 6) {
    final s = _symbols[rng.nextInt(_symbols.length)];
    if (!win && out.where((x) => x == s).length >= 2) continue; // 꽝이면 같은 그림 2개까지만
    if (win && s == out.first) continue;
    out.add(s);
  }
  return out..shuffle(rng);
}

String? scratchWinner(List<String> cells) {
  for (final s in _symbols) {
    if (cells.where((x) => x == s).length >= 3) return s;
  }
  return null;
}

class ScratchGame extends StatefulWidget {
  const ScratchGame({super.key});
  @override
  State<ScratchGame> createState() => _ScratchGameState();
}

class _ScratchGameState extends State<ScratchGame> {
  final _rng = Random();
  late List<String> _cells = scratchCells(_rng);
  final _strokes = <Offset>[];
  final _touched = <int>{};
  bool _done = false;
  static const _grid = 12;

  void _reset() => setState(() {
        _cells = scratchCells(_rng);
        _strokes.clear();
        _touched.clear();
        _done = false;
      });

  void _scratch(Offset p, Size size) {
    if (_done) return;
    setState(() {
      _strokes.add(p);
      final cx = (p.dx / size.width * _grid).floor().clamp(0, _grid - 1);
      final cy = (p.dy / size.height * _grid).floor().clamp(0, _grid - 1);
      _touched.add(cy * _grid + cx);
      if (_touched.length > _grid * _grid * 0.45) _done = true; // 거의 다 긁으면 전부 공개
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = scratchWinner(_cells);
    return Column(children: [
      _panel(Column(children: [
        const Text('행운 즉석 복권', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 4),
        Text('손가락으로 은박을 긁어 보세요', style: TextStyle(fontSize: 12, color: _ink.withValues(alpha: 0.6))),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final size = Size(c.maxWidth, c.maxWidth * 0.66);
          return GestureDetector(
            key: const ValueKey('scratch_area'),
            onPanStart: (d) => _scratch(d.localPosition, size),
            onPanUpdate: (d) => _scratch(d.localPosition, size),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox.fromSize(
                size: size,
                child: Stack(children: [
                  Container(
                    color: const Color(0xFFFFF8E1),
                    child: GridView.count(
                      crossAxisCount: 3,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(10),
                      childAspectRatio: 1.25,
                      children: [for (final s in _cells) Center(child: Text(s, style: const TextStyle(fontSize: 38)))],
                    ),
                  ),
                  if (!_done) Positioned.fill(child: CustomPaint(painter: _FoilPainter(_strokes))),
                ]),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        AnimatedOpacity(
          opacity: _done ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Text(w != null ? '🎉 $w $w $w 당첨! 오늘 운이 좋네요' : '아쉽게 꽝! 다음 장은 꼭 될 거예요',
              key: const ValueKey('scratch_result'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: w != null ? const Color(0xFFE65100) : _ink)),
        ),
      ])),
      const SizedBox(height: 18),
      _cuteButton('새 복권 받기', _reset, color: const Color(0xFF5C9DFF)),
    ]);
  }
}

class _FoilPainter extends CustomPainter {
  final List<Offset> strokes;
  _FoilPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = const LinearGradient(colors: [Color(0xFFD7D9E0), Color(0xFFB8BCC8), Color(0xFFE4E6EC)])
          .createShader(Offset.zero & size));
    final tp = TextPainter(
        text: const TextSpan(text: '✨ 여기를 긁어요 ✨', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF8A8FA0))),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final p in strokes) {
      canvas.drawCircle(p, 22, clear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FoilPainter old) => true;
}

// ── 3. 번호 맞히기 ──────────────────────────────────────────────
class GuessGame extends StatefulWidget {
  /// 테스트용 — 회차 불러오기
  final Future<LottoWinningNumber?> Function()? loader;
  const GuessGame({super.key, this.loader});
  @override
  State<GuessGame> createState() => _GuessGameState();
}

class _GuessGameState extends State<GuessGame> {
  Set<int> _picked = {};
  LottoWinningNumber? _round;
  bool _loading = false, _failed = false;

  Future<LottoWinningNumber?> _randomRound() async {
    final latest = await SupabaseService.getRecentWinningNumbers(1);
    if (latest.isEmpty) return null;
    return SupabaseService.getWinningNumbersForRound(Random().nextInt(latest.first.round) + 1);
  }

  Future<void> _reveal() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = await (widget.loader ?? _randomRound)().catchError((_) => null);
    if (!mounted) return;
    setState(() {
      _round = r;
      _loading = false;
      _failed = r == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _round;
    final win = r == null ? const <int>[] : ([...r.numbers]..sort());
    final hits = _picked.where(win.contains).toSet();
    final rank = r == null ? null : lottoRank(_picked.toList(), win, r.bonusNumber);
    return Column(children: [
      _panel(Column(children: [
        Text(r == null ? '숫자 6개를 고르면 지난 회차 하나를 무작위로 펼쳐요' : '${r.round}회 (${r.drawDate}) 당첨번호',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 10),
        if (r != null) ...[
          Wrap(spacing: 4, alignment: WrapAlignment.center, children: [
            for (final n in win) lottoBall(n, size: 36),
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('+', style: TextStyle(fontWeight: FontWeight.w900))),
            lottoBall(r.bonusNumber, size: 36),
          ]),
          const SizedBox(height: 10),
          Text(rank != null ? '🎉 ${hits.length}개 맞힘 — 그 회차였다면 $rank등!' : '${hits.length}개 맞혔어요 ${hits.length >= 2 ? '👏' : '🙂'}',
              key: const ValueKey('guess_result'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: rank != null ? const Color(0xFFE65100) : _ink)),
          const SizedBox(height: 12),
        ],
        NumberPicker(picked: _picked, hit: hits, onTap: (n) => setState(() {
          if (_round != null) {
            _round = null; // 다시 고르면 새 판
          }
          _picked = _toggle(_picked, n);
        })),
        if (_failed) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text('회차를 불러오지 못했어요. 인터넷 연결을 확인해 주세요', style: TextStyle(fontSize: 12, color: Colors.red.shade400))),
      ])),
      const SizedBox(height: 18),
      _cuteButton(_loading ? '펼치는 중…' : _picked.length < 6 ? '숫자 ${6 - _picked.length}개 더 골라요' : '지난 회차 펼치기',
          _picked.length == 6 && !_loading && _round == null ? _reveal : null,
          color: const Color(0xFF66BB6A), key: const ValueKey('guess_go')),
    ]);
  }
}

// ── 4. 행운 룰렛 ────────────────────────────────────────────────
class RouletteGame extends StatefulWidget {
  const RouletteGame({super.key});
  @override
  State<RouletteGame> createState() => _RouletteGameState();
}

class _RouletteGameState extends State<RouletteGame> with SingleTickerProviderStateMixin {
  static const _n = 8;
  static const _colors = [Color(0xFFFFADAD), Color(0xFFFFD6A5), Color(0xFFFDFFB6), Color(0xFFCAFFBF),
    Color(0xFF9BF6FF), Color(0xFFA0C4FF), Color(0xFFBDB2FF), Color(0xFFFFC6FF)];
  final _rng = Random();
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late List<int> _nums = randomSix(_rng)..addAll(randomSix(_rng).take(2));
  double _from = 0, _to = 0;
  int? _landed;
  final _bag = <int>[];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _spin() {
    final k = _rng.nextInt(_n);
    // 바늘은 위(12시) — k번째 칸 가운데가 위로 오게 + 4~6바퀴
    final target = (4 + _rng.nextInt(3)) * 2 * pi + (2 * pi - (k + 0.5) * 2 * pi / _n);
    setState(() {
      _from = _to % (2 * pi);
      _to = target;
      _landed = null;
    });
    _c.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _landed = _nums[k];
        if (!_bag.contains(_landed) && _bag.length < 6) _bag.add(_landed!);
      });
    });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _panel(Column(children: [
          SizedBox(
            width: 260, height: 270,
            child: Stack(alignment: Alignment.topCenter, children: [
              Positioned(
                top: 14,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => Transform.rotate(
                    angle: _from + (_to - _from) * Curves.easeOutCubic.transform(_c.value),
                    child: CustomPaint(size: const Size(250, 250), painter: _WheelPainter(_nums, _colors)),
                  ),
                ),
              ),
              const Text('▼', style: TextStyle(fontSize: 28, color: Color(0xFFE53935))),
            ]),
          ),
          const SizedBox(height: 6),
          Text(_landed == null ? '룰렛을 돌려 행운 숫자를 모아 보세요 (6개)' : '🎉 $_landed 당첨!',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: _landed == null ? _ink.withValues(alpha: 0.7) : const Color(0xFFE65100))),
          const SizedBox(height: 10),
          Wrap(spacing: 4, children: [
            for (var i = 0; i < 6; i++)
              i < _bag.length
                  ? lottoBall(_bag[i], size: 36)
                  : Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade200)),
          ]),
        ])),
        const SizedBox(height: 18),
        _cuteButton(_bag.length >= 6 ? '다 모았어요! 새로 시작' : '룰렛 돌리기', _c.isAnimating ? null : () {
          if (_bag.length >= 6) {
            setState(() {
              _bag.clear();
              _landed = null;
              _nums = randomSix(_rng)..addAll(randomSix(_rng).take(2));
            });
            return;
          }
          _spin();
        }, color: const Color(0xFFEC6FCF), key: const ValueKey('roulette_spin')),
      ]);
}

class _WheelPainter extends CustomPainter {
  final List<int> nums;
  final List<Color> colors;
  _WheelPainter(this.nums, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2, sweep = 2 * pi / nums.length;
    for (var i = 0; i < nums.length; i++) {
      final start = -pi / 2 + i * sweep;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true, Paint()..color = colors[i % colors.length]);
      final mid = start + sweep / 2;
      final tp = TextPainter(text: TextSpan(text: '${nums[i]}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, c + Offset(cos(mid), sin(mid)) * r * 0.66 - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = Colors.white);
    canvas.drawCircle(c, 18, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.nums != nums;
}

// ── 5. 모의 추첨 ────────────────────────────────────────────────
const _prizeWon = {1: 2000000000, 2: 60000000, 3: 1500000, 4: 50000, 5: 5000}; // 대략의 당첨금 (재미용)

/// 내 번호로 n번 무작위 추첨 → 등수별 횟수 (0 = 낙첨)
Map<int, int> simulateDraws(List<int> pick, int n, Random rng) {
  final out = {for (var k = 0; k <= 5; k++) k: 0};
  final pool = List<int>.generate(45, (i) => i + 1);
  for (var i = 0; i < n; i++) {
    pool.shuffle(rng);
    final rank = lottoRank(pick, pool.sublist(0, 6), pool[6]) ?? 0;
    out[rank] = out[rank]! + 1;
  }
  return out;
}

class SimulateGame extends StatefulWidget {
  const SimulateGame({super.key});
  @override
  State<SimulateGame> createState() => _SimulateGameState();
}

class _SimulateGameState extends State<SimulateGame> {
  static const _n = 1000;
  Set<int> _picked = {};
  Map<int, int>? _res;
  final _rng = Random();

  @override
  Widget build(BuildContext context) {
    final res = _res;
    final won = res == null ? 0 : [for (final e in res.entries) if (e.key > 0) _prizeWon[e.key]! * e.value].fold<int>(0, (a, b) => a + b);
    String won0(int v) => v >= 100000000 ? '${(v / 100000000).toStringAsFixed(1)}억' : v >= 10000 ? '${v ~/ 10000}만' : '$v';
    return Column(children: [
      _panel(Column(children: [
        Text(_picked.length < 6 ? '번호 6개를 고르거나 자동으로 채워요' : '내 번호 ${(_picked.toList()..sort()).join(' · ')}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 10),
        NumberPicker(picked: _picked, onTap: (n) => setState(() {
          _picked = _toggle(_picked, n);
          _res = null;
        })),
        const SizedBox(height: 8),
        TextButton(onPressed: () => setState(() {
          _picked = randomSix(_rng).toSet();
          _res = null;
        }), child: const Text('🎲 자동으로 채우기')),
      ])),
      const SizedBox(height: 14),
      if (res != null)
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('1,000번 추첨 결과', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 8),
          for (final k in [1, 2, 3, 4, 5, 0])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 46, child: Text(k == 0 ? '꽝' : '$k등', style: const TextStyle(fontWeight: FontWeight.w800, color: _ink))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: res[k]! / _n, minHeight: 12, backgroundColor: const Color(0xFFF1EEF8),
                      color: k == 0 ? Colors.grey.shade400 : const Color(0xFF8E7CFF)),
                  ),
                ),
                SizedBox(width: 56, child: Text('${res[k]}번', key: ValueKey('sim_$k'), textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: _ink))),
              ]),
            ),
          const SizedBox(height: 10),
          Text('쓴 돈 ${won0(_n * 1000)}원 · 받은 돈 약 ${won0(won)}원', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 2),
          Text('1등 확률은 1/8,145,060 — 1,000번으로는 거의 만나기 어려워요 😅', style: TextStyle(fontSize: 11.5, color: _ink.withValues(alpha: 0.6))),
        ])),
      const SizedBox(height: 18),
      _cuteButton('1,000번 추첨하기', _picked.length == 6 ? () => setState(() => _res = simulateDraws(_picked.toList(), _n, _rng)) : null,
          color: const Color(0xFF8E7CFF), key: const ValueKey('sim_go')),
    ]);
  }
}

// ── 6. 오늘의 운세 번호 ─────────────────────────────────────────
const _fortunes = [
  '작은 행운이 연달아 찾아오는 날이에요. 미뤄 둔 일을 시작해 보세요.',
  '귀인이 가까이 있어요. 오랜만에 연락 온 사람을 반겨 주세요.',
  '마음이 편해야 운도 들어와요. 오늘은 천천히 가도 괜찮아요.',
  '뜻밖의 소식이 기분을 밝혀 줄 거예요. 웃는 얼굴이 행운을 불러요.',
  '돈 들어오는 길이 열리는 날! 작은 지출은 아껴 두세요.',
  '직감이 잘 맞는 날이에요. 처음 떠오른 생각을 믿어 보세요.',
  '꾸준함이 빛을 보는 날이에요. 하던 일을 끝까지 해 보세요.',
  '새로운 곳에서 좋은 기운을 만나요. 가 보지 않은 길로 걸어 보세요.',
  '가족과 함께하면 운이 두 배! 따뜻한 말 한마디를 건네 보세요.',
  '정리 정돈이 행운을 부르는 날이에요. 지갑부터 정리해 볼까요?',
  '오늘은 쉬어 가는 날. 충전한 만큼 다음 주가 반짝여요.',
  '용기 내면 좋은 결과가 따라와요. 망설이던 일에 도전해 보세요.',
];
const _luckyColors = [('빨강', Color(0xFFEF5350)), ('주황', Color(0xFFFFA726)), ('노랑', Color(0xFFFFD54F)), ('초록', Color(0xFF66BB6A)),
  ('파랑', Color(0xFF42A5F5)), ('보라', Color(0xFFAB47BC)), ('분홍', Color(0xFFF48FB1)), ('하늘', Color(0xFF4FC3F7))];

/// 생일 + 오늘 날짜 → (운세 문장 번호, 행운 번호 6개, 행운 색 번호) — 같은 날 같은 생일이면 늘 같음
(int, List<int>, int) fortuneFor(DateTime birth, DateTime today) {
  final seed = birth.year * 10000 + birth.month * 100 + birth.day + (today.year * 10000 + today.month * 100 + today.day) * 7;
  final rng = Random(seed);
  return (rng.nextInt(_fortunes.length), randomSix(rng), rng.nextInt(_luckyColors.length));
}

class FortuneGame extends StatefulWidget {
  const FortuneGame({super.key});
  @override
  State<FortuneGame> createState() => _FortuneGameState();
}

class _FortuneGameState extends State<FortuneGame> {
  DateTime? _birth;

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: '생년월일을 골라 주세요',
    );
    if (d != null && mounted) setState(() => _birth = d);
  }

  @override
  Widget build(BuildContext context) {
    final b = _birth;
    final now = DateTime.now();
    final f = b == null ? null : fortuneFor(b, now);
    return Column(children: [
      _panel(Column(children: [
        const Text('🔮', style: TextStyle(fontSize: 54)),
        const SizedBox(height: 6),
        Text(b == null ? '생일을 알려 주면 오늘의 운세를 봐 드려요' : '${b.year}.${b.month}.${b.day}생 · ${now.month}월 ${now.day}일의 운세',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
        if (f != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFF0F3), borderRadius: BorderRadius.circular(16)),
            child: Text(_fortunes[f.$1], key: const ValueKey('fortune_text'), textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, height: 1.5, color: _ink, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
          const Text('오늘의 행운 번호', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _ink)),
          const SizedBox(height: 8),
          Wrap(spacing: 4, children: [for (final n in f.$2) lottoBall(n, size: 38)]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('행운의 색 ', style: TextStyle(fontSize: 13, color: _ink)),
            Container(width: 16, height: 16, decoration: BoxDecoration(color: _luckyColors[f.$3].$2, shape: BoxShape.circle)),
            Text(' ${_luckyColors[f.$3].$1}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
          ]),
        ],
      ])),
      const SizedBox(height: 18),
      _cuteButton(b == null ? '생일 고르기' : '생일 다시 고르기', _pick, color: const Color(0xFFEE7C92), key: const ValueKey('fortune_pick')),
      const SizedBox(height: 8),
      Text('재미로 보는 운세예요 🍀', style: TextStyle(fontSize: 11.5, color: _ink.withValues(alpha: 0.5))),
    ]);
  }
}
