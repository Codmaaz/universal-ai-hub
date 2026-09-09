import 'package:flutter/material.dart';

import '../../adapters/adapter_registry.dart';
import '../../adapters/ai_provider_adapter.dart';
import '../../app/app_services.dart';
import '../../app/shell/home_shell.dart';
import '../../core/models/provider.dart';
import '../../core/models/types.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/url_builder.dart';
import '../chat/widgets/connection_result_dialog.dart';

/// Add (wizard-like, guided order) or edit a provider profile.
class ProviderFormScreen extends StatefulWidget {
  const ProviderFormScreen({super.key, this.initial});

  final AIProvider? initial;

  @override
  State<ProviderFormScreen> createState() => _ProviderFormScreenState();
}

class _HeaderEntry {
  _HeaderEntry({required this.name, required this.value});
  final TextEditingController name;
  final TextEditingController value;
}

class _ProviderFormScreenState extends State<ProviderFormScreen> {
  late ProviderType _type;
  bool get _isEdit => widget.initial != null;

  final _nameCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  final _endpointCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _authNameCtrl = TextEditingController();
  final _authValueCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _bodyTemplateCtrl = TextEditingController();
  final _responsePathCtrl = TextEditingController();

  late AuthMethod _auth;
  late HttpMethod _http;
  bool _streaming = true;
  bool _revealKey = false;
  bool _hasStoredKey = false;
  final List<_HeaderEntry> _headers = [];
  final Map<AiCapability, TextEditingController> _capEndpoint = {};
  final Map<AiCapability, TextEditingController> _capMethod = {};
  final Map<AiCapability, TextEditingController> _capTemplate = {};
  final Map<AiCapability, TextEditingController> _capResponse = {};
  Set<AiCapability> _selectedCapabilities = {AiCapability.chat};
  bool _saving = false;
bool _testing = false;
bool _fetchingModels = false;

List<String> _availableModels = [];
String? _modelsFetchError;

String? _baseError;
String? _modelError;

  // Track whether user has customized base URL/model so type changes can
  // refresh suggestions without clobbering their input.
  String _lastDefaultBase = '';
  String _lastDefaultModel = '';

  late final AppServices services;

  @override
  void initState() {
    super.initState();
    services = AppScope.of(context);
    final init = widget.initial;
    _type = init?.type ?? ProviderType.openaiCompatible;
    final defaults = AdapterRegistry.defaultsFor(_type);
    _lastDefaultBase = defaults.baseUrl;
    _lastDefaultModel = defaults.model;
    _auth = init?.authMethod ?? defaults.authMethod;
    _http = init?.httpMethod ?? HttpMethod.post;

    if (init != null) {
      _selectedCapabilities = init.enabledCapabilities.toSet();
      if (_selectedCapabilities.isEmpty) _selectedCapabilities = {AiCapability.chat};
      _nameCtrl.text = init.name;
      _baseCtrl.text = init.baseUrl;
      _endpointCtrl.text = init.endpoint;
      _modelCtrl.text = init.model;
      _authNameCtrl.text = init.customAuthHeaderName;
      _authValueCtrl.text = init.customAuthHeaderValue;
      _streaming = init.streamingEnabled;
      _bodyTemplateCtrl.text = init.requestBodyTemplate;
      _responsePathCtrl.text = init.responsePath;
      for (final h in init.customHeaders) {
        _headers.add(_HeaderEntry(
            name: TextEditingController(text: h.name),
            value: TextEditingController(text: h.value)));
      }
      for (final capability in AiCapability.values) {
        final key = capability.name;
        if (init.capabilityEndpoints.containsKey(key) || init.capabilityRequestTemplates.containsKey(key) || init.capabilityResponsePaths.containsKey(key)) {
          _capEndpoint[capability] = TextEditingController(text: init.capabilityEndpoints[key] ?? '');
          _capMethod[capability] = TextEditingController(text: init.capabilityMethods[key] ?? 'POST');
          _capTemplate[capability] = TextEditingController(text: init.capabilityRequestTemplates[key] ?? '');
          _capResponse[capability] = TextEditingController(text: init.capabilityResponsePaths[key] ?? '');
        }
      }
      _hasStoredKeyFuture();
    } else {
      _baseCtrl.text = defaults.baseUrl;
      if (_type == ProviderType.anthropic) {
        // Anthropic accepts x-api-key; keep bearer default documented.
      }
      if (_type == ProviderType.gemini) {
        _authNameCtrl.text = 'key';
      }
      if (_type == ProviderType.universalHttp) {
        _ensureUniversalEditors();
      }
    }
  }

  Future<void> _hasStoredKeyFuture() async {
    final id = widget.initial!.id;
    final has = await services.providerService.hasKey(id);
    if (mounted) setState(() => _hasStoredKey = has);
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _baseCtrl,
      _endpointCtrl,
      _keyCtrl,
      _authNameCtrl,
      _authValueCtrl,
      _modelCtrl,
      _bodyTemplateCtrl,
      _responsePathCtrl,
    ]) {
      c.dispose();
    }
    for (final h in _headers) {
      h.name.dispose();
      h.value.dispose();
    }
    for (final c in [..._capEndpoint.values, ..._capMethod.values, ..._capTemplate.values, ..._capResponse.values]) { c.dispose(); }
    super.dispose();
  }

  void _onTypeChanged(ProviderType next) {
    if (next == _type) return;
    final changedFromDefault =
        _baseCtrl.text.trim() == _lastDefaultBase ||
            _baseCtrl.text.trim().isEmpty;
    final modelFromDefault = _modelCtrl.text.trim() == _lastDefaultModel ||
        _modelCtrl.text.trim().isEmpty;
    if (_isEdit && !changedFromDefault && !modelFromDefault) {
      // Warn the user before discarding customized fields on type change.
      showAppSnack(context,
          'Provider type changed — check the Base URL and model below.');
    }
    setState(() {
      _type = next;
      final defaults = AdapterRegistry.defaultsFor(next);
      _lastDefaultBase = defaults.baseUrl;
      _lastDefaultModel = defaults.model;
      if (changedFromDefault) _baseCtrl.text = defaults.baseUrl;
      if (modelFromDefault && _type != ProviderType.openaiCompatible) {
        _modelCtrl.text = defaults.model;
      }
      // Sensible auth default per family.
      if (next == ProviderType.universalHttp) {
        if (_selectedCapabilities.isEmpty) _selectedCapabilities = {AiCapability.chat};
        _ensureUniversalEditors();
      }
      if (next == ProviderType.gemini) {
        _auth = AuthMethod.queryParam;
        _authNameCtrl.text = 'key';
      } else if (_auth == AuthMethod.queryParam) {
        _auth = AuthMethod.bearerToken;
        _authNameCtrl.text = '';
      }
      _authValueCtrl.text =
          _auth == AuthMethod.customHeader ? r'{{API_KEY}}' : _authValueCtrl.text;
      _baseError = null;
      _modelError = null;
    });
  }


  AIProvider _draft() => AIProvider(
        id: _isEdit ? widget.initial!.id : 'draft',
        name: _nameCtrl.text.trim(),
        type: _type,
        baseUrl: _baseCtrl.text.trim(),
        authMethod: _auth,
        customAuthHeaderName: _authNameCtrl.text.trim(),
        customAuthHeaderValue: _authValueCtrl.text,
        customHeaders: [
          for (final h in _headers)
            HttpHeader(name: h.name.text.trim(), value: h.value.text),
        ],
        model: _modelCtrl.text.trim(),
        endpoint: _endpointCtrl.text.trim(),
        isEnabled: true,
        streamingEnabled: _streaming,
        httpMethod: _http,
        requestBodyTemplate: _bodyTemplateCtrl.text,
        responsePath: _responsePathCtrl.text,
        enabledCapabilities: _type == ProviderType.universalHttp
            ? _universalCapabilities()
            : const [AiCapability.chat],
        capabilityEndpoints: _universalMap(_capEndpoint),
        capabilityMethods: _universalMap(_capMethod),
        capabilityRequestTemplates: _universalMap(_capTemplate),
        capabilityResponsePaths: _universalMap(_capResponse),
      );

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final draft = _draft();
    final adapter = AdapterRegistry.forType(_type);
    final cfgError = adapter.validateConfiguration(draft);
    if (_nameCtrl.text.trim().isEmpty) {
      showAppSnack(context, 'Give the provider a name first.', error: true);
      return;
    }
    final urlError = UrlBuilder.validate(_baseCtrl.text);
    if (urlError != null) {
      showAppSnack(context, urlError, error: true);
      return;
    }
    if (cfgError != null) {
      showAppSnack(context, cfgError, error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final outcome = await services.providerService.save(
        existingId: _isEdit ? widget.initial!.id : null,
        name: _nameCtrl.text,
        type: _type,
        baseUrl: _baseCtrl.text,
        authMethod: _auth,
        authHeaderName: _authNameCtrl.text,
        authHeaderValue: _authValueCtrl.text,
        apiKey: _keyCtrl.text,
        customHeaders: draft.customHeaders,
        model: _modelCtrl.text,
        endpoint: _endpointCtrl.text,
        isEnabled: true,
        streamingEnabled: _streaming,
        httpMethod: _http,
        requestBodyTemplate: _bodyTemplateCtrl.text,
        responsePath: _responsePathCtrl.text,
        enabledCapabilities: _type == ProviderType.universalHttp
            ? _universalCapabilities()
            : const [AiCapability.chat],
        capabilityEndpoints: _universalMap(_capEndpoint),
        capabilityMethods: _universalMap(_capMethod),
        capabilityRequestTemplates: _universalMap(_capTemplate),
        capabilityResponsePaths: _universalMap(_capResponse),
      );
      await services.state.refreshProviders();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
    Future<void> _fetchModels() async {
  FocusScope.of(context).unfocus();

  if (_fetchingModels) return;

  final urlError = UrlBuilder.validate(_baseCtrl.text);

  if (urlError != null) {
    showAppSnack(context, urlError, error: true);
    return;
  }

  final draft = _draft();
  final typedKey = _keyCtrl.text.trim();
  final apiKey = typedKey.isNotEmpty
      ? typedKey
      : (await services.providerService.readKey(draft.id) ?? '');

  if (apiKey.isEmpty) {
    showAppSnack(
      context,
      'Add an API key first, then tap Update.',
      error: true,
    );
    return;
  }


  final adapter = AdapterRegistry.forType(_type);

  if (!adapter.capabilities.supportsModelListing) {
    showAppSnack(
      context,
      'This provider type does not support automatic model listing.',
      error: true,
    );
    return;
  }

  setState(() {
    _fetchingModels = true;
    _modelsFetchError = null;
  });

  try {
    final models =
        await services.providerService.fetchModelsForDraft(
      draft: draft,
      apiKey: apiKey,
    );

    if (!mounted) return;

    setState(() {
      _availableModels = models;
      _fetchingModels = false;

      if (models.isEmpty) {
        _modelsFetchError =
            'The API returned an empty model list.';
      }

      if (models.isNotEmpty &&
          _modelCtrl.text.trim().isEmpty) {
        _modelCtrl.text = models.first;
      }
    });

    if (models.isNotEmpty) {
      showAppSnack(
        context,
        '${models.length} models found.',
      );
    }
  } on ApiException catch (e) {
    if (!mounted) return;

    setState(() {
      _fetchingModels = false;
      _modelsFetchError = e.message;
    });

    showAppSnack(
      context,
      e.message,
      error: true,
    );
  } catch (_) {
    if (!mounted) return;

    setState(() {
      _fetchingModels = false;
      _modelsFetchError =
          'Could not fetch models. Check the Base URL and API key.';
    });

    showAppSnack(
      context,
      'Could not fetch models. Check the Base URL and API key.',
      error: true,
    );
  }
}
  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    final urlError = UrlBuilder.validate(_baseCtrl.text);
    if (urlError != null) {
      showAppSnack(context, urlError, error: true);
      return;
    }
    if (_keyCtrl.text.trim().isEmpty && !_hasStoredKey) {
      showAppSnack(context,
          'Enter an API key first — the test needs it to authenticate.',
          error: true);
      return;
    }
    final draft = _draft();
    final apiKey = _keyCtrl.text.trim().isEmpty
        ? await services.providerService.readKey(draft.id)
        : _keyCtrl.text.trim();
    if (apiKey == null || apiKey.isEmpty) {
      showAppSnack(context, 'No API key available for this test.',
          error: true);
      return;
    }
    setState(() => _testing = true);
    try {
      final result = await services.providerService.testDraft(
        draft: draft,
        apiKey: apiKey,
        inspectorEnabled:
            services.state.settings.requestInspectorEnabled,
      );
      if (!mounted) return;
      showConnectionResultDialog(context, result,
          providerName: _nameCtrl.text.trim().isEmpty
              ? 'Draft provider'
              : _nameCtrl.text.trim());
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit provider' : 'Add provider'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: _wizardProgress(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // 1. Name
          const _StepLabel(step: 1, title: 'Provider name'),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Provider name',
              hintText: 'e.g. My OpenAI-compatible gateway',
              helperText: AdapterRegistry.fieldHelp(_type, 'name'),
            ),
          ),
          const SizedBox(height: 20),

          // 2. API type
          const _StepLabel(step: 2, title: 'API type'),
          const SizedBox(height: 8),
          _TypePicker(current: _type, onChanged: _onTypeChanged),
          const SizedBox(height: 12),
          _CapabilityRow(type: _type),
          const SizedBox(height: 20),

          // 3. Connection
          const _StepLabel(step: 3, title: 'Connection'),
          const SizedBox(height: 8),
          TextField(
            controller: _baseCtrl,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.example.com/v1',
              helperText: AdapterRegistry.fieldHelp(_type, 'baseUrl'),
              errorText: _baseError,
            ),
            onChanged: (_) => setState(() => _baseError = null),
          ),
          if (services.state.settings.requestInspectorEnabled) ...[
            const SizedBox(height: 4),
            _ResolvedUrlPreview(provider: _draft()),
          ],
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Endpoint path (advanced)',
                style: TextStyle(fontSize: 14)),
            subtitle: Text(
              _endpointCtrl.text.trim().isEmpty
                  ? 'Uses the default for ${_type.label}: '
                      '${_defaultPathLabel()}'
                  : _endpointCtrl.text.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _endpointCtrl,
                  decoration: InputDecoration(
                    labelText: 'Endpoint path',
                    hintText: _type == ProviderType.custom
                        ? '/predict'
                        : '/chat/completions',
                    helperText:
                        'Overrides the standard endpoint for this API type.',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // API key + auth
          TextField(
            controller: _keyCtrl,
            obscureText: !_revealKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API key',
              helperText: _isEdit && _hasStoredKey
                  ? 'A key is already stored for this provider. Leave blank '
                      'to keep it.'
                  : 'Encrypted on-device only — never exported.',
              suffixIcon: IconButton(
                tooltip: _revealKey ? 'Hide key' : 'Reveal key',
                icon: Icon(_revealKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () {
                  if (!_revealKey && _keyCtrl.text.isNotEmpty) {
                    showAppSnack(context,
                        'The key is now visible on screen for a short check.');
                  }
                  setState(() => _revealKey = !_revealKey);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _authNameCtrl,
            enabled: _auth == AuthMethod.customHeader ||
                _auth == AuthMethod.queryParam,
            decoration: InputDecoration(
              labelText: _auth == AuthMethod.queryParam
                  ? 'Query parameter name'
                  : 'Auth header name',
              helperText: _auth == AuthMethod.queryParam
                  ? 'e.g. key or api_key'
                  : 'e.g. X-API-Key',
              isDense: true,
            ),
          ),
          if (_auth == AuthMethod.customHeader) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _authValueCtrl,
              decoration: const InputDecoration(
                labelText: 'Auth header value',
                helperText: 'You may use {{API_KEY}} inside the value.',
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<AuthMethod>(
            initialValue: _auth,
            decoration: const InputDecoration(
              labelText: 'Authentication',
              helperText: 'How the API key is attached to requests.',
              isDense: true,
            ),
            items: [
              for (final a in AuthMethod.values)
                DropdownMenuItem(value: a, child: Text(a.label)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _auth = v);
            },
          ),
          const SizedBox(height: 8),
          if (_type == ProviderType.custom || _type == ProviderType.universalHttp ||
              _auth == AuthMethod.customHeader ||
              _auth == AuthMethod.queryParam)
            _CustomHeadersEditor(
              headers: _headers,
              onAdd: () => setState(() =>
                  _headers.add(_HeaderEntry(
                      name: TextEditingController(),
                      value: TextEditingController()))),
              onRemove: (h) => setState(() {
                h.name.dispose();
                h.value.dispose();
                _headers.remove(h);
              }),
            ),
          if (_type != ProviderType.custom && _type != ProviderType.universalHttp) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Streaming responses',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Token-by-token answers. Needs SSE support.'),
              value: _streaming,
              onChanged: (v) => setState(() => _streaming = v),
            ),
          ],
          const SizedBox(height: 20),

          // 4. Model
          const _StepLabel(step: 4, title: 'Model'),
          const SizedBox(height: 8),
          TextField(
            controller: _modelCtrl,
            decoration: InputDecoration(
              labelText: 'Model',
              hintText: _modelHint(),
              helperText: _type == ProviderType.custom || _type == ProviderType.universalHttp
                  ? 'Optional unless the selected capability template uses {{MODEL}}.'
                  : 'You can also fetch the model list from the chat screen.',
              errorText: _modelError,
            ),
            onChanged: (_) => setState(() => _modelError = null),
          ),
          if (AdapterRegistry.forType(_type).capabilities.supportsModelListing) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _fetchingModels ? null : _fetchModels,
                icon: _fetchingModels
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(_fetchingModels ? 'Updating models…' : 'Update models'),
              ),
            ),
            if (_modelsFetchError != null) ...[
              const SizedBox(height: 6),
              Text(_modelsFetchError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_availableModels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${_availableModels.length} models available. Tap a model below to select it.',
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _availableModels.take(40).map((model) => ActionChip(
                  label: Text(model, style: const TextStyle(fontSize: 12)),
                  onPressed: () => setState(() => _modelCtrl.text = model),
                )).toList(),
              ),
              if (_availableModels.length > 40)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Showing the first 40 models. You can still type any model ID manually.',
                    style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ],
          if (AdapterRegistry.modelHints(_type).isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final hint in AdapterRegistry.modelHints(_type))
                  ActionChip(
                    label: Text(hint, style: const TextStyle(fontSize: 12)),
                    onPressed: () =>
                        setState(() => _modelCtrl.text = hint),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),

          // 5. Custom API configuration (advanced)
          if (_type == ProviderType.universalHttp) ...[
            const _StepLabel(step: 5, title: 'Capabilities', subtitle: 'Select what this API provides.'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cap in AiCapability.values)
                  FilterChip(
                    label: Text(cap.label),
                    selected: _selectedCapabilities.contains(cap),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCapabilities.add(cap);
                        } else if (_selectedCapabilities.length > 1) {
                          _selectedCapabilities.remove(cap);
                        }
                        _ensureUniversalEditors();
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _UniversalMappingEditor(
            capabilities: _universalCapabilities(),
            endpoints: _capEndpoint,
            methods: _capMethod,
            templates: _capTemplate,
            responses: _capResponse,
            onEnsure: _ensureUniversalEditors,
          ), const SizedBox(height: 20)],

          if (_type == ProviderType.custom) ...[
            const _StepLabel(
                step: 5,
                title: 'Custom API configuration',
                subtitle: 'Used only by the Custom API adapter.'),
            const SizedBox(height: 8),
            DropdownButtonFormField<HttpMethod>(
              initialValue: _http,
              decoration: const InputDecoration(
                  labelText: 'HTTP method', isDense: true),
              items: [
                for (final m in HttpMethod.values)
                  DropdownMenuItem(
                      value: m,
                      child: Text('${m.wire}  —  ${_methodHint(m)}')),
              ],
              onChanged: (v) => v != null ? setState(() => _http = v) : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyTemplateCtrl,
              maxLines: 7,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              decoration: const InputDecoration(
                labelText: 'Request body template',
                hintText: '{"model":"{{MODEL}}","prompt":"{{PROMPT}}"}',
                helperText:
                    'Valid JSON. Tokens: {{API_KEY}} {{MODEL}} {{PROMPT}} '
                    '{{SYSTEM_PROMPT}} {{MESSAGES}}',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final t in TemplateTokens.all)
                  ActionChip(
                    label: Text(t, style: const TextStyle(fontSize: 11)),
                    onPressed: () => _insertToken(t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _responsePathCtrl,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Response JSON path',
                hintText: 'choices[0].message.content',
                helperText:
                    'Where the assistant text lives in the response. '
                    'Examples: choices[0].message.content or response.text',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showTemplateHelp(),
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('Template reference'),
            ),
            const SizedBox(height: 20),
          ],

          // 6. Test + save
          _StepLabel(
              step: _isEdit ? 6 : 5,
              title: _isEdit ? 'Test and save' : 'Test and save'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: Text(_testing ? 'Testing…' : 'Test connection'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Testing sends one tiny request (max_tokens=1) to the provider '
            'with your configuration. No secrets leave this device.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_saving
                ? 'Saving…'
                : (_isEdit ? 'Save changes' : 'Save provider')),
          ),
        ),
      ),
    );
  }

  void _insertToken(String token) {
    final t = _bodyTemplateCtrl;
    final sel = t.selection;
    final text = t.text;
    final start = sel.isValid ? sel.start : text.length;
    final newText =
        text.replaceRange(start, sel.isValid ? sel.end : start, token);
    t.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + token.length));
    setState(() {});
  }

  List<AiCapability> _universalCapabilities() => _selectedCapabilities.toList();

  Map<String, String> _universalMap(Map<AiCapability, TextEditingController> source) => {
    for (final entry in source.entries)
      if (entry.value.text.trim().isNotEmpty) entry.key.name: entry.value.text.trim(),
  };

  void _ensureUniversalEditors() {
    for (final cap in _universalCapabilities()) {
      _capEndpoint.putIfAbsent(cap, () => TextEditingController());
      _capMethod.putIfAbsent(cap, () => TextEditingController(text: 'POST'));
      _capTemplate.putIfAbsent(cap, () => TextEditingController());
      _capResponse.putIfAbsent(cap, () => TextEditingController());
    }
  }

  String _defaultPathLabel() {
    switch (_type) {
      case ProviderType.openaiCompatible:
        return '/chat/completions (added automatically if missing)';
      case ProviderType.anthropic:
        return '/v1/messages (added automatically if missing)';
      case ProviderType.gemini:
        return 'the URL is built per model (:generateContent)';
      case ProviderType.custom:
        return 'the Base URL is used as-is';
      case ProviderType.universalHttp:
        return 'configured per capability';
    }
  }

  String _modelHint() {
    switch (_type) {
      case ProviderType.openaiCompatible:
        return 'e.g. gpt-4o-mini';
      case ProviderType.anthropic:
        return 'e.g. claude-3-5-sonnet-latest';
      case ProviderType.gemini:
        return 'e.g. gemini-2.5-flash';
      case ProviderType.custom:
        return 'optional';
      case ProviderType.universalHttp:
        return 'e.g. model-name';
    }
  }

  String _methodHint(HttpMethod m) {
    switch (m) {
      case HttpMethod.get:
        return 'no body';
      case HttpMethod.post:
        return 'body template sent as JSON';
      case HttpMethod.put:
        return 'body template sent as JSON';
      case HttpMethod.patch:
        return 'body template sent as JSON';
      case HttpMethod.delete:
        return 'destructive — connection auto-test disabled';
    }
  }

  void _showTemplateHelp() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Template placeholders',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              for (final (token, meaning) in [
                (TemplateTokens.apiKey, 'your API key (resolved at request '
                    'time; never stored in the template)'),
                (TemplateTokens.model, 'the selected model'),
                (TemplateTokens.prompt,
                    'the latest user message text'),
                (TemplateTokens.systemPrompt,
                    'the active system prompt (when set)'),
                (TemplateTokens.messages,
                    'full JSON array of {"role","content"} messages'),
              ]) ...[
                SelectableText(token,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(meaning,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
              ],
              const Text(
                'Body templates must remain valid JSON. Response JSON path '
                'supports dot and bracket notation, e.g. choices[0].message.'
                'content.',
                style: TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wizardProgress() {
    final steps = [
      'Name',
      'Type',
      'Connection',
      'Model',
      if (_type == ProviderType.custom) 'Custom',
      if (_type == ProviderType.universalHttp) 'Mappings',
      'Save',
    ];
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) => Chip(
          avatar: CircleAvatar(
              radius: 9,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer))),
          label: Text(steps[i], style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.step, required this.title, this.subtitle});

  final int step;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      CircleAvatar(
        radius: 11,
        backgroundColor: cs.primary,
        child: Text('$step',
            style: TextStyle(
                fontSize: 12,
                color: cs.onPrimary,
                fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (subtitle != null)
          Text(subtitle!,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    ]);
  }
}

class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.current, required this.onChanged});

  final ProviderType current;
  final ValueChanged<ProviderType> onChanged;

  @override
  Widget build(BuildContext context) {
    const list = [
      (ProviderType.openaiCompatible, Icons.model_training,
          'OpenAI Compatible', 'OpenAI, local servers & most gateways'),
      (ProviderType.anthropic, Icons.architecture,
          'Anthropic', 'Claude Messages API'),
      (ProviderType.gemini, Icons.auto_awesome,
          'Gemini', 'Google generative language API'),
      (ProviderType.custom, Icons.extension,
          'Custom API', 'Simple one-endpoint custom request'),
      (ProviderType.universalHttp, Icons.hub,
          'Universal HTTP API', 'Map chat, image, video, audio and other capabilities'),
    ];
    return Column(
      children: [
        for (final (t, icon, name, desc) in list)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                width: 2,
                color: current == t
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            child: RadioListTile<ProviderType>(
              value: t,
              groupValue: current,
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
              title: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(desc),
              secondary: Icon(icon),
            ),
          ),
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.type});
  final ProviderType type;

  @override
  Widget build(BuildContext context) {
    final caps = AdapterRegistry.forType(type).capabilities;
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (label, ok) in [
          ('Chat', caps.supportsChat),
          ('Streaming', caps.supportsStreaming),
          ('Model list', caps.supportsModelListing),
          ('Images', caps.supportsImages),
          ('Files', caps.supportsFiles),
          ('Audio', caps.supportsAudio),
        ])
          Chip(
            avatar: Icon(ok ? Icons.check_circle : Icons.block,
                size: 14,
                color: ok ? Colors.green.shade400 : cs.outline),
            label: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: ok ? cs.onSurface : cs.outline)),
            side: BorderSide.none,
            backgroundColor: cs.surfaceContainerHigh,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}


class _UniversalMappingEditor extends StatelessWidget {
  const _UniversalMappingEditor({
    required this.capabilities,
    required this.endpoints,
    required this.methods,
    required this.templates,
    required this.responses,
  });

  final List<AiCapability> capabilities;
  final Map<AiCapability, TextEditingController> endpoints;
  final Map<AiCapability, TextEditingController> methods;
  final Map<AiCapability, TextEditingController> templates;
  final Map<AiCapability, TextEditingController> responses;

  @override
  Widget build(BuildContext context) {
    final caps = widget.capabilities;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _StepLabel(
        step: 5,
        title: 'Universal capability mapping',
        subtitle: 'Tell the hub how each API operation is called and where its result lives.',
      ),
      const SizedBox(height: 8),
      const Text('The provider is not assumed to be OpenAI-compatible. Each capability can have its own endpoint, request template, and response path.'),
      const SizedBox(height: 12),
      for (final cap in caps) ...[
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cap.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: widget.methods[cap],
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'HTTP method', hintText: 'POST', isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: widget.endpoints[cap],
                decoration: InputDecoration(
                  labelText: 'Endpoint',
                  hintText: cap == AiCapability.chat ? '/chat' : '/${cap.name}',
                  helperText: 'Path appended to the Base URL. Full URLs are also accepted by the runtime.',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: widget.templates[cap],
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Request JSON template',
                  hintText: cap == AiCapability.chat
                      ? '{"model":"{{MODEL}}","messages":{{MESSAGES}}}'
                      : '{"model":"{{MODEL}}","prompt":"{{PROMPT}}"}',
                  helperText: 'Tokens: {{MODEL}} {{PROMPT}} {{SYSTEM_PROMPT}} {{MESSAGES}} {{SIZE}} {{N}} {{NEGATIVE_PROMPT}} {{ASPECT_RATIO}} {{DURATION}}',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: widget.responses[cap],
                decoration: InputDecoration(
                  labelText: 'Response path (optional for automatic extraction)',
                  hintText: cap == AiCapability.chat ? 'choices[0].message.content' : 'data[0].url',
                  helperText: 'Dot/bracket notation. For images/videos, URLs or base64 are also detected automatically.',
                  isDense: true,
                ),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _ResolvedUrlPreview extends StatelessWidget {
  const _ResolvedUrlPreview({required this.provider});
  final AIProvider provider;

  @override
  Widget build(BuildContext context) {
    if (provider.baseUrl.trim().isEmpty) return const SizedBox.shrink();
    String resolved;
    try {
      resolved = AdapterSupport.resolveUrl(provider);
    } catch (_) {
      resolved = '—';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Icon(Icons.visibility_outlined,
            size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: SelectableText(
            'Final request URL (developer preview): $resolved',
            style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}

class _CustomHeadersEditor extends StatelessWidget {
  const _CustomHeadersEditor({
    required this.headers,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_HeaderEntry> headers;
  final VoidCallback onAdd;
  final ValueChanged<_HeaderEntry> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(
              child: Text('Custom headers',
                  style: TextStyle(fontWeight: FontWeight.w600))),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add header'),
          ),
        ]),
        for (final h in headers)
          Row(children: [
            Expanded(
              child: TextField(
                controller: h.name,
                decoration:
                    const InputDecoration(labelText: 'Header', isDense: true),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: h.value,
                decoration: const InputDecoration(
                    labelText: 'Value ({{API_KEY}} ok)', isDense: true),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove header',
              onPressed: () => onRemove(h),
            ),
          ]),
        Text(
          'Never paste a real key here — store it in the API key field and '
          'reference it with {{API_KEY}}.',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
