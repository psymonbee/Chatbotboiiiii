# Chatbot

A private DeepSeek chat app for iPhone, iPad and Mac. One SwiftUI app, dark UI, history synced through your own iCloud and encrypted with a key that only your devices hold.

## What it does

- **Your API key, your models.** Paste a DeepSeek API key once; it's stored in iCloud Keychain and appears on your other devices. The model list comes live from DeepSeek's `/models` endpoint, so new models show up without an app update.
- **Every setting the API has:** model, thinking on/off, reasoning effort (low / high / max), temperature, top P, max tokens, JSON output and stop sequences. Settings that do nothing in the current mode are greyed out (temperature while thinking).
- **System prompts as personas.** A persona is a system prompt plus settings. New chats copy one, and you can change the prompt or settings for a single chat from its ⋯ menu.
- **Attachments.** Images (JPEG/PNG/GIF/WebP; photos are converted from HEIC) go to the model as images. PDFs, text, code, CSV, JSON and RTF are converted to text on the device, which works with every model. If a model rejects images, the app remembers and greys out the photo button for that model.
- **Thinking**: the model's reasoning streams into a collapsible "Thought for 12s" section.
- **Voice mode.** Talk to it: on-device speech recognition where supported, it sends when you pause, then reads the reply aloud. The speaker button on any reply reads it too.
- **Incognito chats** that are never saved anywhere.
- **Clean slate.** Every request contains only the current chat's system prompt and messages. Nothing else is sent.

## Privacy model

| What | Where it lives | Who can read it |
|---|---|---|
| Chats, prompts, files, titles | SwiftData → your private CloudKit database | Only your devices. Each record is AES-GCM encrypted before it's saved, so CloudKit holds ciphertext. |
| History encryption key | iCloud Keychain (synchronizable item) | Only your devices. iCloud Keychain is end-to-end encrypted even without Advanced Data Protection. |
| DeepSeek API key | iCloud Keychain | Only your devices, and DeepSeek. |
| A chat you're using | Sent to `api.deepseek.com` | DeepSeek |

No server, no login, no web front-end. Settings → Privacy shows a short **history key ID**; it should match on every device.

If you lose iCloud Keychain, the history can't be decrypted. That's the trade-off for Apple only ever holding ciphertext.

## Setup (once)

You need a Mac with **Xcode 27** and a paid **Apple Developer Program** membership (CloudKit doesn't work with a free account).

1. Install XcodeGen: `brew install xcodegen`
2. Create your signing config:
   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
   Set `DEVELOPMENT_TEAM` to your team ID (developer.apple.com → Account → Membership) and `BUNDLE_ID_PREFIX` to something unique to you, like `com.yourname`.
3. Generate and open the project:
   ```sh
   xcodegen
   open Chatbot.xcodeproj
   ```
4. In Xcode, select the **Chatbot** target → **Signing & Capabilities**. Under iCloud, if the container `iCloud.<your prefix>.chatbot` shows in red, click the refresh button (or **+**) so Xcode creates it in your developer account.
5. Choose your iPhone or "My Mac" as the run destination and press Run.

Re-run `xcodegen` whenever files are added or removed. The `.xcodeproj` is generated, so it isn't committed.

On each device, make sure **iCloud Keychain** is on (Settings → your name → iCloud → Passwords & Keychain) and that you're signed in with the same Apple Account.

### First launch

- **First device:** choose *Set up on this device*. This creates the encryption key and three starter personas. Then paste your API key.
- **Every other device:** choose *I already use it on another device*. The app waits for the key to arrive through iCloud Keychain (usually under a minute), then your history appears.

Only create the key once. If two devices each create one, each can't read the other's history.

## What DeepSeek accepts (October 2026)

- Images: JPEG, PNG, GIF and WebP, on models that support vision (`deepseek-flash` does; `deepseek-v4-pro` reportedly doesn't).
- No audio or video input. Voice mode transcribes on the device and sends text.
- Documents are read on the device and sent as text. Scanned PDFs with no text layer aren't supported yet.

## Project layout

```
project.yml          XcodeGen spec (one multiplatform target: iOS + macOS)
Config/              xcconfigs, entitlements, Info.plist additions
ChatCore/            Swift package: DeepSeek wire format, request building,
                     stream parsing, Markdown parsing. No Apple-only APIs.
Chatbot/
  App/               App entry, root view, onboarding routing
  Data/              SwiftData records (ciphertext only) and payload types
  Security/          Keychain + Vault (key management, AES-GCM sealing)
  Services/          DeepSeek client, model catalog, attachments, speech
  Chat/              ChatSession (one open chat) and SessionStore
  UI/                Home, chat, voice mode, settings, onboarding
```

### Tests

```sh
cd ChatCore && swift test
```

These cover request building (thinking vs. non-thinking parameters, images, documents, JSON mode, role merging), stream parsing (reasoning and content deltas, usage, keep-alives, mid-stream errors) and Markdown parsing. They run on macOS or Linux.

### Before TestFlight or the App Store

CloudKit has separate development and production environments. Before shipping a build that isn't run from Xcode, open the CloudKit Console and **deploy the schema to production**. After that, changes to the SwiftData models must only add fields.
