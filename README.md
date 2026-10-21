# Local Voice

A personal native Mac dictation app for English, Hindi and Hinglish. This is a source distribution, independent of OpenAI and Wispr. It is experimental, ad-hoc signed and not notarized; there is no Apple-trusted public binary release here.

## Requirements

Apple Silicon Mac, macOS 14 or later for the Swift app, Xcode Command Line Tools, Homebrew, Git, and uv. The optional MLX/Qwen engine has additional OS/runtime requirements: current bundled MLX wheels require macOS 26.2 or later. Use Whisper where compatible. Initial installation downloads several GB of model files and needs internet and sufficient free disk space. Recognition accuracy and hardware latency vary.

## Install from source

Install Xcode Command Line Tools (`xcode-select --install`), Homebrew (https://brew.sh), and uv (https://docs.astral.sh/uv/getting-started/installation/), then:

```sh
git clone https://github.com/Parthmudgal15105/local-voice.git
cd local-voice
./setup.sh
```

Setup installs whisper.cpp if needed, downloads and checks the Whisper Large-v3 model, installs Silero VAD and IndicXlit, and builds/opens `~/Applications/Local Voice.app`. No account or API key is required for local recognition. Setup installs dependencies on your Mac; inspect scripts first. Rebuild later with `./build.sh` and reopen the app.

Optional Qwen setup: `./setup-asr.sh`, then select an installed compatible model in app Settings. These optional model downloads are large. Do not select a model until its setup has completed.

## Permissions and use

In app Settings, request Microphone and Accessibility/Device Control permission. Reconnect the shortcut after granting access. Disable conflicting Fn bindings, and set the macOS Globe-key action to Do Nothing.

Tap Fn to start and tap again to finish; hold Fn to record and release to process; Escape cancels. The app also has Try dictation/Finish controls. Choose English translation or Hinglish as spoken in Settings. Use Scratchpad to review and edit text before Copy all. Dictionary and snippets customize spelling and expansions. Review output before using it: recognition and transliteration can make errors, especially with names.

## Privacy and limitations

Choose local Mac processing for an entirely local inference workflow after setup. Private-server mode is disabled in this public source distribution; personal endpoint configuration is never loaded.

Preferences, vocabulary, snippets, scratchpad, optional transcript history and recovery recordings may persist in `~/Library/Application Support/Local Voice`. Do not share that folder. Check history and personal-learning settings before recording sensitive speech. Cancellation and technical-failure recovery are supported, but natural-speech and fresh-machine acceptance testing remain necessary. There is no cloud sync or guaranteed accuracy. Intel Macs and transferred prebuilt app bundles are not supported by these instructions.

## Attribution

Speech uses whisper.cpp/Whisper and optional MLX/Qwen. Hinglish transliteration uses AI4Bharat IndicXlit; its license is in xlit/LICENSE. Figtree and EB Garamond fonts retain their OFL notices. Selected reliability patterns were adapted from Handy and OpenWhispr; full MIT notices are retained under ThirdParty, with details in upstream-workflow-review.md. Interface layout was informed by studying Wispr Flow; no Wispr marketing assets are bundled.
