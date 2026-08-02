import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/drive_auto_sync_provider.dart';
import '../state/drive_provider.dart';
import '../state/spell_check_provider.dart';
import '../state/thesaurus_provider.dart';
import '../state/vault_provider.dart';

/// App version/build, fetched once and shared — the same data
/// `AboutSectionContent` fetches ad hoc via `PackageInfo.fromPlatform()` in
/// `initState`, factored out here so the status bar doesn't duplicate that
/// call every time it rebuilds.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// Thin bar pinned to the bottom of the app: app identity on the left, and a
/// snapshot of the settings/connections that affect what's currently
/// happening to the user's work — Thesaurus and Spell check (are they
/// running at all), the Vault (is it actually protecting anything right
/// now), and Google Drive (connected, and syncing this instant) — on the
/// right, nearest to farthest from the content they describe.
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(packageInfoProvider).valueOrNull;
    final theme = Theme.of(context);

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              packageInfo == null
                  ? 'Narraity · © 2026 Anubis Productions'
                  : 'Narraity v${packageInfo.version} · © 2026 Anubis Productions',
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const _ThesaurusStatus(),
          const SizedBox(width: 10),
          const _SpellCheckStatus(),
          const SizedBox(width: 10),
          const _VaultStatusIndicator(),
          const SizedBox(width: 10),
          const _DriveStatusIndicator(),
        ],
      ),
    );
  }
}

/// One dot-plus-icon status entry: [color] carries the meaning (green good,
/// amber caution, red/grey off), [icon] identifies which subsystem, and
/// [message] is the hover tooltip explaining the color.
class _StatusEntry extends StatelessWidget {
  const _StatusEntry({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      child: Icon(icon, size: 14, color: color),
    );
  }
}

class _ThesaurusStatus extends ConsumerWidget {
  const _ThesaurusStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(thesaurusEnabledProvider);
    return _StatusEntry(
      icon: Icons.menu_book_outlined,
      color: enabled ? Colors.green : Colors.grey,
      message: enabled ? 'Thesaurus: on' : 'Thesaurus: off',
    );
  }
}

class _SpellCheckStatus extends ConsumerWidget {
  const _SpellCheckStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(spellCheckEnabledProvider);
    return _StatusEntry(
      icon: Icons.spellcheck,
      color: enabled ? Colors.green : Colors.grey,
      message: enabled ? 'Spell check: on' : 'Spell check: off',
    );
  }
}

class _VaultStatusIndicator extends ConsumerWidget {
  const _VaultStatusIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(vaultStatusProvider).valueOrNull;
    final autoRefresh = ref.watch(vaultAutoRefreshProvider);

    switch (status) {
      case null:
      case VaultStatus.notConfigured:
        return const _StatusEntry(
          icon: Icons.lock_open_outlined,
          color: Colors.grey,
          message: 'Backup vault: not set up (Settings → Vault)',
        );
      case VaultStatus.locked:
        return const _StatusEntry(
          icon: Icons.lock_clock_outlined,
          color: Colors.amber,
          message:
              'Backup vault: locked — enter your password to resume '
              'encrypted, signed backups',
        );
      case VaultStatus.unlocked:
        return _StatusEntry(
          icon: Icons.lock_outlined,
          color: Colors.green,
          message: autoRefresh
              ? 'Backup vault: unlocked — encrypted backups (AES-256) '
                    'running automatically'
              : 'Backup vault: unlocked, encryption ready, but automatic '
                    'backups are off (Settings → Vault)',
        );
    }
  }
}

class _DriveStatusIndicator extends ConsumerStatefulWidget {
  const _DriveStatusIndicator();

  @override
  ConsumerState<_DriveStatusIndicator> createState() =>
      _DriveStatusIndicatorState();
}

class _DriveStatusIndicatorState extends ConsumerState<_DriveStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(driveConnectionProvider);
    final syncing = ref.watch(driveSyncActiveProvider);

    if (syncing && !_flicker.isAnimating) {
      _flicker.repeat(reverse: true);
    } else if (!syncing && _flicker.isAnimating) {
      _flicker.stop();
      _flicker.value = 0;
    }

    final (icon, color, label) = switch (connection) {
      DriveConnectionStatus.signedIn => (
        Icons.cloud_done_outlined,
        Colors.green,
        syncing
            ? 'Google Drive: connected — syncing now'
            : 'Google Drive: connected',
      ),
      DriveConnectionStatus.signingIn => (
        Icons.cloud_sync_outlined,
        Colors.amber,
        'Google Drive: connecting…',
      ),
      DriveConnectionStatus.signedOut || DriveConnectionStatus.unknown => (
        Icons.cloud_off_outlined,
        Colors.grey,
        'Google Drive: not connected (Settings → Google Drive)',
      ),
    };

    Widget dot = Icon(icon, size: 14, color: color);
    if (syncing) {
      dot = AnimatedBuilder(
        animation: _flicker,
        builder: (context, child) =>
            Opacity(opacity: 0.4 + (0.6 * (1 - _flicker.value)), child: child),
        child: dot,
      );
    }

    return Tooltip(message: label, child: dot);
  }
}
