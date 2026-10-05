# What's New in 0.3.5

## Hardware keyboard mode
- New **Keyboard mode** setting (Settings → Input Method):
  - **Type only** (default): built for a hardware keyboard. F1–F12 pick the matching suggested word, Enter speaks, and the word wheel is hidden so recent phrases get more room.
  - **Type and touch**: the on-screen word wheel and scrolling suggestions, as before. Enter still speaks.
- Enter now speaks the text instead of adding a new line, whether it comes from a hardware keyboard or the on-screen one.
- iOS's double-space shortcut no longer inserts a stray period.
- Picking a word keeps the keyboard active, so you can keep typing straight away.
- The on-screen keyboard show/hide button has been removed.
- Error messages now appear just above SPEAK NOW, so the on-screen keyboard can't hide them. They stay until you edit your text, try again, or tap ✕.

## Phrase repair
- Fixes Quick Phrases that a sync bug had turned into garbled text like `{id: ..., text: ...}`. They're repaired automatically on the first launch, on the device and on the server.
- Duplicate phrases are merged and their usage counts combined. Cached audio is kept.

## Under the hood
- Encrypted settings storage updated. Saved API keys and settings are migrated automatically.
- Dependency updates. iOS 15.0 or later is now required.

## Please test
- After updating, check that your TTS provider and API keys are still set up and that speech works.
- Check that your Quick Phrases look right and nothing is missing.
- With a hardware keyboard: try F1–F12, Enter to speak, and switching between the two keyboard modes.
