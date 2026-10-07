# Adder

Adder is a native iPhone app that turns voice, photos, and typed text into useful items with capture context. It uses Zetic Melange and Liquid AI for local interpretation, with a review step before saving.

## Current features

- Record up to 30 seconds and transcribe locally with Zetic Whisper Tiny.
- Interpret typed or transcribed requests with `zetic/LFM2.5-1.2B-Instruct` (version 1).
- Understand photos with `zetic/LFM2.5-VL-450M` (version 1), combine its descriptions with supporting Apple Vision OCR, then extract structured actions with Liquid 1.2B-Instruct.
- Create contacts with normalized phone numbers, explicitly spelled emails, meeting notes, capture timestamps, and the first attached photo.
- Create Calendar events and separate preparation tasks in Reminders.
- Route explicit meeting requests to a Calendar preview. Image text and standalone note requests open a fresh note preview for sharing directly to Apple Notes; no local-note history is shown.
- Attach real capture coordinates when location permission and a recent fix are available. Capture coordinates are distinct from a meeting venue.

All proposals are editable. Nothing is added to Apple Contacts, Calendar, or Reminders before the user presses Save. Those apps may sync saved items through the user's configured accounts.

The vision pipeline describes photos sequentially and labels its output as model interpretation. Liquid 1.2B-Instruct, Whisper encoder/decoder, and Liquid vision all initialize at app startup. Vision remains ready for photo previews; downloaded artifacts use the SDK KEEP_EXISTING policy. Physical-device vision inference is not yet verified. Standalone notes are sent through the native share sheet: choose Notes and save the new note; no local-note history is shown. The contact's first photo is saved as its picture.

## Run on an iPhone

1. Open `Adder.xcodeproj` in Xcode.
2. Connect and unlock an iPhone. Enable **Settings → Privacy & Security → Developer Mode**, restart, and confirm the setting.
3. Sign into **Xcode → Settings → Accounts**, then choose your team under **Adder → Signing & Capabilities**.
4. Build and run on the physical phone.
5. On your Mac, create a development [Melange Personal Access Token](https://melange.zetic.ai/settings?tab=pat). Run `python3 scripts/configure-local-key.py` and paste the token into the hidden Mac dialog.
6. Rebuild and install. The private build script embeds the ignored `.secrets/MelangeConfig.plist` configuration before signing. The app loads models automatically; keep internet on for the first downloads. No token entry is required on the phone. Do not put credentials in tracked source files or issues.
7. Test a first response, then disable Wi-Fi and cellular and verify offline operation.

The Melange SDK requires a physical device. Simulator execution does not establish that inference works.

The package is pinned to **ZeticMLange iOS 1.11.0** and links Accelerate. Models are downloaded at runtime; their access, billing, and licenses remain governed by their providers. No model weights or SDK binaries are included in this repository.

Embedding a PAT is intended only for private development builds. An embedded credential can be extracted from a distributed application; public deployment needs a provider-supported app credential or provisioning design.

`project.yml` is the XcodeGen source. To regenerate, run `xcodegen generate`; preserve any local signing-team setting when regenerating.

## Try the sample flows

The Contact and Event sample buttons insert text into the capture box. They still run through Liquid and require review.

For contact capture, dictate a person's name, country and phone number, spell their email, and explain where you met. Explicit spelling overrides the inferred email without changing the person's name. A national Australian mobile number is converted to `+61` when Australia is provided.

For a follow-up event, ask for a catch-up with a recently saved person, specify the place and time, and request preparation the day before. Choose the event duration in the preview. “Next Wednesday” uses the following Monday-based calendar week; the exact resolved date is displayed before saving. The reminder uses the meeting's local clock time on the earlier day.

For a business card or event poster, attach photos, inspect and correct the recognized photo text, and request a contact or Calendar event. For a text-only image, Preview opens a new note; choose Share to Apple Notes, then Notes and Save. URL-list actions remain deferred.

## Validation and limits

The signed arm64 app builds against SDK 1.11.0 and has been installed and launched on the physical iPhone. The user confirmed model startup completed and contact creation worked. Previously downloaded GGUF artifacts survived redeployment at the same paths and sizes. Deterministic extraction, response-parser, generation-watchdog, and Whisper preprocessing checks passed. Transcription quality and latency, contact Notes contents, vision extraction quality, event/reminder saves, camera/location permissions, and offline execution still need device verification.

Run the pure extraction checks on macOS:

```sh
Tests/run-extraction-checks.sh
python3 Tests/test_build_credentials.py
```

These checks use the actual field/date rules without requesting permissions or touching Contacts, Calendar, or Reminders. They cover spelling precedence, Australian phone normalization, relative dates, timezones, DST, and invalid dates.

For a compile-only check when Xcode run destinations are unavailable:

```sh
xcodebuild -project Adder.xcodeproj -target Adder -sdk iphoneos \
  -configuration Debug CODE_SIGNING_ALLOWED=NO SYMROOT=build/Products build
```

This produces an unsigned app and cannot install it on a regular iPhone.

Whisper input is capped at 30 seconds and decoding at 160 tokens; incomplete or repeated output reports an error. Combined text, OCR, and visual descriptions are limited to 16,000 characters; larger captures report an error and retain the input for splitting instead of silently dropping evidence. Check names, phone numbers, URLs, and dates before saving.

This prototype was built for the October 6, 2026 Liquid AI × Zetic workshop. The workshop's approved SDK and model list are event-specific.

## License and acknowledgments

Adder's original code is [MIT licensed](LICENSE). Whisper preprocessing and bundled vocabulary/filterbank resources retain their applicable upstream licenses. See [third-party notices](App/Whisper/NOTICE.txt), the [Zetic samples license](App/Whisper/ZeticSamples-LICENSE), and [OpenAI Whisper license](App/Whisper/OpenAI-Whisper-LICENSE).

References: [Zetic iOS SDK](https://github.com/zetic-ai/ZeticMLangeiOS), [Zetic Whisper tutorial](https://docs.zetic.ai/tutorials/speech-recognition-whisper), [Liquid AI models](https://www.liquid.ai/models).
