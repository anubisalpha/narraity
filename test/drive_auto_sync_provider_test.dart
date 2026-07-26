import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/state/drive_auto_sync_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('immediate sync defaults to off', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _settle();

    expect(container.read(driveImmediateSyncEnabledProvider), isFalse);
  });

  test('daily sync defaults to off', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _settle();

    expect(container.read(driveDailySyncEnabledProvider), isFalse);
  });

  test('frequent sync interval defaults to 0 (off)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _settle();

    expect(container.read(driveFrequentSyncIntervalProvider), 0);
  });

  test('toggling immediate sync persists across a fresh provider instance', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(driveImmediateSyncEnabledProvider.notifier).set(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(driveImmediateSyncPrefKey), isTrue);
  });

  test('setting the frequent interval persists the chosen minutes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(driveFrequentSyncIntervalProvider.notifier).set(15);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(driveFrequentSyncIntervalPrefKey), 15);
  });

  test('setting daily sync persists the chosen value', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(driveDailySyncEnabledProvider.notifier).set(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(driveDailySyncPrefKey), isTrue);
  });
}
