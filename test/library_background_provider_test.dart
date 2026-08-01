import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/library_background.dart';
import 'package:narraity/state/library_background_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to the theme-default background when nothing has been saved', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(libraryBackgroundProvider), isA<ThemeDefaultBackground>());
  });

  test('select() persists the choice, readable by a fresh container (simulating a restart)',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final gradient = kLibraryBackgroundChoices.firstWhere((c) => c is GradientBackground);
    await container.read(libraryBackgroundProvider.notifier).select(gradient);
    expect(container.read(libraryBackgroundProvider).id, gradient.id);

    final freshContainer = ProviderContainer();
    addTearDown(freshContainer.dispose);
    // build() kicks off an async restore; the notifier itself is
    // synchronously available, but its restored value needs a beat to load.
    freshContainer.read(libraryBackgroundProvider);
    await Future<void>.delayed(Duration.zero);

    expect(freshContainer.read(libraryBackgroundProvider).id, gradient.id);
  });

  test('selecting a new choice overwrites a previous one', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final solid = kLibraryBackgroundChoices.firstWhere((c) => c is SolidBackground);
    final gradient = kLibraryBackgroundChoices.firstWhere((c) => c is GradientBackground);

    await container.read(libraryBackgroundProvider.notifier).select(solid);
    expect(container.read(libraryBackgroundProvider).id, solid.id);

    await container.read(libraryBackgroundProvider.notifier).select(gradient);
    expect(container.read(libraryBackgroundProvider).id, gradient.id);
  });
}
