#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="${LOCALVOICE_APP_PATH:-$HOME/Applications/Local Voice.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
mkdir -p "$APP/Contents/Resources/Xlit" "$APP/Contents/Resources/ASR"
mkdir -p "$APP/Contents/Resources/Licenses/Handy" "$APP/Contents/Resources/Licenses/OpenWhispr"
cp ThirdParty/Handy/LICENSE "$APP/Contents/Resources/Licenses/Handy/"
cp ThirdParty/OpenWhispr/LICENSE "$APP/Contents/Resources/Licenses/OpenWhispr/"
cp upstream-workflow-review.md "$APP/Contents/Resources/Licenses/"
cp Assets/LocalVoice.icns "$APP/Contents/Resources/LocalVoice.icns"
cp training/adapter.py training/train.py "$APP/Contents/Resources/ASR/"
cp asr/server.py "$APP/Contents/Resources/ASR/"
rm -rf "$APP/Contents/Resources/Xlit/__pycache__"
cp xlit/*.py xlit/lang_list.txt xlit/LICENSE "$APP/Contents/Resources/Xlit/"
cp Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
cp Fonts/*OFL.txt "$APP/Contents/Resources/Fonts/"
SWIFT_RELEASE_FLAGS=()
if [[ "${LOCALVOICE_RELEASE:-0}" == 1 ]]; then
  SWIFT_RELEASE_FLAGS=(-target arm64-apple-macos26.2 -D LOCALVOICE_RELEASE)
fi
swiftc "${SWIFT_RELEASE_FLAGS[@]}" AppResources.swift -O -parse-as-library LocalVoice.swift Learning.swift LearningCore.swift InsightsCore.swift InsightsView.swift VoiceCore.swift Hinglish.swift HomeSpeechServer.swift SpeechEngine.swift ProcessingJob.swift TranscriptionPolicy.swift AudioRecording.swift SpeechTranscription.swift LiveTranscription.swift Interface.swift -o "$APP/Contents/MacOS/LocalVoice" -framework SwiftUI -framework AppKit -framework AVFoundation -framework ApplicationServices
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalVoice</string>
<key>CFBundleIdentifier</key><string>dev.parth.localvoice</string>
<key>CFBundleIconFile</key><string>LocalVoice</string>
<key>CFBundleName</key><string>Local Voice</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSMicrophoneUsageDescription</key><string>Record dictation and process it on this Mac or your private HP home server, according to Settings.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# An explicit local development identity keeps updates from being identified only by a changing code hash.
codesign --force --sign - --identifier dev.parth.localvoice --requirements '=designated => identifier "dev.parth.localvoice"' "$APP"
print "Built $APP"
