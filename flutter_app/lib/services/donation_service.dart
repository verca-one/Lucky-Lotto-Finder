import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// 개발자 커피 후원 인앱결제 서비스
class DonationService {
  static const String _coffeeProductId = 'donation_coffee';

  static final DonationService _instance = DonationService._();
  factory DonationService() => _instance;
  DonationService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? _coffeeProduct;
  bool _isAvailable = false;

  /// 결제 결과 콜백
  void Function(bool success, String message)? onPurchaseResult;

  /// 초기화
  Future<void> initialize() async {
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) {
      debugPrint('[DonationService] 스토어 사용 불가');
      return;
    }

    // 결제 스트림 구독
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => debugPrint('[DonationService] 스트림 에러: $error'),
    );

    // 상품 정보 로드
    final response = await _iap.queryProductDetails({_coffeeProductId});
    if (response.productDetails.isNotEmpty) {
      _coffeeProduct = response.productDetails.first;
      debugPrint('[DonationService] 상품 로드 완료: ${_coffeeProduct!.title}');
    } else {
      debugPrint('[DonationService] 상품을 찾을 수 없음. notFoundIDs: ${response.notFoundIDs}');
    }
  }

  /// 스토어 사용 가능 여부
  bool get isAvailable => _isAvailable && _coffeeProduct != null;

  /// 상품 가격 문자열
  String get priceString => _coffeeProduct?.price ?? '₩1,000';

  /// 커피 후원 결제 시작
  Future<bool> buyCoffee() async {
    if (_coffeeProduct == null) {
      onPurchaseResult?.call(false, '상품 정보를 불러올 수 없습니다');
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: _coffeeProduct!);
    try {
      // 소비성 상품 (한 번 구매하고 끝, 여러 번 가능)
      return await _iap.buyConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint('[DonationService] 결제 에러: $e');
      onPurchaseResult?.call(false, '결제 중 오류가 발생했습니다');
      return false;
    }
  }

  /// 결제 업데이트 처리
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      if (purchase.productID != _coffeeProductId) continue;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // 소비성 상품이므로 완료 처리
          if (purchase.pendingCompletePurchase) {
            _iap.completePurchase(purchase);
          }
          onPurchaseResult?.call(true, '후원해 주셔서 감사합니다! ☕');
          break;
        case PurchaseStatus.error:
          if (purchase.pendingCompletePurchase) {
            _iap.completePurchase(purchase);
          }
          onPurchaseResult?.call(false, purchase.error?.message ?? '결제에 실패했습니다');
          break;
        case PurchaseStatus.canceled:
          onPurchaseResult?.call(false, '결제가 취소되었습니다');
          break;
        case PurchaseStatus.pending:
          debugPrint('[DonationService] 결제 대기 중...');
          break;
      }
    }
  }

  /// 리소스 해제
  void dispose() {
    _subscription?.cancel();
  }
}
