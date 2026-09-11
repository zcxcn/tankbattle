"""Fetch the exact CC0 horror-creature FBX member without the redundant ZIP art.

Python 3 standard library only. The ZIP central directory is validated, ranged
responses are checked, and extracted bytes must match CRC, size and SHA-256.
Run from repository root, then pass the printed FBX path to the Blender helper.
"""
import concurrent.futures
import hashlib
import pathlib
import struct
import time
import urllib.request
import zlib

URL = "https://opengameart.org/sites/default/files/Poses.zip"
ARCHIVE_BYTES = 86_723_187
MEMBER = "Poses/Walk.fbx"
SIZE = 15_089_632
SHA256 = "c406f154c6fdec2a7f73bb7742bb571760c73f81053dffd2b2a7516d834b57da"
OUTPUT = pathlib.Path("work/pc048-monsters/Walk.fbx")


def ranged(start, end):
    for attempt in range(4):
        try:
            request = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{end}"})
            with urllib.request.urlopen(request, timeout=90) as response:
                data = response.read()
                expected = f"bytes {start}-{end}/{ARCHIVE_BYTES}"
                assert response.status == 206 and response.headers["Content-Range"] == expected
                assert len(data) == end - start + 1
                return data
        except Exception:
            if attempt == 3:
                raise
            time.sleep(attempt + 1)


def main():
    if OUTPUT.exists() and hashlib.sha256(OUTPUT.read_bytes()).hexdigest() == SHA256:
        print("Verified cached source:", OUTPUT)
        return
    tail = ranged(ARCHIVE_BYTES - 65536, ARCHIVE_BYTES - 1)
    end = tail.rfind(b"PK\x05\x06")
    assert end >= 0
    directory = struct.unpack_from("<4s4H2IH", tail, end)
    offset = directory[6] - (ARCHIVE_BYTES - len(tail))
    found = None
    for _ in range(directory[4]):
        header = struct.unpack_from("<4s6H3I5H2I", tail, offset)
        assert header[0] == b"PK\x01\x02"
        name = tail[offset + 46 : offset + 46 + header[10]].decode()
        if name == MEMBER:
            found = header
        offset += 46 + header[10] + header[11] + header[12]
    assert found is not None
    crc, compressed, size, start = found[7], found[8], found[9], found[-1]
    local = ranged(start, start + 29)
    local_header = struct.unpack("<4s5H3I2H", local)
    assert local_header[0] == b"PK\x03\x04" and local_header[3] == 8
    payload = start + 30 + local_header[-2] + local_header[-1]
    step = 256 * 1024
    spans = [(a, min(a + step, payload + compressed) - 1) for a in range(payload, payload + compressed, step)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        packed = b"".join(pool.map(lambda span: ranged(*span), spans))
    raw = zlib.decompress(packed, -15)
    assert len(raw) == size == SIZE and zlib.crc32(raw) == crc
    assert hashlib.sha256(raw).hexdigest() == SHA256
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(raw)
    print("Downloaded and verified source:", OUTPUT)


if __name__ == "__main__":
    main()
