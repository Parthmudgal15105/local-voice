#!/bin/zsh
#
# setup.sh - Initial setup script for 'Local Voice'
#
# PREREQUISITES:
# 1. Hardware & OS:
#    - Apple Silicon Mac (M1/M2/M3/M4)
#    - macOS 14.0 (Sonoma) or newer
#
# 2. System Developer Tools:
#    - Xcode Command Line Tools (provides swiftc, codesign):
#      Run: xcode-select --install
#
# 3. Package Managers & Runtimes:
#    - Homebrew: https://brew.sh
#      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#    - whisper-cpp (installed automatically via brew if not present, providing whisper-cli and whisper-server)
#    - uv (fast Python package and project manager, required by setup-hinglish.sh and setup-asr.sh):
#      curl -LsSf https://astral.sh/uv/install.sh | sh
#      (or `brew install uv`)
#    - Python: Python 3.10 and 3.11 virtual environments managed automatically via uv
#
# 4. Storage & Network:
#    - Active internet connection for initial model downloads:
#      * Whisper Large-v3 model (~3.1 GB, SHA-256 verified)
#      * Silero VAD v6.2.0 model (~5 MB)
#      * IndicXlit transliteration model (~120 MB, SHA-256 verified)
#      * Python virtual environment dependencies
#    - ~5-6 GB free disk space in ~/Library/Application Support/Local Voice
#
# 5. System Permissions (prompted on first launch):
#    - Microphone: for recording speech
#    - Accessibility / Device Control: for global Fn key listener & text insertion
#
set -euo pipefail
cd "${0:A:h}"
command -v brew >/dev/null || { print 'Install Homebrew from https://brew.sh first.'; exit 1; }
WHISPER_CLI=$(command -v whisper-cli || echo /opt/homebrew/bin/whisper-cli)
if [[ ! -x "$WHISPER_CLI" && -x /usr/local/bin/whisper-cli ]]; then
  WHISPER_CLI=/usr/local/bin/whisper-cli
fi
if [[ ! -x "$WHISPER_CLI" ]]; then
  brew install whisper-cpp
fi
DATA="$HOME/Library/Application Support/Local Voice"
mkdir -p "$DATA"
chmod 700 "$DATA"
MODEL="$DATA/ggml-large-v3.bin"
EXPECTED=64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2
if [[ ! -f "$MODEL" ]]; then
  curl -fL --retry 3 -C - https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin -o "$MODEL.download"
  ACTUAL=$(shasum -a 256 "$MODEL.download" | cut -d ' ' -f 1)
  [[ "$ACTUAL" == "$EXPECTED" ]] || { print 'Model checksum mismatch. Remove the .download file and retry.'; exit 1; }
  mv "$MODEL.download" "$MODEL"
fi
if [[ ! -f "$DATA/ggml-silero-v6.2.0.bin" ]]; then
  curl -fL --retry 3 https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin -o "$DATA/vad.download"
  mv "$DATA/vad.download" "$DATA/ggml-silero-v6.2.0.bin"
fi
./setup-hinglish.sh
./build.sh
open "$HOME/Applications/Local Voice.app"
