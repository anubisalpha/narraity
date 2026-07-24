import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/app_logger.dart';

void main() {
  AppLogger.run(() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const ProviderScope(child: NarraityApp()));
  });
}
