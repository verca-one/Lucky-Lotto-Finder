// 로또 용지 QR 찍기 — 카메라로 QR 글자만 읽어 (회차, 게임들)로 돌려준다. 동행복권 사이트에는 접속하지 않는다.
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/purchase_records.dart';

class LottoQrScanScreen extends StatefulWidget {
  const LottoQrScanScreen({super.key});
  @override
  State<LottoQrScanScreen> createState() => _LottoQrScanScreenState();
}

class _LottoQrScanScreenState extends State<LottoQrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  DateTime? _warnedAt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture c) {
    if (_done) return;
    for (final b in c.barcodes) {
      final r = parseLottoQr(b.rawValue ?? '');
      if (r != null) {
        _done = true;
        Navigator.pop(context, r);
        return;
      }
    }
    // 다른 QR — 2초에 한 번만 안내
    final now = DateTime.now();
    if (_warnedAt == null || now.difference(_warnedAt!) > const Duration(seconds: 2)) {
      _warnedAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('로또 6/45 용지의 QR이 아닙니다'), duration: Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('로또 용지 QR 찍기', style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Stack(children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? '카메라 권한이 필요합니다 — 설정에서 카메라를 허용해 주세요'
                        : '카메라를 열지 못했습니다 (${error.errorCode.name})',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240, height: 240,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const Positioned(
            left: 0, right: 0, bottom: 48,
            child: Text('용지 오른쪽 위 QR을 네모 안에 맞춰 주세요', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}
