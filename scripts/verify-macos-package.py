#!/usr/bin/env python3
"""Read-only, cross-platform verification of the exported Apple Silicon ZIP.

Checks archive structure and Apple's embedded ad-hoc code/resource hashes. This
does not replace macOS codesign/Gatekeeper checks or testing on an actual Mac.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import plistlib
import posixpath
import stat
import struct
import sys
import zipfile
from pathlib import Path


class InvalidPackage(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise InvalidPackage(message)


def u32(data: bytes, offset: int, endian: str = ">") -> int:
    require(0 <= offset <= len(data) - 4, f"Truncated integer at {offset}")
    return struct.unpack_from(endian + "I", data, offset)[0]


def digest(data: bytes, kind: int) -> bytes:
    algorithm = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}.get(kind)
    require(algorithm is not None, f"Unsupported code-signature hash type {kind}")
    value = hashlib.new(algorithm, data).digest()
    return value[:20] if kind == 3 else value


def cstring(data: bytes, offset: int, end: int) -> str:
    require(0 <= offset < end <= len(data), "Invalid Mach-O string offset")
    return data[offset:end].split(b"\0", 1)[0].decode("utf-8")


def macho_slices(data: bytes) -> list[bytes]:
    magic = data[:4]
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        wide = magic[-1] == 0xBF
        count = u32(data, 4)
        require(0 < count < 16, "Invalid universal architecture count")
        slices = []
        architectures = []
        for index in range(count):
            start = 8 + index * (32 if wide else 20)
            cpu = u32(data, start)
            offset, length = struct.unpack_from(">QQ" if wide else ">II", data, start + 8)
            require(offset + length <= len(data), "Truncated universal binary slice")
            require(cpu in (0x0100000C, 0x01000007), "Unsupported universal architecture")
            part = data[offset:offset + length]
            require(part[:4] == b"\xcf\xfa\xed\xfe" and u32(part, 4, "<") == cpu, "Universal slice CPU mismatch")
            architectures.append(cpu)
            slices.append(part)
        require(len(architectures) == len(set(architectures)), "Duplicate universal architectures")
        return slices
    require(magic == b"\xcf\xfa\xed\xfe", "Expected a 64-bit little-endian Mach-O")
    return [data]


def verify_macho_slice(data: bytes, name: str, special_files: dict[int, bytes] | None = None) -> dict:
    cpu = u32(data, 4, "<")
    require(cpu in (0x0100000C, 0x01000007), f"Unsupported Mach-O CPU: {name}")
    architecture = "arm64" if cpu == 0x0100000C else "x86_64"
    count, command_bytes = struct.unpack_from("<II", data, 16)
    require(32 + command_bytes <= len(data), f"Truncated load commands: {name}")
    cursor = 32
    signature = None
    dependencies, rpaths = [], []
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, cursor)
        require(size >= 8 and cursor + size <= 32 + command_bytes, f"Invalid load command: {name}")
        if command == 0x1D:  # LC_CODE_SIGNATURE
            require(signature is None, f"Duplicate code signature: {name}")
            signature = struct.unpack_from("<II", data, cursor + 8)
        elif command in (0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20):
            dependencies.append(cstring(data, cursor + u32(data, cursor + 8, "<"), cursor + size))
        elif command == 0x8000001C:  # LC_RPATH
            rpaths.append(cstring(data, cursor + u32(data, cursor + 8, "<"), cursor + size))
        cursor += size
    require(cursor == 32 + command_bytes, f"Load-command size mismatch: {name}")
    require(signature is not None, f"Missing LC_CODE_SIGNATURE: {name}")
    offset, length = signature
    require(offset + length <= len(data), f"Truncated signature: {name}")
    blob = data[offset:offset + length]
    require(u32(blob, 0) == 0xFADE0CC0, f"Missing embedded signature SuperBlob: {name}")
    total, entries = u32(blob, 4), u32(blob, 8)
    require(total <= len(blob) and 12 + entries * 8 <= total, f"Invalid SuperBlob: {name}")
    children = {}
    directories = []
    for index in range(entries):
        kind, start = struct.unpack_from(">II", blob, 12 + index * 8)
        end = start + u32(blob, start + 4)
        require(start >= 12 + entries * 8 and end <= total, f"Invalid signature slot: {name}")
        child = blob[start:end]
        # Godot's built-in signer emits SHA-256 and SHA-1 CodeDirectories with
        # the same slot number. Preserve and verify both rather than discarding
        # the first directory in a dictionary keyed only by slot. Apple's XNU
        # cs_validate_csblob() likewise ranks each candidate by hash algorithm.
        if kind == 0 or 0x1000 <= kind < 0x1005:
            require(u32(child, 0) == 0xFADE0C02, f"Invalid CodeDirectory magic: {name}")
            directories.append(child)
        else:
            require(kind not in children, f"Duplicate signature slot: {name}")
            children[kind] = child
    require(bool(directories), f"Missing CodeDirectory: {name}")
    pages, special_count, cdhashes = 0, 0, []
    directory_hash_types = set()
    for directory in directories:
        require(len(directory) >= 44, f"Truncated CodeDirectory: {name}")
        version, flags, hash_offset, identifier_offset, special_slots, code_slots, code_limit = struct.unpack_from(">7I", directory, 8)
        hash_size, hash_type, _, page_exponent = struct.unpack_from("4B", directory, 36)
        require(hash_type not in directory_hash_types, f"Duplicate CodeDirectory hash type {hash_type}: {name}")
        directory_hash_types.add(hash_type)
        require(flags & 2 != 0, f"Expected an ad-hoc signature: {name}")
        require(page_exponent <= 30, f"Invalid signature page size: {name}")
        if version >= 0x20300 and code_limit == 0xFFFFFFFF:
            code_limit = struct.unpack_from(">Q", directory, 56)[0]
        page_size = (1 << page_exponent) if page_exponent else code_limit
        require(code_limit == offset and page_size > 0, f"Signature does not cover all executable bytes: {name}")
        require(code_slots == math.ceil(code_limit / page_size), f"Code-page count mismatch: {name}")
        require(hash_offset - special_slots * hash_size >= 0 and hash_offset + code_slots * hash_size <= len(directory), f"Invalid hash table: {name}")
        require(hash_size == len(digest(b"", hash_type)), f"Unexpected signature digest length: {name}")
        cstring(directory, identifier_offset, len(directory))
        for index in range(code_slots):
            begin = index * page_size
            expected = directory[hash_offset + index * hash_size:hash_offset + (index + 1) * hash_size]
            actual = digest(data[begin:min(begin + page_size, code_limit)], hash_type)
            require(actual == expected, f"Code-page hash mismatch: {name}, page {index}")
        for index in range(1, special_slots + 1):
            expected = directory[hash_offset - index * hash_size:hash_offset - (index - 1) * hash_size]
            if expected == bytes(hash_size):
                continue
            payload = (special_files or {}).get(index, children.get(index))
            require(payload is not None, f"Missing signed special slot {index}: {name}")
            require(digest(payload, hash_type) == expected, f"Special-slot hash mismatch: {name}, slot {index}")
            special_count += 1
        cdhashes.append(digest(directory, hash_type)[:20].hex())
        pages += code_slots
    return {"name": name, "architecture": architecture, "signed_pages": pages,
            "special_hashes": special_count, "cdhashes": cdhashes,
            "dependencies": dependencies, "rpaths": rpaths}


def verify_macho(data: bytes, name: str, special_files: dict[int, bytes] | None = None) -> dict:
    slices = [verify_macho_slice(part, name, special_files) for part in macho_slices(data)]
    return {"name": name, "architectures": [part["architecture"] for part in slices],
            "signed_pages": sum(part["signed_pages"] for part in slices),
            "special_hashes": sum(part["special_hashes"] for part in slices),
            "cdhashes": [value for part in slices for value in part["cdhashes"]],
            "dependencies": sorted({value for part in slices for value in part["dependencies"]}),
            "rpaths": sorted({value for part in slices for value in part["rpaths"]})}


def verify_archive(path: Path, version: str, require_extras: bool, architecture: str) -> dict:
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names = [item.filename for item in infos]
        require(len(names) == len(set(names)), "Duplicate ZIP entries")
        for name in names:
            require(not name.startswith("/") and "\\" not in name and ".." not in name.split("/"), f"Invalid archive path: {name}")
            require(Path(name).suffix.lower() not in (".exe", ".dll", ".msi"), f"Windows binary in macOS package: {name}")
        require(archive.testzip() is None, "ZIP CRC check failed")
        members = {item.filename.rstrip("/"): item for item in infos}
        plists = [name for name in names if name.endswith(".app/Contents/Info.plist")]
        require(len(plists) == 1, "Expected exactly one app bundle")
        plist_name = plists[0]
        app_root = plist_name.removesuffix("/Contents/Info.plist")
        contents = app_root + "/Contents/"
        plist_data = archive.read(plist_name)
        info = plistlib.loads(plist_data)
        executable = info.get("CFBundleExecutable", "")
        require(isinstance(executable, str) and executable and "/" not in executable, "Invalid CFBundleExecutable")
        require(info.get("CFBundlePackageType") == "APPL", "Bundle is not an APPL")
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            require(info.get(key) == version, f"Expected {key}={version}, found {info.get(key)}")
        executable_name = contents + "MacOS/" + executable
        require(executable_name in members, "Bundle executable is missing")
        executable_info = members[executable_name]
        require(executable_info.create_system == 3 and stat.S_IMODE(executable_info.external_attr >> 16) == 0o755,
                "Executable must retain Unix 0755 mode in ZIP")

        def resolved(name: str) -> str:
            name = posixpath.normpath(name)
            for _ in range(32):
                parts = name.split("/")
                for index in range(1, len(parts) + 1):
                    prefix = "/".join(parts[:index])
                    entry = members.get(prefix)
                    if entry and stat.S_ISLNK(entry.external_attr >> 16):
                        target = archive.read(entry).decode("utf-8")
                        require(not target.startswith("/"), f"Absolute bundle symlink: {prefix}")
                        name = posixpath.normpath(posixpath.join(posixpath.dirname(prefix), target, *parts[index:]))
                        require(name == app_root or name.startswith(app_root + "/"), f"Symlink leaves app: {prefix}")
                        break
                else:
                    require(name in members or any(entry.startswith(name + "/") for entry in members), f"Missing symlink/dependency target: {name}")
                    return name
            raise InvalidPackage(f"Cyclic bundle symlink: {name}")

        symlinks = [name for name, entry in members.items() if stat.S_ISLNK(entry.external_attr >> 16)]
        for name in symlinks:
            resolved(name)
        pck_name = contents + "Resources/" + executable + ".pck"
        require(pck_name in members and members[pck_name].file_size > 1024, "Missing or empty game PCK")
        with archive.open(pck_name) as pck:
            require(pck.read(4) == b"GDPC", "Invalid Godot PCK magic")
        seal_name = contents + "_CodeSignature/CodeResources"
        require(seal_name in members, "Missing bundle resource signature")
        seal_data = archive.read(seal_name)
        seal = plistlib.loads(seal_data)
        binaries = {}
        for name, entry in members.items():
            if not name.startswith(contents) or entry.is_dir() or stat.S_ISLNK(entry.external_attr >> 16):
                continue
            with archive.open(entry) as stream:
                magic = stream.read(4)
            if magic in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
                special = {1: plist_data, 3: seal_data} if name == executable_name else {}
                binaries[name] = verify_macho(archive.read(entry), name, special)
            require(magic[:2] != b"MZ", f"Unexpected Windows PE header: {name}")
        require(executable_name in binaries, "Main executable is not a Mach-O")
        expected_architectures = {"arm64", "x86_64"} if architecture == "universal" else {"arm64"}
        require(set(binaries[executable_name]["architectures"]) == expected_architectures,
                f"Main executable does not contain the expected {architecture} architecture(s)")
        signed_resources = set()
        resource_hashes = 0
        for table_name in ("files", "files2"):
            for relative, value in seal.get(table_name, {}).items():
                name = contents + relative
                value = {"hash": value} if isinstance(value, bytes) else value
                require(isinstance(value, dict), f"Invalid resource signature: {relative}")
                if value.get("optional") and name not in members:
                    continue
                target_name = resolved(name)
                if "symlink" in value:
                    require(name in symlinks and archive.read(name).decode("utf-8") == value["symlink"], f"Symlink seal mismatch: {relative}")
                for key, algorithm in (("hash", "sha1"), ("hash2", "sha256")):
                    if key in value:
                        require(hashlib.new(algorithm, archive.read(target_name)).digest() == value[key], f"Resource hash mismatch: {relative}")
                        resource_hashes += 1
                        signed_resources.add(name)
                if "cdhash" in value:
                    binary = binaries.get(target_name)
                    require(binary is not None and value["cdhash"].hex() in binary["cdhashes"], f"Nested-code signature mismatch: {relative}")
        require(pck_name in signed_resources, "Game PCK is not protected by resource signature")

        def expand_dependency(value: str, owner: str) -> str:
            return value.replace("@loader_path", posixpath.dirname(owner)).replace("@executable_path", posixpath.dirname(executable_name))

        dependency_count = 0
        for name, binary in binaries.items():
            for dependency in binary["dependencies"]:
                if dependency.startswith(("/usr/lib/", "/System/Library/")):
                    dependency_count += 1
                    continue
                if dependency.startswith("@rpath/"):
                    candidates = [posixpath.join(expand_dependency(base, name), dependency[7:])
                                  for base in binary["rpaths"] + binaries[executable_name]["rpaths"]]
                else:
                    candidates = [expand_dependency(dependency, name)]
                found = False
                for candidate in candidates:
                    try:
                        target = resolved(candidate)
                        found = target in binaries
                    except InvalidPackage:
                        continue
                    if found:
                        break
                require(found, f"Unresolved library dependency: {name}: {dependency}")
                dependency_count += 1
        outer_files = [name for name in names if not name.startswith(app_root + "/") and not name.endswith("/")]
        if require_extras:
            require(any(posixpath.basename(name).lower().startswith("readme") for name in outer_files), "Missing outer README")
            require(any(name.endswith("credits/THIRD_PARTY_ASSETS.md") for name in outer_files), "Missing outer third-party credits")
        with path.open("rb") as stream:
            archive_hash = hashlib.file_digest(stream, "sha256").hexdigest()
        return {"result": "PASS", "archive": str(path.resolve()), "version": version, "architecture": architecture,
                "app": app_root, "bundle_identifier": info.get("CFBundleIdentifier"),
                "zip_entries": len(infos), "executable_mode": "0755", "pck_bytes": members[pck_name].file_size,
                "resource_hashes_verified": resource_hashes, "symlinks_verified": len(symlinks),
                "library_dependencies_verified": dependency_count, "binaries": list(binaries.values()),
                "sha256": archive_hash,
                "limitations": "Archive and embedded hashes verified on host; macOS Gatekeeper and M4 runtime not tested."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--version", default="0.4.11")
    parser.add_argument("--architecture", choices=("universal", "arm64"), default="universal")
    parser.add_argument("--require-extras", action="store_true", help="Require outer README and credits after final packaging")
    args = parser.parse_args()
    try:
        result = verify_archive(args.archive, args.version, args.require_extras, args.architecture)
    except (InvalidPackage, OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
