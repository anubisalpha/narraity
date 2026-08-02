import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/library_screen.dart';
import 'screens/project_shell_screen.dart';
import 'state/drive_auto_sync_provider.dart';
import 'state/library_provider.dart';
import 'state/manuscript_provider.dart';
import 'state/theme_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/status_bar.dart';

class NarraityApp extends ConsumerWidget {
  const NarraityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final currentProject = ref.watch(currentProjectProvider);
    // Only meaningful inside a project; false (and so ignored) on the
    // library screen, since focusModeProvider only gets set from there.
    final focusMode = ref.watch(focusModeProvider);
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
      home: Scaffold(
        body: currentProject == null
            ? const LibraryScreen()
            : ProjectShellScreen(project: currentProject),
        // Focus Mode already strips the project shell's own AppBar and
        // sidebar for a distraction-free view — the status bar is exactly
        // that kind of chrome, so it goes with them.
        bottomNavigationBar: focusMode ? null : const StatusBar(),
      ),
    );
  }
}
