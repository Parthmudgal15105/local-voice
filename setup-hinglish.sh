#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
DATA="$HOME/Library/Application Support/Local Voice"
UV=$(command -v uv || true)
[[ -n "$UV" ]] || UV="$HOME/.local/bin/uv"
[[ -x "$UV" ]] || { print 'Install uv from https://docs.astral.sh/uv/ first.'; exit 1; }
mkdir -p "$DATA"
if [[ ! -x "$DATA/xlit-env/bin/python" ]]; then "$UV" venv --python 3.10 "$DATA/xlit-env"; fi
"$UV" pip install --python "$DATA/xlit-env/bin/python" -r xlit/requirements.lock
if [[ ! -f "$DATA/indicxlit/transformer/indicxlit.pt" ]]; then
  ARCHIVE="$DATA/indicxlit.zip.download"
  curl -fL --retry 3 -C - https://github.com/AI4Bharat/IndicXlit/releases/download/v1.0/indicxlit-indic-en-v1.0.zip -o "$ARCHIVE"
  "$DATA/xlit-env/bin/python" - "$ARCHIVE" "$DATA/indicxlit" <<'PY'
import hashlib, pathlib, sys, zipfile
archive=pathlib.Path(sys.argv[1]); root=pathlib.Path(sys.argv[2])
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='420d23a13cfa953edfb47644bc805de06e97134f25e6d182303a29f55b5a3322', 'Model checksum mismatch'
root.mkdir(mode=0o700,exist_ok=True)
with zipfile.ZipFile(archive) as z:
 for member in z.infolist():
  assert not pathlib.Path(member.filename).is_absolute() and '..' not in pathlib.Path(member.filename).parts
 assert z.testzip() is None
 z.extractall(root)
archive.unlink()
PY
fi
print 'Local Hinglish model ready.'
