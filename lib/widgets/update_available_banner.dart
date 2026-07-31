import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/update_check_provider.dart';

/// Tracks whether the banner has been dismissed this session — deliberately
/// not persisted, so it reappears next launch rather than needing a
/// "remind me later" setting nobody asked for.
final _updateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Shown at the top of the Library screen when a newer release is available
/// on GitHub. Silent by default: if the check fails or finds nothing newer,
/// this renders nothing.
class UpdateAvailableBanner extends ConsumerWidget {
  const UpdateAvailableBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(_updateBannerDismissedProvider);
    if (dismissed) return const SizedBox.shrink();

    final updateAsync = ref.watch(updateCheckProvider);
    final update = updateAsync.valueOrNull;
    if (update == null) return const SizedBox.shrink();

    return MaterialBanner(
      leading: const Icon(Icons.system_update_outlined),
      content: Text(
        'Narraity ${update.version} is available — you\'re on an older version.',
      ),
      actions: [
        TextButton(
          onPressed: () => launchUrl(Uri.parse(update.htmlUrl)),
          child: const Text('View Release'),
        ),
        TextButton(
          onPressed: () => ref.read(_updateBannerDismissedProvider.notifier).state = true,
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
