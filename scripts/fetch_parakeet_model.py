#!/usr/bin/env python3
"""Fetch the pinned Core ML model for reproducible local/device diagnostics."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

project = Path(__file__).resolve().parent.parent
manifest = json.loads((project / 'shared/Config/parakeet-model-manifest.json').read_text())
folder = project / 'build/parakeet-models' / ('parakeet-v3-' + manifest['revision'])
folder.mkdir(parents=True, exist_ok=True)

def valid(path, entry):
    if not path.is_file() or path.stat().st_size != entry['size']:
        return False
    digest = hashlib.sha256() if entry['sha256'] else hashlib.sha1()
    if not entry['sha256']:
        digest.update(f"blob {entry['size']}\0".encode())
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest() == entry['hash']

def fetch(entry):
    path = folder / entry['path']
    if valid(path, entry):
        return entry['path']
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.download')
    url = 'https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/' + manifest['revision'] + '/' + entry['path']
    with urllib.request.urlopen(url, timeout=300) as response, temporary.open('wb') as stream:
        while chunk := response.read(4 * 1024 * 1024):
            stream.write(chunk)
    if not valid(temporary, entry):
        raise RuntimeError('Integrity check failed: ' + entry['path'])
    temporary.replace(path)
    return entry['path']

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for name in pool.map(fetch, manifest['files']):
        print('Verified', name, flush=True)
(folder / 'verified-revision').write_text(manifest['revision'])
print('Model ready:', folder, flush=True)
