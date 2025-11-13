import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile, ShareResultStatus;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/tts_provider_manager.dart';
import '../../core/providers/tts_provider.dart';
import '../../core/models/default_provider_templates.dart';
import '../../core/models/provider_template.dart';
import '../../core/services/custom_provider_storage.dart';
import 'vocabulary_import_screen.dart';
import 'vocabulary_screen.dart';

/// Settings screen for configuring TTS providers
class SettingsScreen extends StatefulWidget {
  final TTSProviderManager providerManager;

  const SettingsScreen({
    super.key,
    required this.providerManager,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, TextEditingController> _controllers = {};
  bool _isLoading = false;
  bool _isSaved = false;
  String? _errorMessage;
  String? _selectedProviderId;
  TTSProvider? _selectedProvider;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Try to load the active provider first
      final activeProvider = widget.providerManager.activeProvider;
      if (activeProvider != null) {
        _selectedProviderId = activeProvider.id;
        _selectedProvider = activeProvider;
        await _loadProviderConfiguration(activeProvider);
      } else {
        // Default to first available provider
        final providers = widget.providerManager.availableProviders;
        if (providers.isNotEmpty) {
          _selectedProviderId = providers.first.id;
          _selectedProvider = providers.first;
          await _loadProviderConfiguration(providers.first);
        }
      }
    } catch (e) {
      // Silently fail - user can still configure manually
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProviderConfiguration(TTSProvider provider) async {
    // Clear existing controllers
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();

    // Load saved config from storage (not just from provider instance)
    final config = await _loadSavedConfig(provider.id);

    // Create controllers for each config field with auto-save listeners
    for (final field in provider.getRequiredConfig()) {
      final controller = TextEditingController(
        text: config[field.key] ?? field.defaultValue ?? '',
      );
      // Add listener for auto-save when text changes
      controller.addListener(() => _autoSaveConfiguration());
      _controllers[field.key] = controller;
    }

    setState(() {
      _isSaved = config.isNotEmpty && _hasRequiredFields(provider, config);
    });
  }

  /// Load saved configuration from secure storage
  Future<Map<String, String>> _loadSavedConfig(String providerId) async {
    // Use the provider manager's internal storage access
    // We need to read from secure storage directly
    final provider = widget.providerManager.getProvider(providerId);
    if (provider == null) return {};

    // If provider is already initialized, use its config
    if (provider.isInitialized && provider.config.isNotEmpty) {
      return provider.config;
    }

    // Otherwise, try to initialize it temporarily to load the config
    try {
      final isReady = await widget.providerManager.isProviderReady(providerId);
      if (isReady) {
        return provider.config;
      }
    } catch (e) {
      // Ignore errors, we'll just show empty/default values
    }

    return {};
  }

  /// Check if required fields are filled
  bool _hasRequiredFields(TTSProvider provider, Map<String, String> config) {
    for (final field in provider.getRequiredConfig()) {
      if (field.isRequired && (config[field.key]?.isEmpty ?? true)) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Auto-save with debouncing (saves 1 second after user stops typing)
  void _autoSaveConfiguration() {
    // Cancel existing timer
    _autoSaveTimer?.cancel();

    // Set new timer for 1 second from now
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      _saveConfiguration(showSuccessMessage: false);
    });
  }

  Future<void> _saveConfiguration({bool showSuccessMessage = true}) async {
    final provider = _selectedProvider;
    if (provider == null) {
      setState(() {
        _errorMessage = 'Please select a provider';
      });
      return;
    }

    // Build config from controllers
    final config = <String, String>{};
    for (final field in provider.getRequiredConfig()) {
      final value = _controllers[field.key]?.text.trim() ?? '';
      if (field.isRequired && value.isEmpty) {
        // Don't show error for auto-save, only for manual save
        if (showSuccessMessage) {
          setState(() {
            _errorMessage = 'Please enter ${field.label}';
          });
        }
        return;
      }
      if (value.isNotEmpty) {
        config[field.key] = value;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSaved = false;
    });

    try {
      final success = await widget.providerManager.setActiveProvider(
        provider.id,
        config,
      );

      if (success) {
        setState(() {
          _isSaved = true;
        });

        if (mounted && showSuccessMessage) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${provider.name} configured successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (showSuccessMessage) {
          setState(() {
            _errorMessage = 'Failed to configure provider';
          });
        }
      }
    } catch (e) {
      if (showSuccessMessage) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onProviderChanged(String? providerId) async {
    if (providerId == null) return;

    final provider = widget.providerManager.getProvider(providerId);
    if (provider == null) return;

    setState(() {
      _selectedProviderId = providerId;
      _selectedProvider = provider;
      _errorMessage = null;
      _isSaved = false;
    });

    await _loadProviderConfiguration(provider);

    // Auto-save when provider is changed (if the provider has saved config)
    final config = await _loadSavedConfig(provider.id);
    if (config.isNotEmpty && _hasRequiredFields(provider, config)) {
      // Only auto-save if this provider was already configured
      await _saveConfiguration(showSuccessMessage: false);
    }
  }

  /// Import provider configuration from .speakjson file
  Future<void> _importProviderConfig() async {
    try {
      // Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['speakjson', 'json'],
      );

      if (result == null || result.files.isEmpty) {
        return; // User canceled
      }

      final file = File(result.files.single.path!);
      final jsonContent = await file.readAsString();

      // Parse template
      final template = ProviderTemplate.fromSpeakJson(jsonContent);

      // Check if provider already exists
      final prefs = await SharedPreferences.getInstance();
      final storage = CustomProviderStorage(prefs);
      final exists = await storage.exists(template.id);

      if (exists && mounted) {
        // Ask user if they want to replace
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Provider Already Exists'),
            content: Text(
              'A provider with ID "${template.id}" already exists. Do you want to replace it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: const Text('Replace'),
              ),
            ],
          ),
        );

        if (replace != true) return;
      }

      // Generate unique ID if needed
      var uniqueId = template.id;
      var uniqueName = template.name;
      final builtInIds = ['fish_audio', 'cartesia', 'elevenlabs', 'playht', 'resemble'];
      final existingProviders = widget.providerManager.availableProviders.map((p) => p.id).toSet();

      // If this ID already exists (built-in or imported), make it unique
      if (existingProviders.contains(uniqueId)) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        uniqueId = '${template.id}_imported_$timestamp';
        uniqueName = '${template.name} (Imported)';
      }

      // Create modified template with unique ID
      final uniqueTemplate = ProviderTemplate(
        id: uniqueId,
        name: uniqueName,
        description: template.description,
        baseUrl: template.baseUrl,
        supportsStreaming: template.supportsStreaming,
        configFields: template.configFields,
        endpoints: template.endpoints,
        requestFormat: template.requestFormat,
        responseFormat: template.responseFormat,
      );

      // Save template with unique ID
      await storage.save(uniqueTemplate);

      // Import into provider manager
      final success = await widget.providerManager.importCustomProvider(uniqueId);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to import provider'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Extract and save any included non-secret values from the JSON
      final json = jsonDecode(jsonContent) as Map<String, dynamic>;
      final providerJson = json['provider'] as Map<String, dynamic>;
      final configFieldsList = providerJson['configFields'] as List<dynamic>;

      final importedValues = <String, String>{};
      for (final fieldJson in configFieldsList) {
        final field = fieldJson as Map<String, dynamic>;
        final key = field['key'] as String;
        final value = field['value'] as String?;
        final isSecret = field['isSecret'] as bool? ?? false;

        // Only import non-secret values
        if (value != null && value.isNotEmpty && !isSecret) {
          importedValues[key] = value;
        }
      }

      // Save imported values to SharedPreferences using unique ID
      if (importedValues.isNotEmpty) {
        for (final entry in importedValues.entries) {
          await prefs.setString('${uniqueId}_${entry.key}', entry.value);
        }
      }

      // Refresh provider list and select the imported provider
      setState(() {
        _selectedProviderId = uniqueId;
        _selectedProvider = null;
      });

      // This will load the provider and trigger _loadProviderConfiguration
      await _onProviderChanged(uniqueId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$uniqueName imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Export current provider configuration as .speakjson file
  Future<void> _exportProviderConfig() async {
    final provider = _selectedProvider;
    if (provider == null) return;

    try {
      // Get provider template
      final template = DefaultProviderTemplates.getById(provider.id);
      if (template == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This provider cannot be exported'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Get current config values to include non-secret values in export
      final configValues = <String, String>{};
      for (final controller in _controllers.entries) {
        if (controller.value.text.isNotEmpty) {
          configValues[controller.key] = controller.value.text;
        }
      }

      // Convert to .speakjson format (will only include non-secret values)
      final jsonContent = template.toSpeakJson(configValues: configValues);

      // Write to temporary directory with proper extension
      final tempDir = Directory.systemTemp;
      final fileName = '${provider.id}.speakjson';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(jsonContent);

      // Share the file
      final xFile = XFile(tempFile.path, mimeType: 'application/json');

      // Get screen size for iPad popover positioning
      final box = context.findRenderObject() as RenderBox?;
      final sharePositionOrigin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      final result = await Share.shareXFiles(
        [xFile],
        subject: '${provider.name} TTS Provider Configuration',
        text: 'Import this configuration in Stuart Speaks to add the ${provider.name} provider.',
        sharePositionOrigin: sharePositionOrigin,
      );

      if (result.status == ShareResultStatus.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${provider.name} configuration exported!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _selectedProvider == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final providers = widget.providerManager.availableProviders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TTS Provider Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.book),
            tooltip: 'Vocabulary Dictionary',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const VocabularyScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.library_books),
            tooltip: 'Import Vocabulary',
            onPressed: () async {
              final wasImported = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => const VocabularyImportScreen(),
                ),
              );

              // If vocabulary was imported, notify TTS screen to reload
              if (wasImported == true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vocabulary updated! Word suggestions will reflect your import.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import Provider Config',
            onPressed: _importProviderConfig,
          ),
          if (_selectedProvider != null)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Export Provider Config',
              onPressed: _exportProviderConfig,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Provider Selection
              Text(
                'Select TTS Provider',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // Provider Dropdown
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Provider',
                  prefixIcon: const Icon(Icons.cloud),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedProviderId,
                    isExpanded: true,
                    items: providers.map((provider) {
                      return DropdownMenuItem(
                        value: provider.id,
                        child: Text(
                          provider.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: _onProviderChanged,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              if (_selectedProvider != null) ...[
                // Provider Configuration
                Builder(
                  builder: (context) {
                    final provider = _selectedProvider!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${provider.name} Configuration',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 16),

                        // Dynamic Configuration Fields
                        ..._buildConfigFields(provider),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Auto-save indicator
                if (_isSaved && !_isLoading)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Settings saved automatically',
                            style: TextStyle(color: Colors.green[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isSaved && !_isLoading) const SizedBox(height: 16),

                // Error Message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_errorMessage != null) const SizedBox(height: 16),

                // Help Section
                _buildHelpSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildConfigFields(TTSProvider provider) {
    final widgets = <Widget>[];

    for (final field in provider.getRequiredConfig()) {
      // Render dropdown if field has options
      if (field.options != null && field.options!.isNotEmpty) {
        widgets.add(
          InputDecorator(
            decoration: InputDecoration(
              labelText: '${field.label}${field.isRequired ? ' *' : ''}',
              hintText: field.hint,
              prefixIcon: const Icon(Icons.settings),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: _isSaved
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: () {
                  final controllerValue = _controllers[field.key]?.text;
                  // Check if controller value exists in options
                  if (controllerValue != null &&
                      controllerValue.isNotEmpty &&
                      field.options!.contains(controllerValue)) {
                    return controllerValue;
                  }
                  // Fall back to default or first option
                  return field.defaultValue ?? field.options!.first;
                }(),
                isExpanded: true,
                items: field.options!.map((option) {
                  return DropdownMenuItem(
                    value: option,
                    child: Text(
                      option,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    _controllers[field.key]?.text = value;
                  }
                },
              ),
            ),
          ),
        );
      } else {
        // Render text field for non-dropdown fields
        widgets.add(
          TextField(
            controller: _controllers[field.key],
            decoration: InputDecoration(
              labelText: '${field.label}${field.isRequired ? ' *' : ''}',
              hintText: field.hint,
              prefixIcon: Icon(
                field.isSecret ? Icons.key : Icons.settings,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: _isSaved
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
            ),
            obscureText: field.isSecret,
            enableInteractiveSelection: true,
            enableSuggestions: false,
            autocorrect: false,
          ),
        );
      }
      widgets.add(const SizedBox(height: 16));
    }

    return widgets;
  }

  Widget _buildHelpSection() {
    final provider = _selectedProvider;
    if (provider == null) return const SizedBox.shrink();

    String helpText;
    if (provider.id == 'fish_audio') {
      helpText = '''1. Visit fish.audio and sign in
2. Go to your API settings
3. Copy your API key
4. Create or select a voice model
5. Copy the model ID''';
    } else if (provider.id == 'cartesia') {
      helpText = '''1. Visit cartesia.ai and sign up
2. Get your API key from the dashboard
3. Visit play.cartesia.ai/voices to browse voices
4. Copy the voice ID (UUID format)
5. Model ID is typically "sonic-3"''';
    } else if (provider.id == 'elevenlabs') {
      helpText = '''1. Visit elevenlabs.io and sign up
2. Go to your profile settings
3. Copy your API key (xi-api-key)
4. Browse voices at elevenlabs.io/voice-library
5. Copy the voice ID from your selected voice
6. Model ID is typically "eleven_multilingual_v2"''';
    } else if (provider.id == 'playht') {
      helpText = '''1. Visit play.ht and sign up
2. Go to your dashboard settings
3. Copy your User ID
4. Copy your API Key
5. Clone a voice or use a pre-built voice
6. Copy the voice ID (manifest URL)
7. Voice Engine is typically "PlayDialog"''';
    } else if (provider.id == 'resemble') {
      helpText = '''1. Visit resemble.ai and sign up
2. Go to your profile to get API token
3. Clone a voice (requires 10s-1min of audio)
4. Copy the Voice UUID from your cloned voice
5. Optional: Create a project and copy Project UUID
6. Supports emotions: happy, sad, angry, neutral''';
    } else {
      helpText = 'Follow your provider\'s documentation to obtain the required credentials.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2563EB).withAlpha(76)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                'How to get your credentials',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            helpText,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
