import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// One third-party component bundled with the app, credited here per its
/// license's attribution requirement (or just as a courtesy where a license
/// doesn't require it).
class _Attribution {
  const _Attribution({required this.name, required this.license, this.url});
  final String name;
  final String license;
  final String? url;
}

const _attributions = [
  _Attribution(
    name: 'Flutter & the Dart/Flutter package ecosystem',
    license: 'BSD-3-Clause and various — see pubspec.yaml',
  ),
  _Attribution(
    name: 'Hunspell (spell check)',
    license: 'LGPL / GPL / MPL tri-license',
    url: 'https://github.com/hunspell/hunspell',
  ),
  _Attribution(
    name: 'Vosk (offline voice dictation, Windows)',
    license: 'Apache License 2.0',
    url: 'https://alphacephei.com/vosk/',
  ),
  _Attribution(
    name: 'Open English WordNet (thesaurus & dictionary)',
    license: 'CC BY 4.0',
    url: 'https://en-word.net/',
  ),
];

/// Version, license, and third-party credits — the content for Settings'
/// "About" category. Not a standalone screen: it's rendered inside
/// `SettingsScreen`'s existing side-nav content pane, same as every other
/// category.
class AboutSectionContent extends StatefulWidget {
  const AboutSectionContent({super.key});

  @override
  State<AboutSectionContent> createState() => _AboutSectionContentState();
}

class _AboutSectionContentState extends State<AboutSectionContent> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _packageInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Narraity', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          info == null ? 'Loading version...' : 'Version ${info.version} (build ${info.buildNumber})',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const Text(
          'A local-first novel writing app — your manuscript stays as plain files on your own '
          'device, with optional sync through your own Google Drive.',
        ),
        const SizedBox(height: 24),
        Text('License', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('© 2026 Anubis Productions. All rights reserved.'),
        const SizedBox(height: 4),
        const _LinkText(
          label: 'github.com/anubisalpha/narraity',
          url: 'https://github.com/anubisalpha/narraity',
        ),
        const SizedBox(height: 24),
        Text('Third-party components', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final attribution in _attributions)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attribution.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(attribution.license, style: Theme.of(context).textTheme.bodySmall),
                if (attribution.url != null)
                  _LinkText(label: attribution.url!, url: attribution.url!),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
