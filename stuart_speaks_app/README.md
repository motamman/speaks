# <img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" width="48" height="48" style="vertical-align: middle;"> Speaks

A Flutter AAC (Augmentative and Alternative Communication) app with multi-provider TTS support and intelligent word prediction.

**Version:** 0.3.0+3
**Platform:** iOS 12.0+ / Android 5.0+

## About This App

**This app was built to help my dear friend Stuart communicate with his old voice after being diagnosed with ALS.** I used Fish.Audio and Cartesia AI to create models of his voice. You will need to have recordings of the person's voice you want to emulate. You don't need much. Create an account with Fish and/or Cartesia and follow their instructions. Once the model is created, you will need to plug in your API Key and Model ID into the config.

## Features

### Text-to-Speech
- **5 TTS Providers**: Fish.Audio, ElevenLabs, Cartesia AI, Play.ht, Resemble.AI
- **Streaming Audio**: ElevenLabs, Cartesia, Fish.Audio have working streaming
- **Voice Cloning**: Fish.Audio, ElevenLabs, Play.ht, Resemble.AI support custom voices
- **Text Chunking**: Automatically splits long text (>100 chars) for better audio quality
- **Audio Caching**: Caches generated audio for instant replay

### Word Prediction
- **Predictive Word Wheel**: Circular interface with 12 word suggestions
- **Usage Tracking**: Learns from your word usage (1.2x boost for words used in last 7 days)
- **Horizontal Suggestions**: 8 suggestion chips above the wheel
- **Haptic Feedback**: Vibration on word hover
- **Adaptive Sizing**: 320px-500px based on device

### Phrases
- **Quick Phrases**: default phrases + custom phrases
- **Recent Phrases**: Last 10 spoken items with cached audio
- **Action Buttons**:
  - Recent phrases: Play, Edit, Regenerate, Add to Quick Phrases, Share, Delete
  - Quick phrases: Edit, Regenerate, Share, Delete
- **Phrase Exclusion**: Hide unwanted default phrases
- **Usage Sorting**: Most-used phrases shown first

### Vocabulary Management
- **Import from Files**: Import words from .txt files with frequency analysis
- **Stop Word Filtering**: Excludes 100+ common English words
- **Manual Management**: Add/delete words, search, sort by usage
- **Auto-Tracking**: All spoken words automatically added to vocabulary

### Settings
- **User Profile**: First name, last name (app title becomes "{FirstName} Speaks")
- **TTS Provider Config**: Switch providers, configure API keys and voice settings
- **Vocabulary Dictionary**: View, search, sort all words with usage stats

### Accessibility (WCAG 2.1 AAA)
- **Touch Targets**: 48-70pt minimum (SPEAK NOW button is 70pt)
- **Long-Press Duration**: 800ms (extended for tremor users)
- **Disabled Shake-to-Undo**: Safe for ALS users
- **No Scrolling**: Text input area doesn't scroll (critical for motor impairments)
- **Landscape Support**: Full tablet landscape layout with optimized keyboard handling
- **High Contrast**: Colors meet AAA standards
- **Large Fonts**: 18-24pt default

## TTS Providers

| Provider | Streaming | Default Format |
|----------|-----------|----------------|
| Fish.Audio | ✅ Working | MP3 |
| ElevenLabs | ✅ Working | MP3 |
| Cartesia AI | ✅ Working | PCM/WAV |
| Play.ht | ❌ Not implemented | MP3 |
| Resemble.AI | ❌ Not implemented | MP3 |

### Fish.Audio
- Custom voice cloning
- HTTP streaming (WebSocket planned)
- MP3, Opus, WAV, PCM formats
- Temperature and top-p controls

### ElevenLabs
- Custom voice cloning
- HTTP streaming
- MP3 and PCM formats
- Stability, similarity boost, style controls

### Cartesia AI
- Custom voice cloning
- Low-latency Sonic model
- Server-Sent Events (SSE) streaming
- PCM and MP3 formats
- Pre-configured with defaults

## Installation

1. Clone repository:
```bash
cd stuart_speaks_app
flutter pub get
```

2. Run:
```bash
flutter run
```

## Configuration

1. Open app → Settings → User Profile
2. Enter your first name (changes app title)
3. Settings → Text-to-Speech Settings
4. Select provider and enter API credentials:
   - **Fish.Audio**: API Key + Model ID
   - **ElevenLabs**: API Key + Voice ID
   - **Cartesia AI**: API Key + Voice ID (UUID)
   - **Play.ht**: User ID + API Key + Voice Manifest URL
   - **Resemble.AI**: API Token + Voice UUID
5. Click "Save Configuration"

## Usage

1. Type message in text field (5,000 char max)
2. Tap word suggestions or word wheel to insert words
3. Tap "SPEAK NOW" to generate and play speech
4. Use Quick Phrases tab for saved phrases
5. Recent phrases automatically cached for replay

## Dependencies

```yaml
# Core
flutter_sound: ^9.16.3             # Audio playback
http: ^1.1.0                       # TTS API calls
shared_preferences: ^2.2.2         # Local storage
flutter_secure_storage: ^9.2.4     # Encrypted credentials
path_provider: ^2.1.5              # File paths
crypto: ^3.0.3                     # Encryption
provider: ^6.1.1                   # State management
share_plus: ^12.0.1                # Share audio files
file_picker: ^10.3.3               # Import vocabulary
```

## Project Structure

```
lib/
├── main.dart
├── core/
│   ├── models/                    # Data models
│   ├── providers/                 # TTS provider implementations
│   ├── services/                  # Business logic
│   └── utils/                     # Validators
├── features/
│   ├── tts/                       # Main TTS screen
│   ├── settings/                  # Settings screens
│   ├── phrases/                   # Quick phrases screen
│   └── input/word_wheel/          # Word wheel widget
└── data/                          # Data sources
```

## Known Limitations

- Play.ht streaming declared but not implemented
- Resemble.AI streaming declared but not implemented
- iOS Simulator may not play audio (works on real devices)

## License

MIT License
