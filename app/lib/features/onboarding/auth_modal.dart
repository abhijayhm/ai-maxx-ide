import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/global_loader_provider.dart';
import '../../theme/workbench_colors.dart';

Future<void> showAuthModal(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.workbenchColors.elevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (sheetContext) => const _AuthModalSheet(),
  );
}

class _AuthModalSheet extends ConsumerStatefulWidget {
  const _AuthModalSheet();

  @override
  ConsumerState<_AuthModalSheet> createState() => _AuthModalSheetState();
}

class _AuthModalSheetState extends ConsumerState<_AuthModalSheet> {
  late final TextEditingController _serverUrlController;
  late final TextEditingController _apiKeyController;
  bool _obscure = true;
  bool _submitting = false;
  bool _sheetClosed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFields());
  }

  void _prefillFields() {
    if (!mounted) {
      return;
    }
    final session = ref.read(sessionProvider).valueOrNull;
    final config = ref.read(appConfigProvider);

    final serverUrl = session?.serverUrl.isNotEmpty == true
        ? session!.serverUrl
        : (config.serverUrl.isNotEmpty
            ? config.serverUrl
            : AppConfig.defaultServerUrl);
    _serverUrlController.text = serverUrl;

    if (session?.apiKey.isNotEmpty == true) {
      _apiKeyController.text = session!.apiKey;
    } else if (AppConfig.defaultApiKey.isNotEmpty) {
      _apiKeyController.text = AppConfig.defaultApiKey;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _closeSheet() {
    if (_sheetClosed || !mounted) {
      return;
    }
    _sheetClosed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    });
  }

  Future<void> _submit() async {
    final serverUrl = AppConfig.normalizeServerUrl(_serverUrlController.text);
    final apiKey = _apiKeyController.text.trim();

    if (serverUrl.isEmpty || Uri.tryParse(serverUrl)?.host.isEmpty == true) {
      setState(() => _error = 'Server URL is required.');
      return;
    }
    if (apiKey.isEmpty) {
      setState(() => _error = 'API key is required.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final handle =
        ref.read(globalLoaderProvider.notifier).acquire('Authenticating…');

    try {
      await ref.read(sessionProvider.notifier).persistServerUrl(serverUrl);
      await ref.read(sessionProvider.notifier).register(
            apiKey,
            serverUrl: serverUrl,
          );
      if (mounted) {
        _closeSheet();
      }
    } on DioException catch (error) {
      final detail = error.response?.data;
      setState(() {
        _error = detail is Map && detail['detail'] != null
            ? detail['detail'].toString()
            : 'Authentication failed. Check API key and server URL.';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      handle.release();
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Authenticate',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.fgStrong,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set the server URL and API key. Defaults match the repo .env for development.',
            style: TextStyle(color: colors.fgMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _serverUrlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://aimaxx.example.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'API key',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                  color: colors.fgMuted,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colors.statusError)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }
}
