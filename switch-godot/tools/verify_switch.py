"""Check real NRO/PCK structure and original runtime provenance; no hardware claims."""
from __future__ import annotations

import datetime
import hashlib
import pathlib
import struct


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from('<I', data, offset)[0]


def cstring(data: bytes) -> str:
    return data.split(b'\x00', 1)[0].decode('utf-8')


def inspect_icon(data: bytes) -> dict:
    assert data[:2] == b'\xff\xd8', 'Icon is not JPEG'
    cursor = 2
    while cursor + 4 <= len(data):
        assert data[cursor] == 0xFF, 'Malformed JPEG marker'
        marker = data[cursor + 1]
        cursor += 2
        length = struct.unpack_from('>H', data, cursor)[0]
        assert length >= 2 and cursor + length <= len(data)
        if marker in (0xC0, 0xC2):
            precision, height, width, components = struct.unpack_from('>BHHB', data, cursor + 2)
            assert precision == 8 and width == 256 and height == 256 and components == 3, 'Icon must be 256x256 8-bit RGB JPEG'
            return {'encoding': 'baseline JPEG' if marker == 0xC0 else 'progressive JPEG', 'width': width, 'height': height, 'components': components}
        assert marker not in (0xDA, 0xD9), 'Missing JPEG frame header'
        cursor += length
    raise AssertionError('Missing JPEG dimensions')


def inspect_nro(data: bytes) -> dict:
    assert data[0x10:0x14] == b'NRO0', 'Missing NRO0 magic'
    native_size = u32(data, 0x18)
    assert 0x80 <= native_size < len(data), 'Invalid native size'
    segments = [dict(zip(('offset', 'size'), struct.unpack_from('<II', data, 0x20 + i * 8))) for i in range(3)]
    previous_end = 0
    for segment in segments:
        assert segment['offset'] >= previous_end
        assert segment['offset'] + segment['size'] <= native_size
        previous_end = segment['offset'] + segment['size']
    assert data[native_size:native_size + 4] == b'ASET', 'Missing asset header'
    sections = {}
    previous_end = native_size + 56
    for index, name in enumerate(('icon', 'nacp', 'romfs')):
        offset, size = struct.unpack_from('<QQ', data, native_size + 8 + index * 16)
        assert offset >= 56 and native_size + offset + size <= len(data), f'Invalid {name} bounds'
        assert native_size + offset >= previous_end, f'Overlapping {name} asset'
        previous_end = native_size + offset + size
        sections[name] = {'offset': native_size + offset, 'size': size}
    assert sections['nacp']['size'] == 0x4000, 'Unexpected NACP size'
    icon = sections['icon']
    icon_info = inspect_icon(data[icon['offset']:icon['offset'] + icon['size']])
    # This NRO format has no ELF machine field. Verify the actual ARM64 branch opcode and its target.
    entry_instruction = u32(data, 0)
    assert entry_instruction & 0xFC000000 == 0x14000000, 'Entry is not an AArch64 B instruction'
    entry_target = (entry_instruction & 0x03FFFFFF) * 4
    assert 0x80 <= entry_target < segments[0]['offset'] + segments[0]['size']
    module_offset = u32(data, 4)
    assert data[module_offset:module_offset + 4] == b'MOD0', 'Missing MOD0 at module offset'
    return {'native_size': native_size, 'segments': segments, 'sections': sections, 'icon': icon_info,
            'entry_instruction': hex(entry_instruction), 'entry_target': entry_target,
            'module_offset': module_offset, 'build_id': data[0x40:0x60].hex()}


def inspect_pck(data: bytes) -> dict:
    assert data[:4] == b'GDPC', 'Missing Godot pack magic'
    format_version, major, minor, patch = struct.unpack_from('<4I', data, 4)
    assert format_version == 1 and (major, minor) == (3, 5), 'Unexpected pack/engine version'
    count = u32(data, 84)
    assert 1 <= count <= 100000
    cursor = 88
    paths = []
    entries = []
    for _ in range(count):
        length = u32(data, cursor)
        cursor += 4
        assert 0 < length <= 65536 and cursor + length + 32 <= len(data)
        path = cstring(data[cursor:cursor + length])
        cursor += length
        offset, size = struct.unpack_from('<QQ', data, cursor)
        md5 = data[cursor + 16:cursor + 32]
        cursor += 32
        assert offset + size <= len(data), f'Invalid bounds for {path}'
        assert hashlib.md5(data[offset:offset + size]).digest() == md5, f'Checksum mismatch for {path}'
        assert not any(path.startswith(f'res://{folder}/') for folder in ['tools', 'build', 'dist', 'docs', 'tests', 'artifacts']), path
        paths.append(path)
        entries.append((offset, size))
    assert len(paths) == len(set(paths)), 'Duplicate pack resource'
    assert 'res://project.binary' in paths or 'res://project.godot' in paths
    assert 'res://scenes/main.tscn' in paths or 'res://scenes/main.scn' in paths
    for offset, size in entries:
        assert offset >= cursor, 'Pack data overlaps directory'
    return {'magic': 'GDPC', 'format_version': format_version, 'engine_version': f'{major}.{minor}.{patch}',
            'resource_count': count, 'all_resource_md5_checked': True, 'paths': paths}


def finalize_and_verify(output: pathlib.Path, template: pathlib.Path, title: str, author: str, version: str) -> dict:
    data = bytearray(output.read_bytes())
    original = template.read_bytes()
    info = inspect_nro(data)
    assert info['icon']['encoding'] == 'baseline JPEG', 'Export must use the project baseline JPEG icon'
    original_info = inspect_nro(original)
    assert digest(original[:original_info['native_size']]) == 'd29e9766f71ca6728ae54b9fcc49d1fc491268edbcfa6eabe76a6527a47acfc1', 'Template native hash differs from tested release'
    assert info['native_size'] == original_info['native_size']
    assert data[:info['native_size']] == original[:info['native_size']], 'Runtime code differs from upstream template'
    # Upstream fills 12 language slots. Fill all 16 explicitly, including Chinese language slots.
    nacp_offset = info['sections']['nacp']['offset']
    for slot in range(16):
        for offset, capacity, text in ((slot * 0x300, 0x200, title), (slot * 0x300 + 0x200, 0x100, author)):
            encoded = text.encode('utf-8')
            assert len(encoded) < capacity
            data[nacp_offset + offset:nacp_offset + offset + capacity] = encoded.ljust(capacity, b'\0')
    encoded_version = version.encode('utf-8')
    assert len(encoded_version) < 0x10
    data[nacp_offset + 0x3060:nacp_offset + 0x3070] = encoded_version.ljust(0x10, b'\0')
    output.write_bytes(data)
    data = output.read_bytes()
    info = inspect_nro(data)
    metadata = data[nacp_offset:nacp_offset + 0x4000]
    assert all(cstring(metadata[i * 0x300:i * 0x300 + 0x200]) == title for i in range(16))
    assert all(cstring(metadata[i * 0x300 + 0x200:(i + 1) * 0x300]) == author for i in range(16))
    assert cstring(metadata[0x3060:0x3070]) == version
    pck = output.with_suffix('.pck')
    packed = pck.read_bytes()
    return {'verified_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'status': 'local_static_validation_passed', 'hardware_tested': False,
            'title': title, 'author': author, 'version': version, 'metadata_language_slots_checked': 16,
            'runtime_source': 'https://github.com/Stary2001/godot/releases/tag/v3.5.1-stable_switch_fixed',
            'architecture': 'AArch64',
            'architecture_evidence': 'ARM64 entry B opcode plus unchanged runtime native sections from upstream ARMv8-A/devkitA64 build; NRO has no ELF machine field.',
            'native_sections_match_upstream_template': True, 'native_sha256': digest(data[:info['native_size']]),
            'nro': {'name': output.name, 'bytes': len(data), 'sha256': digest(data), **info},
            'pck': {'name': pck.name, 'bytes': len(packed), 'sha256': digest(packed), **inspect_pck(packed)},
            'still_requires_switch_testing': ['Application mode boot', 'Visual correctness and frame time', 'Memory',
                                            'Joy-Con and Pro Controller', 'Audio', 'Save and reload', 'HOME and sleep resume', 'Exit']}
