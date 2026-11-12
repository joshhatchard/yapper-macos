# Yapper

Push-to-talk dictation for macOS that runs entirely on your Mac.

Hold **fn (Globe) + Shift**, speak, let go, and your words are typed into whatever text field you're focused on: Notes, Mail, Slack, a browser, or an AI chat box. Speech recognition and formatting both run on-device. Your audio and text are never uploaded.

## Features

- **Push-to-talk anywhere**: hold fn + Shift to record, release to insert. Lives in the menu bar.
- **On-device speech recognition** with Apple's `SpeechAnalyzer`. After the one-time model download, it works offline.
- **Three transcript modes**, picked from the menu:
  | Mode | What you get |
  |---|---|
  | **Default** | Exactly what you said. |
  | **AI** | A clean prompt for an AI assistant: filler words and false starts removed, grammar fixed, multiple requests turned into a numbered list. It is rewritten, never answered. |
  | **Notes** | Short bullet points that keep every fact, name and number. |
- **Works in web and Electron apps**: native text fields get text inserted directly through the Accessibility API. Browser and Electron editors, such as ChatGPT, Claude and Slack, get a paste instead, and your clipboard is restored afterwards.
- **Private by design**: Yapper only ever watches fn and Shift, never what you type. It never reads text from other apps, never types into password fields, and doesn't keep your audio or transcripts.

## Requirements

- macOS 26 or later on Apple silicon
- Xcode 26 or later to build
- For **AI** and **Notes** modes, Apple Intelligence turned on (System Settings › Apple Intelligence & Siri). Siri itself can stay off. Without Apple Intelligence these modes insert the plain transcript.

## Build and run

```sh
git clone git@github.com:joshhatchard/yapper-macos.git
cd yapper-macos
make run
```

Yapper appears as a microphone icon in the menu bar. Open it to grant permissions and download the speech model.

| Command | What it does |
|---|---|
| `make run` | Build (Debug) and launch |
| `make build` | Build only |
| `make test` | Run the test suite |
| `make lint` | Strict `swift format` lint |
| `make clean` | Remove build products |

### Code signing (keeps permissions across rebuilds)

The project builds ad-hoc signed by default, so it needs no Apple developer account. macOS ties privacy permissions to the app's signature, and an ad-hoc signature changes on every build, so you may need to grant permissions again after rebuilding. To avoid that, sign with your own Apple Development identity (a free Apple account works):

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
# then set DEVELOPMENT_TEAM to your team ID
```

`Signing.local.xcconfig` is gitignored.

## Permissions

Each permission is requested from a button in the menu. Yapper never prompts on its own.

| Permission | Why |
|---|---|
| **Microphone** | Record while fn + Shift is held. |
| **Input Monitoring** | Notice fn + Shift. The event tap is listen-only and only sees modifier-key changes. |
| **Accessibility** | Insert text into the focused field, or send ⌘V for the paste fallback. |

If a permission looks granted in System Settings but Yapper still shows it as off, quit and reopen Yapper. If that doesn't fix it, reset the permission and grant it again:

```sh
tccutil reset Accessibility com.joshhatchard.Yapper
tccutil reset ListenEvent com.joshhatchard.Yapper   # Input Monitoring
```

## How it works

```
fn + Shift ─▶ Shortcut ─▶ DictationCoordinator ─▶ AudioCapture ─▶ SpeechTranscription
                                  │                                        │
                                  ▼                                        ▼
                            TextInsertion ◀──────────────────────── Formatting (AI / Notes)
                     (AX insert, or paste fallback)            (on-device Foundation Models)
```

- **Shortcut**: listen-only `CGEventTap` on `flagsChanged`, turned into a press/release gesture.
- **AudioCapture**: `AVAudioEngine` records to a temporary file, which is deleted after each dictation.
- **SpeechTranscription**: `SpeechAnalyzer` / `SpeechTranscriber` running on-device.
- **Formatting**: Apple's on-device language model rewrites the transcript, with a 10 s time limit and an output cap. A check that the output reuses your words catches cases where the model answered instead of rewriting. Whenever formatting can't be trusted, the plain transcript is inserted.
- **TextInsertion**: sets `kAXSelectedText` on the focused element. For web and Electron content, or fields that refuse it, Yapper pastes with ⌘V and restores your clipboard. The pasted text is marked transient so clipboard managers skip it.
- **AppShell / StatusUI**: SwiftUI `MenuBarExtra`.

Every platform API sits behind a small protocol, so the coordinator and adapters are unit-tested with fakes and no hardware or permissions are needed. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions, limitations and the manual test checklist.

## Known limitations

- The shortcut is fixed to fn + Shift.
- The paste fallback sends the ⌘V key code for QWERTY. Layouts that move V, such as Dvorak, may not paste.
- AI and Notes output quality depends on Apple's on-device model. Very long dictations exceed its context window and are inserted unformatted.
- If you dictate with nothing editable focused, Yapper may still send ⌘V and report "Inserted".

## License

[MIT](LICENSE)
