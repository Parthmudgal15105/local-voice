"""CPU-only IndicXlit word conversion. JSON in/out; no network or sentence rewriting."""
import contextlib
import json
import logging
import os
from pathlib import Path
import sys
import unicodedata
sys.dont_write_bytecode = True

logging.disable(logging.CRITICAL)
os.environ['TOKENIZERS_PARALLELISM'] = 'false'

def main():
    words = json.load(sys.stdin)
    if not isinstance(words, list) or len(words) > 512 or any(not isinstance(w,str) or not 0 < len(w) <= 128 for w in words):
        raise ValueError('Invalid word batch')
    model = Path(sys.argv[1])
    with contextlib.redirect_stdout(sys.stderr):
        import torch
        torch.set_num_threads(2)
        from custom_interactive import Transliterator
        languages = (Path(__file__).parent / 'lang_list.txt').read_text().split()
        engine = Transliterator(str(model/'corpus-bin'), str(model/'transformer/indicxlit.pt'),
                                ','.join(f'{lang}-en' for lang in languages if lang != 'en'),
                                str(Path(__file__).parent/'lang_list.txt'), beam=4, batch_size=32)
        inputs = ['__hi__ ' + ' '.join(unicodedata.normalize('NFC',word)) for word in words]
        with torch.inference_mode():
            output = engine.translate(inputs, nbest=1)
    results = {}
    for line in output.splitlines():
        if line.startswith('H-'):
            index, _, letters = line.split('\t',2)
            results[words[int(index[2:])]] = ''.join(letters.split())
    if set(results) != set(words):
        raise ValueError('Incomplete transliteration')
    json.dump(results, sys.stdout, ensure_ascii=False)

if __name__ == '__main__':
    main()
