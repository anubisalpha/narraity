import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/library_screen.dart';
import 'screens/project_shell_screen.dart';
import 'state/library_provider.dart';
import 'state/theme_provider.dart';
import 'theme/app_theme.dart';

class NarraityApp extends ConsumerWidget {
  const NarraityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final currentProject = ref.watch(currentProjectProvider);

    return MaterialApp(
      title: 'Narraity',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: currentProject == null
          ? const LibraryScreen()
          : ProjectShellScreen(project: currentProject),
    );
  }
}
