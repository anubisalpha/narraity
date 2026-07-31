import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/update_check_service.dart';

final updateCheckServiceProvider = Provider<UpdateCheckService>((ref) => UpdateCheckService());

/// One background check per app session, cached for the whole session
/// (deliberately not `autoDispose` — re-checking every time a screen mounts
/// would just spam GitHub's API). Errors collapse to `null` here since this
/// is the silent, unattended path; `AboutSectionContent`'s manual "Check for
/// Updates" button calls [UpdateCheckService] directly so it can surface a
/// real error instead.
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final service = ref.read(updateCheckServiceProvider);
  try {
    return await service.checkForUpdate(info.version);
  } on UpdateCheckException {
    return null;
  }
});
