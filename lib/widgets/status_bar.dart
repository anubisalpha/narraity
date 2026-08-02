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
/// [message] explains the color — shown via a tap-triggered SnackBar rather
/// than a hover `Tooltip`, since `Tooltip` needs an ancestor `Overlay` this
/// bar doesn't have (it lives in `Scaffold.bottomNavigationBar`, outside the
/// app's main Navigator — see app.dart's doc comment for the two different
/// ways of fixing that with a manual `Overlay` that went wrong first).
/// `ScaffoldMessenger`, unlike `Overlay`, *is* reachable from here.
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
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message))),
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
    final allowUnencrypted = ref.watch(vaultAllowUnencryptedProvider);

    switch (status) {
      case null:
      case VaultStatus.notConfigured:
      case VaultStatus.locked:
        // A password isn't unlocked this session in either of these two
        // cases, but backups may still be running unencrypted — see
        // VaultActions.refreshProject. That's a materially different state
        // from "nothing is happening at all," so it gets its own icon/color
        // rather than folding into the plain "not set up"/"locked" ones.
        if (allowUnencrypted && autoRefresh) {
          return _StatusEntry(
            icon: Icons.lock_open_outlined,
            color: Colors.orange,
            message: status == VaultStatus.locked
                ? 'Backup vault: locked, but backups are still running — '
                      'NOT encrypted (unlock for encrypted backups instead)'
                : 'Backup vault: no password set — backups are running, '
                      'but NOT encrypted (Settings → Vault)',
          );
        }
        return _StatusEntry(
          icon: status == VaultStatus.locked
              ? Icons.lock_clock_outlined
              : Icons.lock_open_outlined,
          color: status == VaultStatus.locked ? Colors.amber : Colors.grey,
          message: status == VaultStatus.locked
              ? 'Backup vault: locked — enter your password to resume '
                    'encrypted, signed backups'
              : 'Backup vault: not set up, no backups running '
                    '(Settings → Vault)',
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

    // Tap-triggered SnackBar rather than a hover Tooltip — see _StatusEntry's
    // doc for why (no Overlay ancestor available in this bar's position).
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(label))),
      child: dot,
    );
  }
}
