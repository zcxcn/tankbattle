"""Verify Godot 3 source and generated-resource hashes before exporting assets."""
from __future__ import annotations

import hashlib
import json
import pathlib
import re


IMPORT_EXTENSIONS = {'.glb', '.gltf', '.png', '.jpg', '.jpeg', '.webp', '.svg', '.wav', '.ogg', '.mp3'}


def check_imports(project: pathlib.Path) -> list[dict]:
    project = project.resolve()
    result = []
    for source in sorted((project / 'assets').rglob('*')):
        if not source.is_file() or source.suffix.lower() not in IMPORT_EXTENSIONS:
            continue
        uri = 'res://' + source.relative_to(project).as_posix()
        sidecar = pathlib.Path(str(source) + '.import')
        if not sidecar.is_file():
            raise RuntimeError(f'Asset has not been imported: {uri}')
        config = sidecar.read_text(encoding='utf-8')
        source_match = re.search(r'^source_file="([^"]+)"', config, re.M)
        if not source_match or source_match.group(1) != uri:
            raise RuntimeError(f'Wrong source mapping in {sidecar}')
        cache_stem = source.name + '-' + hashlib.md5(uri.encode('utf-8')).hexdigest()
        checksum_file = project / '.import' / (cache_stem + '.md5')
        if not checksum_file.is_file():
            raise RuntimeError(f'Import checksum is missing: {uri}')
        checksums = dict(re.findall(r'^(\w+)="([a-f0-9]+)"', checksum_file.read_text(), re.M))
        raw = source.read_bytes()
        source_md5 = hashlib.md5(raw).hexdigest()
        if checksums.get('source_md5') != source_md5:
            raise RuntimeError(f'Stale imported resource: {uri}; source changed since import')
        destinations_match = re.search(r'^dest_files=\[(.*?)\]', config, re.M | re.S)
        if not destinations_match:
            raise RuntimeError(f'Import destinations are missing: {uri}')
        destinations = re.findall(r'"([^"]+)"', destinations_match.group(1))
        destination_digest = hashlib.md5()
        for destination_uri in destinations:
            if not destination_uri.startswith('res://'):
                raise RuntimeError(f'Unexpected import destination: {destination_uri}')
            destination = (project / destination_uri[6:]).resolve()
            if not destination.is_relative_to(project) or not destination.is_file():
                raise RuntimeError(f'Missing or invalid import destination: {destination_uri}')
            destination_digest.update(destination.read_bytes())
        if not destinations or destination_digest.hexdigest() != checksums.get('dest_md5'):
            raise RuntimeError(f'Import cache data checksum mismatch: {uri}')
        result.append({'source': uri, 'bytes': len(raw), 'source_md5': source_md5,
                       'source_sha256': hashlib.sha256(raw).hexdigest(),
                       'destinations': destinations, 'destination_md5': destination_digest.hexdigest()})
    return result


if __name__ == '__main__':
    project = pathlib.Path(__file__).resolve().parents[2]
    records = check_imports(project)
    print(json.dumps({'status': 'current', 'asset_count': len(records), 'assets': records}, indent=2))
