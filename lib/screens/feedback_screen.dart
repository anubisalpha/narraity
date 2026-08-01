import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/dictation_engine.dart';
import '../services/github_auth_service.dart';
import '../services/github_discussions_service.dart';
import '../state/dictation_provider.dart';
import '../state/github_feedback_provider.dart';

const _discussionsUrl = 'https://github.com/anubisalpha/narraity/discussions/categories/app-feedback';

/// Settings → "Send Feedback". Posts to the Narraity repo's GitHub
/// Discussions "App Feedback" category, attributed to the user's own GitHub
/// account (see PLAN.md's "Feedback" section for the full design and why
/// `mailto:` was superseded by this).
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _includeDiagnostics = false;
  bool _posting = false;
  String? _postError;
  String? _postedUrl;

  bool _signingIn = false;
  String? _signInError;
  DeviceCodeRequest? _deviceCode;

  bool _dictating = false;
  DictationEngine? _dictationEngine;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _dictationEngine?.dispose();
    super.dispose();
  }

  Future<void> _startSignIn() async {
    setState(() {
      _signingIn = true;
      _signInError = null;
      _deviceCode = null;
    });

    final auth = ref.read(githubAuthServiceProvider);
    try {
      final request = await auth.requestDeviceCode();
      if (!mounted) return;
      setState(() => _deviceCode = request);

      // Open the browser immediately so the user isn't hunting for the button.
      await launchUrl(Uri.parse(request.verificationUri));

      var cancelled = false;
      await auth.pollForToken(
        request,
        isCancelled: () => cancelled || !mounted,
      );
      if (!mounted) return;
      ref.invalidate(githubSignedInProvider);
    } on GitHubAuthException catch (error) {
      if (mounted) setState(() => _signInError = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _deviceCode = null;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await ref.read(githubAuthServiceProvider).signOut();
    ref.invalidate(githubSignedInProvider);
  }

  Future<void> _toggleDictation() async {
    if (_dictating) {
      await _dictationEngine?.stop();
      setState(() => _dictating = false);
      return;
    }

    try {
      _dictationEngine ??= await ref.read(dictationEngineProvider.future);
      await _dictationEngine!.start((result) {
        if (!result.isFinal) return;
        final text = _bodyController.text;
        final needsSpace = text.isNotEmpty && !text.endsWith(' ') && !text.endsWith('\n');
        _bodyController.text = '$text${needsSpace ? ' ' : ''}${result.text}';
        _bodyController.selection = TextSelection.collapsed(offset: _bodyController.text.length);
      });
      if (mounted) setState(() => _dictating = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start dictation: $error')),
        );
      }
    }
  }

  Future<String> _buildBody() async {
    var body = _bodyController.text.trim();
    if (_includeDiagnostics) {
      final info = await PackageInfo.fromPlatform();
      body += '\n\n---\nApp version: ${info.version} (build ${info.buildNumber})\n'
          'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    }
    return body;
  }

  Future<void> _confirmAndPost() async {
    String username;
    try {
      final token = await ref.read(githubAuthServiceProvider).currentToken();
      username = token == null
          ? 'your GitHub account'
          : await ref.read(githubDiscussionsServiceProvider).fetchViewerLogin(token);
    } catch (_) {
      username = 'your GitHub account';
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post feedback publicly?'),
        content: Text('This will be posted publicly to GitHub as $username.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Post')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _post();
  }

  Future<void> _post() async {
    setState(() {
      _posting = true;
      _postError = null;
    });

    try {
      final auth = ref.read(githubAuthServiceProvider);
      final token = await auth.currentToken();
      if (token == null) throw GitHubDiscussionsException('Not signed in.');

      final body = await _buildBody();
      final url = await ref.read(githubDiscussionsServiceProvider).postFeedback(
            accessToken: token,
            title: _titleController.text.trim(),
            body: body,
          );

      if (!mounted) return;
      setState(() {
        _postedUrl = url;
        _titleController.clear();
        _bodyController.clear();
      });
    } on GitHubDiscussionsException catch (error) {
      if (mounted) setState(() => _postError = error.message);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedInAsync = ref.watch(githubSignedInProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Send Feedback')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: signedInAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
          data: (signedIn) => signedIn ? _buildSignedInForm(context) : _buildSignedOutExplainer(context),
        ),
      ),
    );
  }

  Widget _buildSignedOutExplainer(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Send Feedback', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text(
            'Where it goes: feedback is posted publicly to the Narraity GitHub repo\'s '
            'Discussions, "App Feedback" category — anyone can read it, including other users.',
          ),
          const SizedBox(height: 8),
          const Text(
            'What\'s required: a GitHub account, signed in below. Your post is attributed to your '
            'real GitHub username, not anonymous.',
          ),
          const SizedBox(height: 24),
          if (_signInError != null) ...[
            Text(
              _signInError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          if (_deviceCode case final device?) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Enter this code at the GitHub page that just opened:'),
                    const SizedBox(height: 8),
                    SelectableText(
                      device.userCode,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontFeatures: [const FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => launchUrl(Uri.parse(device.verificationUri)),
                      child: Text('Open ${device.verificationUri}'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              FilledButton.icon(
                onPressed: _signingIn ? null : _startSignIn,
                icon: _signingIn
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(_signingIn ? 'Waiting for approval...' : 'Continue with GitHub'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(_discussionsUrl)),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Discussions in browser'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'No GitHub account? Sign up at github.com/signup, or use "Open Discussions in '
            'browser" to read existing feedback and post manually if you already have an '
            'account you\'d rather not connect to Narraity.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedInForm(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Posts publicly to GitHub Discussions, "App Feedback" category.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(onPressed: _signOut, child: const Text('Sign out of GitHub')),
            ],
          ),
          const SizedBox(height: 16),
          if (_postedUrl case final url?) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(child: Text('Feedback posted. Thank you!')),
                    TextButton(
                      onPressed: () => launchUrl(Uri.parse(url)),
                      child: const Text('View on GitHub'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _titleController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            onChanged: (_) => setState(() {}),
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Feedback',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _dictating ? 'Stop dictation' : 'Dictate',
                icon: Icon(_dictating ? Icons.mic : Icons.mic_none_outlined,
                    color: _dictating ? Theme.of(context).colorScheme.error : null),
                onPressed: _toggleDictation,
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _includeDiagnostics,
            onChanged: (value) => setState(() => _includeDiagnostics = value ?? false),
            title: const Text('Include diagnostic info (app version, platform)'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (_postError != null) ...[
            Text(_postError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: (_posting ||
                    _titleController.text.trim().isEmpty ||
                    _bodyController.text.trim().isEmpty)
                ? null
                : _confirmAndPost,
            child: _posting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Post Feedback'),
          ),
        ],
      ),
    );
  }
}
