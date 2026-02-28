import '../models/plan.dart';
import '../services/billing_service.dart';

abstract class PlanBillingGateway {
  Future<bool> isAvailable();
  Future<dynamic> purchase(String productId);
  Future<List<dynamic>> restore();
}

class BillingServiceGateway implements PlanBillingGateway {
  BillingServiceGateway(this._billingService);

  final BillingService _billingService;

  @override
  Future<bool> isAvailable() => _billingService.isAvailable();

  @override
  Future<dynamic> purchase(String productId) =>
      _billingService.purchase(productId);

  @override
  Future<List<dynamic>> restore() async => _billingService.restore();
}

typedef PlanBillingGatewayFactory = Future<PlanBillingGateway?> Function();
typedef PlanActivationFn = Future<void> Function(PlanTier tier);

class PlanBillingController {
  PlanBillingController({
    required PlanBillingGatewayFactory gatewayFactory,
    required bool isIapSupportedPlatform,
    required String iosPlusProductId,
    required String iosProProductId,
    required String iosUnlimitedProductId,
  })  : _gatewayFactory = gatewayFactory,
        _isIapSupportedPlatform = isIapSupportedPlatform,
        _iosPlusProductId = iosPlusProductId,
        _iosProProductId = iosProProductId,
        _iosUnlimitedProductId = iosUnlimitedProductId;

  static const String purchaseMissingProductId = 'iap_missing_product_id';
  static const String purchaseUnavailable = 'iap_unavailable';
  static const String purchaseFailed = 'iap_failed';
  static const String restoreUnavailable = 'iap_restore_unavailable';
  static const String restoreNone = 'iap_restore_none';
  static const String restoreNotFound = 'iap_restore_not_found';

  final PlanBillingGatewayFactory _gatewayFactory;
  final bool _isIapSupportedPlatform;
  final String _iosPlusProductId;
  final String _iosProProductId;
  final String _iosUnlimitedProductId;

  Future<PlanBillingGateway?>? _gatewayFuture;

  Future<String?> purchasePlan({
    required PlanTier tier,
    required PlanActivationFn onActivateLocalPlan,
    required PlanActivationFn onPersistPlan,
  }) async {
    if (tier == PlanTier.free) {
      await onActivateLocalPlan(tier);
      return null;
    }
    if (!_isIapSupportedPlatform) {
      return purchaseUnavailable;
    }

    final productId = _productIdForTier(tier);
    if (productId.isEmpty) {
      return purchaseMissingProductId;
    }

    final gateway = await _getGateway();
    if (gateway == null || !(await gateway.isAvailable())) {
      return purchaseUnavailable;
    }

    final purchase = await gateway.purchase(productId);
    if (purchase == null) {
      return purchaseFailed;
    }

    await onActivateLocalPlan(tier);
    await onPersistPlan(tier);
    return null;
  }

  Future<String?> restorePurchases({
    required PlanActivationFn onActivateLocalPlan,
    required PlanActivationFn onPersistPlan,
  }) async {
    if (!_isIapSupportedPlatform) {
      return restoreUnavailable;
    }
    final gateway = await _getGateway();
    if (gateway == null || !(await gateway.isAvailable())) {
      return restoreUnavailable;
    }
    final purchases = await gateway.restore();
    if (purchases.isEmpty) {
      return restoreNone;
    }

    final restoredTier = _resolveTierFromPurchases(purchases);
    if (restoredTier == null) {
      return restoreNotFound;
    }
    await onActivateLocalPlan(restoredTier);
    await onPersistPlan(restoredTier);
    return null;
  }

  Future<PlanBillingGateway?> _getGateway() async {
    _gatewayFuture ??= _gatewayFactory();
    return _gatewayFuture!;
  }

  String _productIdForTier(PlanTier tier) {
    switch (tier) {
      case PlanTier.starter:
        return _iosPlusProductId;
      case PlanTier.growth:
        return _iosProProductId;
      case PlanTier.unlimited:
        return _iosUnlimitedProductId;
      case PlanTier.free:
      case PlanTier.lifetime:
        return '';
    }
  }

  PlanTier? _resolveTierFromPurchases(List<dynamic> purchases) {
    final ids = purchases
        .map((purchase) {
          if (purchase is String) return purchase;
          try {
            return (purchase as dynamic).productID as String?;
          } catch (_) {
            return null;
          }
        })
        .whereType<String>()
        .toSet();

    if (ids.contains(_iosUnlimitedProductId)) {
      return PlanTier.unlimited;
    }
    if (ids.contains(_iosProProductId)) {
      return PlanTier.growth;
    }
    if (ids.contains(_iosPlusProductId)) {
      return PlanTier.starter;
    }
    return null;
  }
}
