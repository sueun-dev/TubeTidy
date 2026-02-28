import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_summary/models/plan.dart';
import 'package:youtube_summary/state/plan_billing_controller.dart';

class _FakeGateway implements PlanBillingGateway {
  _FakeGateway({
    required this.available,
    this.purchaseResult,
    this.restoreResult = const <dynamic>[],
  });

  bool available;
  dynamic purchaseResult;
  List<dynamic> restoreResult;
  int purchaseCalls = 0;
  int restoreCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<dynamic> purchase(String productId) async {
    purchaseCalls += 1;
    return purchaseResult;
  }

  @override
  Future<List<dynamic>> restore() async {
    restoreCalls += 1;
    return restoreResult;
  }
}

PlanBillingController _controller({
  required bool supported,
  required Future<PlanBillingGateway?> Function() gatewayFactory,
  String plus = 'plus',
  String pro = 'pro',
  String unlimited = 'unlimited',
}) {
  return PlanBillingController(
    gatewayFactory: gatewayFactory,
    isIapSupportedPlatform: supported,
    iosPlusProductId: plus,
    iosProProductId: pro,
    iosUnlimitedProductId: unlimited,
  );
}

void main() {
  test('purchase free tier activates local plan without persisting', () async {
    final gateway = _FakeGateway(available: true);
    final controller = _controller(
      supported: true,
      gatewayFactory: () async => gateway,
    );
    var activated = 0;
    var persisted = 0;

    final result = await controller.purchasePlan(
      tier: PlanTier.free,
      onActivateLocalPlan: (_) async => activated += 1,
      onPersistPlan: (_) async => persisted += 1,
    );

    expect(result, isNull);
    expect(activated, 1);
    expect(persisted, 0);
    expect(gateway.purchaseCalls, 0);
  });

  test('purchase returns unavailable when platform is unsupported', () async {
    final controller = _controller(
      supported: false,
      gatewayFactory: () async => _FakeGateway(available: true),
    );

    final result = await controller.purchasePlan(
      tier: PlanTier.starter,
      onActivateLocalPlan: (_) async {},
      onPersistPlan: (_) async {},
    );

    expect(result, PlanBillingController.purchaseUnavailable);
  });

  test('purchase returns missing product id when configured id is empty',
      () async {
    final controller = _controller(
      supported: true,
      plus: '',
      gatewayFactory: () async => _FakeGateway(available: true),
    );

    final result = await controller.purchasePlan(
      tier: PlanTier.starter,
      onActivateLocalPlan: (_) async {},
      onPersistPlan: (_) async {},
    );

    expect(result, PlanBillingController.purchaseMissingProductId);
  });

  test('purchase success activates and persists plan', () async {
    final gateway = _FakeGateway(available: true, purchaseResult: Object());
    final controller = _controller(
      supported: true,
      gatewayFactory: () async => gateway,
    );
    PlanTier? activatedTier;
    PlanTier? persistedTier;

    final result = await controller.purchasePlan(
      tier: PlanTier.growth,
      onActivateLocalPlan: (tier) async => activatedTier = tier,
      onPersistPlan: (tier) async => persistedTier = tier,
    );

    expect(result, isNull);
    expect(activatedTier, PlanTier.growth);
    expect(persistedTier, PlanTier.growth);
    expect(gateway.purchaseCalls, 1);
  });

  test('restore returns not found when no known product is restored', () async {
    final gateway = _FakeGateway(
      available: true,
      restoreResult: const ['unknown_product'],
    );
    final controller = _controller(
      supported: true,
      gatewayFactory: () async => gateway,
    );

    final result = await controller.restorePurchases(
      onActivateLocalPlan: (_) async {},
      onPersistPlan: (_) async {},
    );

    expect(result, PlanBillingController.restoreNotFound);
    expect(gateway.restoreCalls, 1);
  });

  test('restore selects highest tier and persists it', () async {
    final gateway = _FakeGateway(
      available: true,
      restoreResult: const ['plus', 'unlimited'],
    );
    final controller = _controller(
      supported: true,
      gatewayFactory: () async => gateway,
    );
    PlanTier? activatedTier;
    PlanTier? persistedTier;

    final result = await controller.restorePurchases(
      onActivateLocalPlan: (tier) async => activatedTier = tier,
      onPersistPlan: (tier) async => persistedTier = tier,
    );

    expect(result, isNull);
    expect(activatedTier, PlanTier.unlimited);
    expect(persistedTier, PlanTier.unlimited);
  });
}
