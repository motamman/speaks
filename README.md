# <img src="stuart_speaks_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" width="48" height="48" style="vertical-align: middle;"> Speaks

AAC (Augmentative and Alternative Communication) app designed for individuals with speech difficulties, particularly ALS patients with motor impairments.

**Version:** 0.2.0+4
**Platforms:** iOS 12.0+ / Android 5.0+

---

## About This App

**This app was built to help my dear friend Stuart communicate with his old voice after being diagnosed with ALS.** I used Fish.Audio and Cartesia AI to create models of his voice. You will need to have recordings of the person's voice you want to emulate. You don't need much. Create an account with Fish and/or Cartesia and follow their instructions. Once the model is created, you will need to plug in your API Key and Model ID into the config.

---

## Overview

Speaks provides AI-powered text-to-speech with intelligent word prediction and accessibility features designed for motor impairments. Built for Stuart and the AAC community.

**Key Features:**
- 5 TTS providers with streaming audio
- Predictive word wheel with usage learning
- Quick phrases with audio caching
- Vocabulary management with file import
- WCAG 2.1 AAA accessibility compliance

---

## Features

### Text-to-Speech

**5 Providers:**
- Fish.Audio (streaming, voice cloning)
- ElevenLabs (streaming, voice cloning)
- Cartesia AI (streaming, low latency)
- Play.ht (voice cloning, streaming not implemented)
- Resemble.AI (voice cloning, streaming not implemented)

**Audio:**
- Text chunking for long messages (>100 chars)
- Concurrent generation, sequential playback
- Audio caching for instant replay
- Formats: MP3, WAV, PCM, Opus, OGG, FLAC

### Word Prediction

**Predictive Word Wheel:**
- Circular interface with 12 suggestions
- Two rings: inner (most frequent), outer (alternatives)
- Usage scoring with recency multiplier (1.2x for last 7 days)
- Haptic feedback on hover
- Adaptive sizing: 320-500px

**Word Suggestions:**
- 8 horizontal chips above wheel
- Prefix matching on current input
- Sorted by usage score

### Phrases

**Quick Phrases:**
- 24 default phrases + custom phrases
- Grid layout with usage badges
- Action buttons: Edit, Regenerate, Share, Delete
- Phrase exclusion system (hide defaults)
- Audio caching

**Recent Phrases:**
- Last 10 spoken items
- Cached audio for replay
- Action buttons: Play, Edit, Regenerate, Add to Quick Phrases, Share, Delete
- Timestamps ("Just now", "5m ago")

### Vocabulary

**Management:**
- Import from .txt files with frequency analysis
- Stop word filtering (100+ common words excluded)
- Manual add/delete
- Search and sort by usage
- Auto-tracking of all spoken words

**Core Vocabulary:**
- Pre-loaded with 50+ high-frequency AAC words

### Settings

**User Profile:**
- First name, last name
- Dynamic app title ("{FirstName} Speaks")

**TTS Configuration:**
- Provider selection
- API credentials (encrypted storage)
- Voice settings per provider
- Credential validation

**Vocabulary Dictionary:**
- View all words with usage stats
- Search and sort
- Delete words

### Accessibility (WCAG 2.1 AAA)

**Touch Targets:**
- SPEAK NOW button: 70pt height
- All buttons: 48-56pt minimum
- 12-16pt spacing between elements

**Motor Impairment Support:**
- Long-press duration: 800ms (tremor-safe)
- Disabled shake-to-undo
- Confirmation dialogs for destructive actions
- No scrolling in text input area
- Full landscape support for tablets
- Haptic feedback

**Visual:**
- High contrast colors (AAA compliant)
- Large fonts (18-24pt default)
- Text cursor at top-left

---

## TTS Providers

| Provider | Streaming | Format |
|----------|-----------|--------|
| Fish.Audio | ✅ Working | MP3 |
| ElevenLabs | ✅ Working | MP3 |
| Cartesia AI | ✅ Working | PCM |
| Play.ht | ❌ Not implemented | MP3 |
| Resemble.AI | ❌ Not implemented | MP3 |

### Fish.Audio
- Custom voice cloning
- HTTP streaming
- Supports: MP3, Opus, WAV, PCM
- Controls: temperature, top-p, latency

**Setup:**
1. Sign up at [fish.audio](https://fish.audio)
2. Create voice model
3. Get API key and model ID

### ElevenLabs
- Custom voice cloning
- HTTP streaming endpoint
- Supports: MP3, PCM
- Controls: stability, similarity boost, style, speaker boost

**Setup:**
1. Sign up at [elevenlabs.io](https://elevenlabs.io)
2. Get API key
3. Browse voice library
4. Copy voice ID

### Cartesia AI
- Custom voice cloning
- Low-latency Sonic model
- Server-Sent Events (SSE) streaming
- Supports: PCM, MP3, WAV
- Pre-configured with default credentials

**Setup:**
1. Sign up at [cartesia.ai](https://cartesia.ai)
2. Get API key
3. Browse voices
4. Copy voice ID (UUID)

### Play.ht
- Instant voice cloning (30s audio)
- Streaming NOT YET IMPLEMENTED
- Supports: MP3, WAV, OGG, FLAC
- Controls: quality, speed, temperature

**Setup:**
1. Sign up at [play.ht](https://play.ht)
2. Get user ID and API key
3. Clone voice or use pre-built
4. Copy voice manifest URL

### Resemble.AI
- Voice cloning (10s-1min audio)
- Streaming NOT YET IMPLEMENTED
- Supports: MP3, WAV
- Controls: emotion (planned)

**Setup:**
1. Sign up at [resemble.ai](https://resemble.ai)
2. Get API token
3. Clone voice
4. Copy voice UUID

---

## Installation

```bash
git clone https://github.com/yourusername/stuart-speaks.git
cd stuart-speaks/stuart_speaks_app
flutter pub get
flutter run
```

**Requirements:**
- Flutter 3.9.2+
- Dart 3.9.2+
- iOS 12.0+ / Android 5.0+

---

## Configuration

1. **User Profile:**
   - Settings → User Profile
   - Enter first name (changes app title)

2. **TTS Provider:**
   - Settings → Text-to-Speech Settings
   - Select provider
   - Enter API credentials
   - Click "Save Configuration"

3. **Vocabulary (Optional):**
   - Settings → Import Vocabulary
   - Select .txt file
   - Review top words
   - Import

---

## Usage

1. Type message (5,000 char max)
2. Tap word wheel or suggestion chips to insert words
3. Tap "SPEAK NOW" (70pt button)
4. Audio plays immediately
5. Recent phrases cached for replay
6. Use Quick Phrases tab for saved phrases

---

## Architecture

```
lib/
├── main.dart
├── core/
│   ├── models/           # TTSRequest, Word, Phrase, Voice
│   ├── providers/        # 5 TTS provider implementations
│   ├── services/         # Audio, word tracking, text chunking
│   └── utils/            # Input validation
├── features/
│   ├── tts/             # Main screen with word wheel
│   ├── settings/        # User profile, TTS config, vocabulary
│   ├── phrases/         # Quick phrases grid
│   └── input/word_wheel/ # Circular prediction UI
└── assets/
    ├── stuart.png       # App icon
    └── default_phrases.json
```

**Patterns:**
- Provider pattern for TTS backends
- Singleton services
- State management with Provider package
- Encrypted credential storage (FlutterSecureStorage)

---

## Dependencies

```yaml
flutter_sound: ^9.16.3             # Audio playback
http: ^1.1.0                       # TTS API calls
shared_preferences: ^2.2.2         # Local storage
flutter_secure_storage: ^9.2.4     # Encrypted credentials
path_provider: ^2.1.5              # File paths
crypto: ^3.0.3                     # Encryption
provider: ^6.1.1                   # State management
share_plus: ^12.0.1                # Share audio
file_picker: ^10.3.3               # Import vocabulary
```

---

## Known Limitations

- Play.ht streaming declared but not implemented
- Resemble.AI streaming declared but not implemented
- iOS Simulator may not play audio (works on real devices)

---

## Roadmap

**Completed:**
- [x] Multi-provider TTS (5 providers)
- [x] Streaming audio (3 providers working)
- [x] Word wheel v2
- [x] User profile with dynamic title
- [x] Vocabulary import from files
- [x] Phrase exclusion system
- [x] Audio caching
- [x] Text chunking
- [x] Accessibility (WCAG AAA)

**Planned:**
- [ ] WebSocket streaming for Fish.Audio
- [ ] Complete Play.ht streaming
- [ ] Complete Resemble.AI streaming
- [ ] Offline TTS (Coqui TTS)
- [ ] Voice recording for cloning
- [ ] Multi-language UI
- [ ] Dark mode
- [ ] Cloud backup (optional)

---

## Contributing

Contributions welcome. This app was built for the AAC community.

**Guidelines:**
- Maintain WCAG 2.1 AAA compliance
- Add tests for new features
- Update documentation
- Follow Dart style guide

---

## License

MIT License

---

## Acknowledgments

Built for Stuart and the AAC community. Powered by Fish.Audio, ElevenLabs, Cartesia, Play.ht, and Resemble.AI.

**Contact:** maurice@zennora.sv

---

**Made for accessible communication.**
