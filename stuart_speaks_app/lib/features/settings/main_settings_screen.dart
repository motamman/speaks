import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/services/user_profile_service.dart';
import '../../core/services/tts_provider_manager.dart';
import '../../core/services/input_method_service.dart';
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
  InputMethodService? _inputMethodService;
  bool _isLoading = true;
  String _version = '';
  String _buildNumber = '';
  InputMethod _inputMethod = InputMethod.wordWheel;
  Handedness _handedness = Handedness.right;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _profileService = UserProfileService(prefs);
    _inputMethodService = InputMethodService(prefs);

    // Load package info
    final packageInfo = await PackageInfo.fromPlatform();
    _version = packageInfo.version;
    _buildNumber = packageInfo.buildNumber;

    // Load input method preference
    _inputMethod = _inputMethodService!.getInputMethod();
    _handedness = _inputMethodService!.getHandedness();

    setState(() {
      _firstNameController.text = _profileService!.getFirstName();
      _lastNameController.text = _profileService!.getLastName();
      _isLoading = false;
    });

    // Add listeners for auto-save
    _firstNameController.addListener(_saveProfile);
    _lastNameController.addListener(_saveProfile);
  }

  void _setInputMethod(InputMethod method) {
    setState(() {
      _inputMethod = method;
    });
    _inputMethodService?.setInputMethod(method);
  }

  void _setHandedness(Handedness handedness) {
    setState(() {
      _handedness = handedness;
    });
    _inputMethodService?.setHandedness(handedness);
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

              const SizedBox(height: 24),

              // Input Method Section
              _buildSection(
                title: 'Input Method',
                icon: Icons.keyboard,
                child: _buildInputMethodSelector(),
              ),

              const SizedBox(height: 24),

              // About Section
              _buildSection(
                title: 'About Speaks',
                icon: Icons.info_outline,
                child: _buildAboutContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputMethodSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose how you want to type:',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),

          // Word Wheel option
          _buildInputMethodOption(
            title: 'Word Wheel',
            subtitle: 'Select complete words from a circular menu',
            icon: Icons.donut_large,
            isSelected: _inputMethod == InputMethod.wordWheel,
            onTap: () => _setInputMethod(InputMethod.wordWheel),
          ),

          // Spinner Keyboard option - disabled for now (code retained)
          // TODO: Re-enable when spinner keyboard is ready
          // const SizedBox(height: 12),
          // _buildInputMethodOption(
          //   title: 'Spinner Keyboard',
          //   subtitle: 'Type letter-by-letter with predictive reordering',
          //   icon: Icons.radio_button_checked,
          //   isSelected: _inputMethod == InputMethod.spinnerKeyboard,
          //   onTap: () => _setInputMethod(InputMethod.spinnerKeyboard),
          //   badge: 'NEW',
          // ),

          const SizedBox(height: 16),

          // Info about spinner keyboard - disabled
          // if (_inputMethod == InputMethod.spinnerKeyboard)
          //   Container(
          //     padding: const EdgeInsets.all(12),
          //     decoration: BoxDecoration(
          //       color: Colors.blue[50],
          //       borderRadius: BorderRadius.circular(8),
          //       border: Border.all(color: Colors.blue[200]!),
          //     ),
          //     child: Row(
          //       children: [
          //         Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
          //         const SizedBox(width: 8),
          //         Expanded(
          //           child: Text(
          //             'Long-press to activate, drag to type letters. The keyboard reorganizes to bring likely next letters closer.',
          //             style: TextStyle(
          //               fontSize: 12,
          //               color: Colors.blue[700],
          //             ),
          //           ),
          //         ),
          //       ],
          //     ),
          //   ),

          const SizedBox(height: 24),

          // Handedness section
          Text(
            'Which hand do you use?',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildHandednessOption(
                  title: 'Left',
                  icon: Icons.back_hand,
                  isSelected: _handedness == Handedness.left,
                  onTap: () => _setHandedness(Handedness.left),
                  flipIcon: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHandednessOption(
                  title: 'Right',
                  icon: Icons.back_hand,
                  isSelected: _handedness == Handedness.right,
                  onTap: () => _setHandedness(Handedness.right),
                  flipIcon: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHandednessOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool flipIcon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB).withAlpha(25) : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Transform.flip(
              flipX: flipIcon,
              child: Icon(
                icon,
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey[600],
                size: 32,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF2563EB) : Colors.black87,
              ),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.check_circle,
                  color: const Color(0xFF2563EB),
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputMethodOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    String? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB).withAlpha(25) : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2563EB) : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? const Color(0xFF2563EB) : Colors.black87,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: const Color(0xFF2563EB),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version and Build
          _buildInfoRow('Version', _version),
          const SizedBox(height: 8),
          _buildInfoRow('Build', _buildNumber),
          const SizedBox(height: 16),

          const Divider(),
          const SizedBox(height: 16),

          // Links section
          Text(
            'Resources',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),

          _buildLinkRow(
            icon: Icons.code,
            label: 'GitHub Repository',
            url: 'https://github.com/mtamsett/stuart-speaks',
          ),
          const SizedBox(height: 8),
          _buildLinkRow(
            icon: Icons.bug_report,
            label: 'Report Issues',
            url: 'https://github.com/mtamsett/stuart-speaks/issues',
          ),
          const SizedBox(height: 8),
          _buildLinkRow(
            icon: Icons.description,
            label: 'Documentation',
            url: 'https://github.com/mtamsett/stuart-speaks/blob/main/README.md',
          ),
          const SizedBox(height: 16),

          const Divider(),
          const SizedBox(height: 16),

          // Contact
          Text(
            'Contact',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          _buildLinkRow(
            icon: Icons.email,
            label: 'maurice@zennora.sv',
            url: 'mailto:maurice@zennora.sv',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLinkRow({
    required IconData icon,
    required String label,
    required String url,
  }) {
    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.blue[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue[600],
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Icon(Icons.open_in_new, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $urlString'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
