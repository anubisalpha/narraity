import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/library_screen.dart';
import 'screens/project_shell_screen.dart';
import 'state/drive_auto_sync_provider.dart';
import 'state/library_provider.dart';
import 'state/theme_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/status_bar.dart';

class NarraityApp extends ConsumerWidget {
  const NarraityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final currentProject = ref.watch(currentProjectProvider);
    // Keeps the daily/frequent auto-sync timers alive for the whole app
    // session, regardless of which screen is open — not just while
    // Settings happens to be mounted.
    ref.watch(driveAutoSyncSchedulerProvider);

    return MaterialApp(
      title: 'Narraity',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: currentProject == null
          ? const LibraryScreen()
          : ProjectShellScreen(project: currentProject),
      // Wraps the Navigator itself (every route it ever pushes — Settings,
      // Series, Ideas, Focus Mode, ...), not just `home`, so the status bar
      // stays visible everywhere rather than being covered the moment any
      // screen gets pushed on top. Always shown, including in Focus Mode —
      // unlike the project shell's own AppBar/sidebar, this isn't editor
      // chrome to get out of the way of the prose.
      //
      // `child` goes straight into Scaffold.body: this Scaffold sits
      // *outside* the Navigator it wraps (`child`), which is where the
      // Navigator's own Overlay lives — so anything here that needs one
      // (Tooltip, dialogs, ...) doesn't have access to it. Tried manually
      // wrapping this in an `Overlay` to fix that (what StatusBar's own
      // Tooltips would normally need); it caused two separate real bugs
      // instead — `Overlay.initialEntries` is a one-time, non-reactive
      // constructor argument, so a fresh `Overlay` reconstructed on every
      // rebuild silently froze `home` swapping (Library ↔ ProjectShell)
      // after the first frame; scoping the Overlay to just `StatusBar`
      // (no external closure captured, so freezing itself was harmless)
      // fixed that but broke hit-testing for content *above* it instead —
      // Overlay's render object doesn't respect the tight height its
      // `bottomNavigationBar` slot gives it, so its hit-test area ends up
      // covering the whole screen. Given both, StatusBar deliberately
      // avoids `Tooltip`/`Overlay` entirely (see its own doc) rather than
      // fighting this a third time.
      builder: (context, child) =>
          Scaffold(body: child, bottomNavigationBar: const StatusBar()),
    );
  }
}
