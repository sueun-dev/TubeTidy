import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

class BillingService {
  BillingService._(this._iap);

  final InAppPurchase _iap;

  static Future<BillingService> create() async {
    return BillingService._(InAppPurchase.instance);
  }

  Future<bool> isAvailable() async => _iap.isAvailable();

  Future<ProductDetails?> getProduct(String productId) async {
    if (productId.isEmpty) return null;
    final response = await _iap.queryProductDetails({productId});
    if (response.error != null || response.productDetails.isEmpty) {
      return null;
    }
    return response.productDetails.first;
  }

  Future<PurchaseDetails?> purchase(String productId) async {
    final product = await getProduct(productId);
    if (product == null) return null;

    final completer = Completer<PurchaseDetails?>();
    late StreamSubscription<List<PurchaseDetails>> sub;

    sub = _iap.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        if (purchase.productID != productId) continue;
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          completer.complete(purchase);
          await sub.cancel();
          return;
        }
        if (purchase.status == PurchaseStatus.error ||
            purchase.status == PurchaseStatus.canceled) {
          completer.complete(null);
          await sub.cancel();
          return;
        }
      }
    });

    final params = PurchaseParam(productDetails: product);
    _iap.buyNonConsumable(purchaseParam: params);

    return completer.future.timeout(const Duration(seconds: 45),
        onTimeout: () async {
      await sub.cancel();
      return null;
    });
  }

  Future<List<PurchaseDetails>> restore() async {
    final restored = <PurchaseDetails>[];
    final completer = Completer<List<PurchaseDetails>>();
    late StreamSubscription<List<PurchaseDetails>> sub;

    sub = _iap.purchaseStream.listen((purchases) async {
      for (final purchase in purchases) {
        if (purchase.status == PurchaseStatus.restored) {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          restored.add(purchase);
        }
      }
      if (!completer.isCompleted) {
        completer.complete(restored);
      }
      await sub.cancel();
    });

    await _iap.restorePurchases();

    return completer.future.timeout(const Duration(seconds: 30),
        onTimeout: () async {
      await sub.cancel();
      return restored;
    });
  }
}
