import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/user_profile_service.dart';
import '../../core/services/tts_provider_manager.dart';
import '../../core/constants/accessibility_constants.dart';
import 'settings_screen.dart'; // TTS Provider Settings
import 'vocabulary_screen.dart';
import 'vocabulary_import_screen.dart';

/// Main settings screen with user profile and navigation to subsections
class MainSettingsScreen extends StatefulWidget {
  final TTSProviderManager providerManager;

  const MainSettingsScreen({
    super.key,
    required this.providerManager,
  });

  @override
  State<MainSettingsScreen> createState() => _MainSettingsScreenState();
}

class _MainSettingsScreenState extends State<MainSettingsScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  UserProfileService? _profileService;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _profileService = UserProfileService(prefs);

    setState(() {
      _firstNameController.text = _profileService!.getFirstName();
      _lastNameController.text = _profileService!.getLastName();
      _isLoading = false;
    });

    // Add listeners for auto-save
    _firstNameController.addListener(_saveProfile);
    _lastNameController.addListener(_saveProfile);
  }

  void _saveProfile() {
    final profileService = _profileService;
    if (profileService != null) {
      profileService.setFirstName(_firstNameController.text);
      profileService.setLastName(_lastNameController.text);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Profile Section
              _buildSection(
                title: 'User Profile',
                icon: Icons.person,
                child: Column(
                  children: [
                    TextField(
                      controller: _firstNameController,
                      decoration: InputDecoration(
                        labelText: 'First Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _lastNameController,
                      decoration: InputDecoration(
                        labelText: 'Last Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'App title: ${_profileService?.getAppTitle() ?? "Speaks"}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // TTS Provider Settings Section
              _buildSection(
                title: 'Text-to-Speech',
                icon: Icons.record_voice_over,
                child: _buildSettingsButton(
                  icon: Icons.cloud,
                  title: 'TTS Provider Settings',
                  subtitle: 'Configure your text-to-speech provider',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SettingsScreen(
                          providerManager: widget.providerManager,
                        ),
                      ),
                    );
                    // Reload profile in case anything changed
                    setState(() {});
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Vocabulary Section
              _buildSection(
                title: 'Vocabulary',
                icon: Icons.book,
                child: Column(
                  children: [
                    _buildSettingsButton(
                      icon: Icons.library_books,
                      title: 'Vocabulary Dictionary',
                      subtitle: 'View and manage your vocabulary',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const VocabularyScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSettingsButton(
                      icon: Icons.file_upload,
                      title: 'Import Vocabulary',
                      subtitle: 'Import words from a file',
                      onTap: () async {
                        final wasImported = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const VocabularyImportScreen(),
                          ),
                        );

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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2563EB),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }

  Widget _buildSettingsButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF2563EB),
                  size: AccessibilityConstants.standardIconSize,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
