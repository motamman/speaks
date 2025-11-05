import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/tts_provider_manager.dart';
import '../../core/providers/tts_provider.dart';

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
        ),
      );
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
