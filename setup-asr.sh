#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
DATA="$HOME/Library/Application Support/Local Voice"
UV=$(command -v uv || print "$HOME/.local/bin/uv")
[[ -x "$UV" ]] || { print 'Install uv from https://docs.astral.sh/uv/ first.'; exit 1; }
[[ -x "$DATA/asr-env/bin/python" ]] || "$UV" venv --python 3.11 "$DATA/asr-env"
"$UV" pip install --python "$DATA/asr-env/bin/python" -r asr/requirements.lock
python3 benchmarks/download.py
for ITEM in 'Qwen3-ASR-0.6B-8bit:b5bfe4abc1b4c6e58b633096682ec2b6297298add1527119936107d211adf0e8' 'Qwen3-ASR-1.7B-8bit:bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c'; do
 NAME=${ITEM%%:*}; EXPECTED=${ITEM#*:}
 ACTUAL=$(shasum -a 256 "$DATA/asr-models/$NAME/model.safetensors" | cut -d ' ' -f 1)
 [[ "$ACTUAL" == "$EXPECTED" ]] || { print "Checksum mismatch: $NAME"; exit 1; }
done
print 'Local Qwen speech models installed.'
