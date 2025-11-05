# Stuart Speaks

A powerful, accessible AAC (Augmentative and Alternative Communication) app built with Flutter, featuring AI-powered text-to-speech with voice cloning capabilities.

## Overview

Stuart Speaks is designed to help individuals with speech difficulties communicate effectively using AI-generated speech. The app features a predictive word wheel interface, multiple TTS provider support, and custom voice cloning capabilities.

## Features

### 🎯 Core Features
- **Predictive Word Wheel**: Smart word suggestions based on usage patterns
- **Sentence Starters**: Quick access to common phrases
- **Quick Action Buttons**: One-tap access to "Yes", "No", "Help", "Thank You"
- **Text Chunking**: Automatically splits long text for optimal TTS generation
- **Audio Queue Management**: Seamless playback of multiple audio chunks

### 🔊 Multiple TTS Providers

#### Voice Cloning Providers
1. **Fish.Audio**
   - Custom voice cloning for personalized voices
   - Supports MP3 and Opus formats
   - Advanced voice quality controls (temperature, top-p)
   - Best for: Creating Stuart's personal voice

2. **ElevenLabs**
   - Professional-grade voices with streaming support
   - Extensive voice library
   - Fine-grained voice settings (stability, similarity boost, style)
   - Best for: High-quality, natural-sounding voiceovers

3. **Play.ht**
   - Ultra-realistic instant voice cloning (30 seconds of audio)
   - Multiple voice engines (PlayDialog, Play3.0)
   - Quality and speed controls
   - Best for: Quick custom voice creation

4. **Resemble.AI**
   - Real-time voice cloning (10s-1min of audio)
   - Emotional control (happy, sad, angry, neutral)
   - 149+ languages supported
   - Best for: Expressive character voices

#### High-Performance Provider
5. **Cartesia AI**
   - Low-latency Sonic 3 model
   - Excellent for real-time applications
   - Multiple audio formats and sample rates
   - Best for: Fast response times

## Audio Format Compatibility

### Supported Formats
The app uses the `audioplayers` package and supports:
- MP3
- WAV (PCM)
- OGG
- AAC/M4A
- FLAC
- Opus
- μ-law/A-law

### Provider Response Formats

| Provider | Default Format | Response Type | Processing |
|----------|----------------|---------------|------------|
| Fish.Audio | MP3 | Raw bytes | Direct ✅ |
| Cartesia AI | WAV (PCM) | Raw bytes | Direct ✅ |
| ElevenLabs | MP3 | Raw bytes | Direct ✅ |
| Play.ht | MP3 | Raw bytes | Direct ✅ |
| Resemble.AI | MP3/WAV | JSON + fetch/base64 | Decoded ✅ |

### Audio Flow
```
User Input → TTS Provider → Uint8List (audio bytes) → AudioPlayer → Device Speakers
```

## Architecture

### Project Structure
```
lib/
├── core/
│   ├── models/
│   │   ├── tts_request.dart          # TTS request/response models
│   │   └── word.dart                 # Word usage tracking models
│   ├── providers/
│   │   ├── tts_provider.dart         # Abstract TTS provider interface
│   │   ├── fish_audio_provider.dart  # Fish.Audio implementation
│   │   ├── cartesia_provider.dart    # Cartesia AI implementation
│   │   ├── elevenlabs_provider.dart  # ElevenLabs implementation
│   │   ├── playht_provider.dart      # Play.ht implementation
│   │   └── resemble_provider.dart    # Resemble.AI implementation
│   └── services/
│       ├── tts_provider_manager.dart # Provider registration & switching
│       ├── audio_playback_service.dart # Audio playback & queue
│       ├── word_usage_tracker.dart   # Word frequency tracking
│       └── text_chunker.dart         # Text splitting for TTS
├── features/
│   ├── input/
│   │   └── word_wheel/              # Predictive word wheel widget
│   ├── settings/
│   │   └── settings_screen.dart     # Provider configuration UI
│   └── tts/
│       └── tts_screen.dart          # Main TTS interface
└── main.dart                         # App entry point
```

### Provider Pattern
All TTS providers implement the `TTSProvider` abstract class:
```dart
abstract class TTSProvider {
  String get id;
  String get name;
  String get description;
  bool get supportsStreaming;
  bool get supportsVoiceCloning;

  List<ConfigField> getRequiredConfig();
  Future<bool> initialize(Map<String, String> config);
  Future<String?> validateCredentials();
  Future<Uint8List> generateSpeech(TTSRequest request);
  Stream<Uint8List>? generateSpeechStream(TTSRequest request);
  Future<List<Voice>> getAvailableVoices();
}
```

## Getting Started

### Prerequisites
- Flutter SDK (3.0.0 or higher)
- Dart SDK (2.17.0 or higher)
- iOS 12.0+ / Android 5.0+
- API keys from your chosen TTS provider(s)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/stuart-speaks.git
cd stuart-speaks/stuart_speaks_app
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
# For iOS
flutter run -d ios

# For Android
flutter run -d android
```

### Configuration

1. Launch the app
2. Tap the Settings icon (⚙️)
3. Select your preferred TTS provider from the dropdown
4. Enter your API credentials:

#### Fish.Audio Setup
- Get API key from [fish.audio](https://fish.audio)
- Create/select a voice model
- Copy the model ID

#### Cartesia AI Setup
- Sign up at [cartesia.ai](https://cartesia.ai)
- Get API key from dashboard
- Browse voices at [play.cartesia.ai/voices](https://play.cartesia.ai/voices)
- Copy voice ID (UUID format)

#### ElevenLabs Setup
- Sign up at [elevenlabs.io](https://elevenlabs.io)
- Get API key from profile settings
- Browse [voice library](https://elevenlabs.io/voice-library)
- Copy voice ID

#### Play.ht Setup
- Sign up at [play.ht](https://play.ht)
- Get User ID and API Key from dashboard
- Clone a voice or use pre-built voices
- Copy voice manifest URL

#### Resemble.AI Setup
- Sign up at [resemble.ai](https://resemble.ai)
- Get API token from profile
- Clone a voice (requires 10s-1min of audio)
- Copy Voice UUID

5. Click "Save Configuration"

## Usage

### Basic Operation
1. Type your message or use the word wheel for suggestions
2. Tap "SPEAK NOW" to generate and play speech
3. Use quick action buttons for common phrases

### Word Wheel
- Start typing to see suggestions based on your usage history
- Tap and hold the center to see sentence starters
- Selected words are tracked for better future suggestions

### Advanced Features
- **Text Chunking**: Long text is automatically split into chunks for better quality
- **Queue Playback**: Multiple audio chunks play seamlessly in sequence
- **Provider Switching**: Change TTS providers without losing configurations

## Development

### Running Tests
```bash
flutter test
```

### Code Analysis
```bash
flutter analyze
```

### Building for Production

#### iOS
```bash
flutter build ios --release
```

#### Android
```bash
flutter build apk --release
```

## Dependencies

### Core
- `flutter` - UI framework
- `http` - HTTP client for API calls
- `audioplayers` - Audio playback
- `flutter_secure_storage` - Secure credential storage
- `shared_preferences` - Local data persistence

## Future Enhancements

### Planned Features
- [ ] WebSocket streaming for real-time TTS
- [ ] Offline TTS support
- [ ] Voice recording for custom cloning
- [ ] Multi-language support
- [ ] Custom phrase library
- [ ] Voice emotion controls
- [ ] Accessibility improvements (switch control, eye tracking)
- [ ] Cloud backup for settings and phrases
- [ ] Widget support for quick access

### Provider Roadmap
- [ ] Google Cloud Text-to-Speech
- [ ] Amazon Polly
- [ ] Microsoft Azure Speech
- [ ] OpenAI TTS
- [ ] Coqui TTS (open source, self-hosted)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Guidelines
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built for Stuart and others with speech difficulties
- Powered by cutting-edge AI voice cloning technology
- Inspired by the AAC community's needs

## Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Contact: [maurice@znnora.sv]

## Privacy & Security

- API keys are stored securely using `flutter_secure_storage`
- No audio data is stored locally
- All TTS generation happens via secure HTTPS connections
- Usage data (word frequencies) is stored locally only

---

Made with ❤️ for accessible communication
