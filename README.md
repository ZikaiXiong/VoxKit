# VoxNote 声记

A macOS menu-bar speech-to-text app: quick dictation + meeting transcription, multiple
transcription models, AI proofreading, and a lexicon that learns your corrections.
Interface in English and 中文. By [Zikai Xiong](https://zikaixiong.github.io).

## Features

- **Lives in the menu bar** — closing the main window tucks it into the top-right corner;
  a global hotkey (default `⌥ Space`) starts dictation from anywhere
- **Two modes**
  - *Quick Dictation*: a lightweight floating bar (like an input method); the result is
    copied to your clipboard the moment you stop, with optional auto-paste
  - *Meeting*: long-form recording with pause/resume; transcribes in the background and
    presents the result with timestamps
- **Multiple engines**: Apple on-device recognition (free/offline), OpenAI, Groq,
  SiliconFlow, AssemblyAI, or any OpenAI-compatible endpoint — Chinese and English alike
- **Speaker diarization**: choose AssemblyAI for meetings and get a transcript split by
  speaker (`[02:15] Speaker A: …`); hours-long audio is handled natively without chunking
- **Text-to-speech**: a dedicated Speak page turns text into audio — system voices
  (free/offline), OpenAI / Groq / SiliconFlow TTS models, with voice & speed options;
  generated audio is auto-saved and can optionally play right away
- **Microphone picker**: choose your input source right on the record page; newly
  plugged-in mics appear automatically, unplugged ones fall back to the system default
- **Drag & drop import**: drop audio files (wav/mp3/m4a/aac/flac/aiff/caf) onto the
  window — they're converted automatically and ready to transcribe with any model
- **Keys in the Keychain**: API keys are stored in the macOS Keychain, never in plain text
- **Long-audio auto-chunking**: recordings beyond a model's limits are split at quiet
  points, transcribed chunk by chunk, and merged back with timestamps
- **Recordings are never wasted**: everything is kept in a local library; re-run any
  recording through a different model and compare versions side by side
- **Two-layer correction system**
  1. *Pair learning* — edit a transcript, hit "Save & Learn", and a fix seen twice becomes
     a rule: future transcripts get auto-corrected, with one-click suggestions (the
     original text is always preserved)
  2. *AI proofreading* — mis-recognitions vary wildly but the right words are stable, so
     VoxNote can hand the transcript *plus your glossary* (hotwords + known corrections)
     to a language model for context-aware proofreading: Apple Intelligence on-device
     (macOS 26+, free) or any OpenAI-compatible chat model; run it automatically after
     every transcription or manually per session
- **Hotword injection**: your glossary is passed as a prompt to transcription models that
  support it, so proper nouns come out right at the source

## Install (free path, no Apple Developer account)

1. Download `VoxNote-x.y.z.zip` from [Releases](../../releases) and unzip it
2. Drag `VoxNote.app` into your **Applications** folder
3. First launch — the app is not notarized, so macOS will block the first double-click:
   - **macOS 15 (Sequoia) and later**: double-click once (it gets blocked), then open
     **System Settings → Privacy & Security**, scroll down and click **"Open Anyway"**
   - **macOS 14 and earlier**: right-click the app → **Open** → **Open**
   - Or clear the quarantine flag in Terminal instead:
     ```bash
     xattr -cr /Applications/VoxNote.app
     ```
4. Grant **Microphone** and **Speech Recognition** permissions when prompted
5. Optional: add API keys under *Settings → API Keys* for cloud models; on-device
   recognition works out of the box with no key

## Build from source

```bash
git clone <this repo>
cd VoxNote
./build.sh          # compile + package dist/VoxNote.app
./build.sh --zip    # also produce a distributable zip
open dist/VoxNote.app
```

Only Xcode Command Line Tools are required (the build uses `swiftc` directly — no
full Xcode, no SwiftPM). See [DISTRIBUTION.md](DISTRIBUTION.md) for signing,
notarization, and shipping to other people.

## Service limits (chunk length is adjustable in Settings)

| Service | Models | Max upload | Default chunk |
|---|---|---|---|
| Apple on-device | system recognizer | — | 10 min offline / 55 s server |
| OpenAI | gpt-4o(-mini)-transcribe, whisper-1 | 25 MB | 10 min |
| Groq | whisper-large-v3(-turbo) | 25 MB | 10 min |
| SiliconFlow | SenseVoiceSmall | 25 MB | 5 min |
| AssemblyAI | universal-3-pro (+ diarization) | ~2 GB | no chunking needed |

Recordings are stored as 16 kHz mono WAV (~1.9 MB/min), so a 10-minute chunk stays
far below the 25 MB caps.

## Data location

`~/Library/Application Support/VoxNote/` — `sessions.json` (history), `lexicon.json`
(learned corrections & hotwords), `Audio/` (recordings), `Speech/` (generated TTS audio).

## Requirements

- macOS 13+ (Apple Silicon build; see DISTRIBUTION.md for universal binaries)
- "AI Correction → Apple Intelligence" needs macOS 26+ with Apple Intelligence enabled;
  everything else works without it

## Roadmap

- System-audio capture (the other side of a meeting) — currently records the microphone
- Speaker identification (mapping Speaker A/B to real names) and automatic summaries
- Silence auto-stop (VAD)

## License

[MIT](LICENSE) © 2026 Zikai Xiong
