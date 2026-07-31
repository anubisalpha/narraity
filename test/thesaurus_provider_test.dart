import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/state/thesaurus_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to enabled with nothing persisted yet', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(thesaurusEnabledProvider), isTrue);
  });

  test('toggling off actually persists to SharedPreferences', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(thesaurusEnabledProvider.notifier).set(false);
    expect(container.read(thesaurusEnabledProvider), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(thesaurusEnabledPrefKey), isFalse);
  });

  test('a fresh provider instance restores a previously persisted value', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(thesaurusEnabledPrefKey, false);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // build()'s _restore() is fire-and-forget; poll briefly rather than a
    // single fixed delay, since exactly how many event-loop turns the mock
    // SharedPreferences channel needs isn't a documented guarantee.
    var state = container.read(thesaurusEnabledProvider);
    for (var i = 0; i < 10 && state; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      state = container.read(thesaurusEnabledProvider);
    }
    expect(state, isFalse);
  });
}
