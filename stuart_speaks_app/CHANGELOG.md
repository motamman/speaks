# Changelog

All notable changes to Stuart Speaks will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- WebSocket streaming implementation for ElevenLabs
- WebSocket streaming implementation for Play.ht
- WebSocket streaming implementation for Resemble.AI
- Offline TTS support
- Voice recording interface for custom cloning
- Custom phrase library
- Cloud backup for settings and phrases
- Widget support for quick access
- Accessibility improvements (switch control, eye tracking)

## [0.1.0] - 2025-01-04

### Added
- Initial release of Stuart Speaks AAC app
- Predictive word wheel with usage-based suggestions
- Sentence starters for quick phrase access
- Quick action buttons (Yes, No, Help, Thank You)
- Text chunking for long messages
- Audio queue management for seamless playback

#### TTS Provider Support
- **Fish.Audio** provider with voice cloning
  - MP3 and Opus format support
  - Bitrate control (128-320 kbps)
  - Temperature control (0.0-1.0)
  - Top P nucleus sampling (0.0-1.0)
  - Latency optimization (normal/balanced)
  - WebSocket streaming support (placeholder)

- **Cartesia AI** provider
  - Sonic 3 model support
  - WAV, MP3, and raw audio formats
  - Multiple encoding options (pcm_s16le, pcm_f32le, mulaw)
  - Sample rate control (8k-44.1k Hz)
  - Language support

- **ElevenLabs** provider
  - Professional voice library
  - Multiple audio formats (MP3, PCM, Opus, μ-law, A-law)
  - Voice settings (stability, similarity boost, style, speed)
  - Speaker boost option
  - Streaming latency optimization (0-4 levels)
  - Model selection (eleven_multilingual_v2, etc.)

- **Play.ht** provider with instant voice cloning
  - Multiple voice engines (PlayDialog, Play3.0-mini, Play3.0)
  - Quality presets (draft, low, medium, high, premium)
  - Format support (mp3, wav, ogg, flac, mulaw)
  - Speed control (0.5-2.0x)
  - Temperature control (0.0-2.0)
  - Sample rate control (8k-44.1k Hz)

- **Resemble.AI** provider with emotional control
  - Rapid voice cloning (10s-1min audio)
  - Emotion presets (happy, sad, angry, neutral)
  - 149+ language support
  - MP3 and WAV formats
  - Precision control (PCM_16, PCM_24, PCM_32, FLOAT)
  - Sample rate control (8k-44.1k Hz)
  - Project integration

#### Core Features
- Dynamic provider switching without losing configurations
- Secure credential storage using `flutter_secure_storage`
- Local word usage tracking with `shared_preferences`
- Audio format compatibility (MP3, WAV, OGG, AAC, FLAC, Opus, μ-law)
- Provider-specific configuration UI
- Real-time credential validation
- Error handling with user-friendly messages

#### UI/UX
- Clean, accessible interface design
- Settings screen with provider selection dropdown
- Dynamic configuration fields based on selected provider
- Context-aware help text for each provider
- Visual feedback for saved configurations
- Loading states and error displays

#### Architecture
- Abstract `TTSProvider` interface for extensibility
- Provider pattern for easy addition of new TTS services
- Service layer separation (TTS, audio playback, word tracking)
- Modular feature-based structure

#### Documentation
- Comprehensive README with setup instructions
- Audio format compatibility documentation
- Provider comparison table
- Architecture documentation
- MIT License
- Contributing guidelines

### Technical Details
- Flutter SDK 3.0.0+ support
- iOS 12.0+ / Android 5.0+ compatibility
- HTTP-based TTS generation
- Concurrent chunk generation for long text
- Sequential audio queue playback

### Dependencies
- `http: ^1.2.2` - HTTP client for API calls
- `audioplayers: ^6.1.0` - Audio playback
- `flutter_secure_storage: ^9.2.2` - Secure credential storage
- `shared_preferences: ^2.3.4` - Local data persistence

### Security
- API keys stored in device secure storage
- HTTPS-only API communication
- No local audio data retention
- Local-only word frequency tracking

---

## Version History

### Version Numbering
- **Major version** (X.0.0): Breaking changes or major new features
- **Minor version** (0.X.0): New features, backward compatible
- **Patch version** (0.0.X): Bug fixes, backward compatible

### Categories
- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security improvements

---

[Unreleased]: https://github.com/yourusername/stuart-speaks/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/stuart-speaks/releases/tag/v0.1.0
