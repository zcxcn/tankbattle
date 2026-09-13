#!/usr/bin/env python3
"""Repackage the verified upstream NRO as a narrowly scoped IronEmbers helper.

Does not execute the downloaded NRO, access a Switch, or need any console keys.
Only the pre-existing local devkitPro build_romfs program is executed. The
upstream native executable and all original RomFS assets except main.js remain
byte-for-byte identical. Console-side packaging keeps generated keys in memory.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import struct
import subprocess

EXPECTED_SHA256 = "c668d6cf665ec8f38faf6288d7767df2ca3796bb0502ac25a5ae20eeecd4bdb5"
PROJECT = Path(__file__).resolve().parents[1]
TARGET_NRO = "sdmc:/switch/IronEmbers/IronEmbers.nro"
TARGET_PCK = "sdmc:/switch/IronEmbers/IronEmbers.pck"
TITLE_ID = f"{0x0100000000000000 | (int.from_bytes(hashlib.sha256((TARGET_NRO * 2).encode()).digest()[:8], 'little') & 0x00fffffffffff000):016x}"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def bounded(data: bytes, offset: int, size: int, label: str) -> bytes:
    require(offset >= 0 and size >= 0 and offset + size <= len(data),
            f"Invalid {label} bounds: {offset:#x}+{size:#x}/{len(data):#x}")
    return data[offset:offset + size]


def split_nro(data: bytes) -> tuple[bytes, bytes, bytes, bytes]:
    require(len(data) >= 0x80 and data[0x10:0x14] == b"NRO0", "Expected NRO0")
    native_size = struct.unpack_from("<I", data, 0x18)[0]
    native = bounded(data, 0, native_size, "native NRO")
    aset = bounded(data, native_size, 0x38, "ASET header")
    require(aset[:8] == b"ASET\0\0\0\0", "Unsupported ASET version")
    sections = []
    previous_end = 0x38
    for index, name in enumerate(("icon", "NACP", "RomFS")):
        offset, size = struct.unpack_from("<QQ", aset, 8 + index * 16)
        require(offset >= previous_end and size > 0, f"Missing/overlapping {name}")
        sections.append(bounded(data, native_size + offset, size, name))
        previous_end = offset + size
    require(native_size + previous_end == len(data), "Unexpected trailing NRO data")
    return native, *sections


def pack_nro(native: bytes, icon: bytes, nacp: bytes, romfs: bytes) -> bytes:
    offset = 0x38
    header = bytearray(b"ASET\0\0\0\0")
    for section in (icon, nacp, romfs):
        header += struct.pack("<QQ", offset, len(section))
        offset += len(section)
    return native + header + icon + nacp + romfs


def romfs_files(data: bytes) -> dict[str, bytes]:
    require(len(data) >= 0x50, "Truncated RomFS header")
    (header_size, dir_hash, dir_hash_size, dir_table, dir_size,
     file_hash, file_hash_size, file_table, file_size, payload) = struct.unpack_from("<10Q", data)
    require(header_size == 0x50, "Unsupported RomFS header size")
    bounded(data, dir_hash, dir_hash_size, "directory hash table")
    directories = bounded(data, dir_table, dir_size, "directory table")
    bounded(data, file_hash, file_hash_size, "file hash table")
    files = bounded(data, file_table, file_size, "file table")
    require(payload <= len(data), "Invalid RomFS payload offset")
    result: dict[str, bytes] = {}
    seen_dirs: set[int] = set()
    seen_files: set[int] = set()
    null = 0xFFFFFFFF

    def name_at(table: bytes, offset: int, size: int) -> str:
        name = bounded(table, offset, size, "entry name").decode("utf-8")
        require(name not in (".", "..") and "/" not in name and "\\" not in name
                and ":" not in name and "\0" not in name, "Unsafe RomFS name")
        return name

    def visit(directory: int, parent_path: str, expected_parent: int) -> int:
        require(directory not in seen_dirs, "Cyclic/duplicate RomFS directory")
        seen_dirs.add(directory)
        fields = struct.unpack("<6I", bounded(directories, directory, 24, "directory"))
        parent, sibling, child, first_file, _hash, name_size = fields
        require(directory == 0 or parent == expected_parent, "RomFS directory parent mismatch")
        name = name_at(directories, directory + 24, name_size)
        path = f"{parent_path}/{name}".strip("/")
        if directory == 0:
            require(name == "" and sibling == null, "Unexpected RomFS root")
        file = first_file
        while file != null:
            require(file not in seen_files, "Cyclic/duplicate RomFS file")
            seen_files.add(file)
            fparent, next_file, offset, size, _fhash, fsize = struct.unpack(
                "<IIQQII", bounded(files, file, 32, "file"))
            require(fparent == directory, "RomFS file parent mismatch")
            filename = name_at(files, file + 32, fsize)
            require(bool(filename), "Empty RomFS filename")
            relative = f"{path}/{filename}".lstrip("/")
            require(relative not in result, "Duplicate RomFS path")
            result[relative] = bounded(data, payload + offset, size, relative)
            file = next_file
        while child != null:
            child = visit(child, path, directory)
        return sibling

    visit(0, "", 0)
    require("main.js" in result, "Expected nx.js main.js")
    return result


def replace_once(text: str, old: str, new: str) -> str:
    require(text.count(old) == 1, f"Expected exactly one upstream patch marker: {old[:100]!r}")
    return text.replace(old, new, 1)


def patch_js(text: str) -> str:
    # Always use the upstream SPL derivation; never open or export prod.keys.
    text = replace_once(text,
        'var prodKeys = Switch.readFileSync("sdmc:/switch/prod.keys");',
        'var prodKeys; // IronEmbers: generate only in console memory through SPL.')
    text = replace_once(text,
        '  console.debug(\n    `Generated header key from "spl" service: ${keyHex.slice(0, 8)}...${keyHex.slice(-8)}`\n  );',
        '  // IronEmbers: do not print any part of the derived key.')
    # Do not enumerate other homebrew or read their metadata.
    text = replace_once(text,
        'var apps = [\n  new URL("sdmc:/hbmenu.nro"),\n  ...nroIterator("sdmc:/switch/")\n].map(pathToAppInfo).filter((v2) => typeof v2 !== "undefined");',
        'var IRONEMBERS_HOME = Object.freeze({\n'
        f'  path: {json.dumps(TARGET_NRO)},\n'
        '  name: "\\u94a2\\u94c1\\u4f59\\u70ec",\n'
        '  author: "Iron Embers Build", version: "0.1.0", romPath: "",\n'
        '  icon: Switch.readFileSync("romfs:/ironembers-icon.jpg")\n'
        '});\nvar apps = [IRONEMBERS_HOME];')
    start_marker = 'function Edit() {\n'
    end_marker = '\n// src/main.tsx\n'
    require(text.count(start_marker) == 1 and text.count(end_marker) == 1,
            "Edit component boundaries are not unique")
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    require(text[start:end].endswith('}\n'), "Unexpected Edit component ending")
    # Keep the established /edit -> /generate route and title-ID algorithm.
    # This UI exposes only the requested game, with no editable paths or IDs.
    component = r'''function Edit() {
  const root = useParent();
  const navigate = useNavigate();
  const [id, setId] = (0, import_react20.useState)("");
  const [status, setStatus] = (0, import_react20.useState)("Checking IronEmbers...");
  const [busy, setBusy] = (0, import_react20.useState)(false);
  (0, import_react20.useEffect)(() => {
    let active = true;
    (async () => {
      const game = pathToAppInfo(new URL(IRONEMBERS_HOME.path));
      if (!game) throw new Error("Game missing: /switch/IronEmbers/IronEmbers.nro");
      const pack = Switch.statSync(new URL("sdmc:/switch/IronEmbers/IronEmbers.pck"));
      if (!pack || isDirectory(pack.mode) || pack.size <= 0) throw new Error("Game data missing: /switch/IronEmbers/IronEmbers.pck");
      if (!IRONEMBERS_HOME.icon) throw new Error("Embedded game icon is missing");
      const generatedId = await generateDeterministicID(IRONEMBERS_HOME.path, IRONEMBERS_HOME.path);
      if (!/^[0-9a-f]{16}$/.test(generatedId)) throw new Error("Invalid generated title ID");
      if (generatedId !== "01cdcf1458845000") throw new Error("Unexpected game title ID");
      if (active) { setId(generatedId); setStatus("Ready. A installs; Y saves NSP."); }
    })().catch((error) => { if (active) setStatus(String(error)); });
    return () => { active = false; };
  }, []);
  const goToGenerate = (0, import_react20.useCallback)((install) => {
    if (busy || !/^[0-9a-f]{16}$/.test(id)) return;
    setBusy(true);
    navigate("/generate", { state: { ...IRONEMBERS_HOME, id, profileSelector: false, install } });
  }, [id, busy, navigate]);
  useGamepadButton("Y", () => goToGenerate(false), [goToGenerate]);
  useGamepadButton("A", () => goToGenerate(true), [goToGenerate]);
  useGamepadButton("B", () => Switch.exit(), []);
  const jsx = import_jsx_runtime17.jsx;
  const lines = [
    ["IronEmbers HOME Setup", 36, 28],
    ["Iron Embers - Switch / version 0.1.0", 28, 100],
    ["Iron Embers Build", 24, 146],
    ["Y  Save NSP: create /IronEmbers-HOME.nsp", 24, 246],
    ["Then use DBI MTP > 5: SD Card install.", 24, 290],
    ["A  Install to HOME: install the same NSP now.", 24, 370],
    ["Your game stays in /switch/IronEmbers/.", 24, 416],
    [status, 22, 518],
    [id ? "Title ID: " + id : "", 18, 556]
  ];
  return import_jsx_runtime17.jsxs(import_jsx_runtime17.Fragment, { children: [
    ...lines.map(([label, size, y], index) => jsx(Text2, {
      fill: index === 7 ? "#ffcc77" : "white", fontSize: size, x: 32, y, children: label
    }, "ironembers-line-" + index)),
    jsx(AppIcon, { icon: IRONEMBERS_HOME.icon, x: root.ctx.canvas.width - 304, y: 32, width: 160, height: 160 }),
    jsx(Footer, { children: [
      jsx(FooterItem, { button: "B", x: 40, children: "Exit" }),
      jsx(FooterItem, { button: "Y", x: 440, children: "Save NSP" }),
      jsx(FooterItem, { button: "A", x: 840, children: "Install to HOME" })
    ] })
  ] });
}
'''
    text = text[:start] + component + text[end:]
    text = replace_once(text, 'var initialRoute = "/select-forwarder-type";',
                        'var initialRoute = "/edit";')
    # The success screen's optional restart must stay inside this game helper.
    text = replace_once(text,
        'useGamepadButton("Minus", () => navigate("/select-forwarder-type"), [',
        'useGamepadButton("Minus", () => navigate("/edit"), [')
    text = replace_once(text,
        'const fileName = `${name.replace(/[:/\\\\]/g, "-")} [${id}].nsp`;',
        'const fileName = "IronEmbers-HOME.nsp";')
    text = replace_once(text,
        '  console.debug("Found `prod.keys` file");',
        '  // IronEmbers: no console key file is opened.')
    text = replace_once(text,
        'setError("missing `prod.keys` file");',
        'setError("In-memory SPL setup failed; no key file is used.");')
    text = replace_once(text,
        '                    navigate(`/success?${query}`);\n                  });',
        '                    navigate(`/success?${query}`);\n'
        '                  }).catch((error) => {\n'
        '                    setStatus("error");\n'
        '                    setError(`HOME install failed: ${String(error)}`);\n'
        '                  });')
    require('Switch.readFileSync("sdmc:/switch/prod.keys")' not in text,
            "The helper must not read prod.keys")
    require("keyHex.slice(" not in text, "Derived key fragments must not be logged")
    require(text.count('var IRONEMBERS_HOME = Object.freeze(') == 1,
            "IronEmbers configuration must be unique")
    require(text.count('var initialRoute = "/edit";') == 1, "Incorrect helper entry route")
    require(text.count('useGamepadButton("A", () => goToGenerate(true)') == 1,
            "A must be the sole direct-install button")
    require(text.count('useGamepadButton("Y", () => goToGenerate(false)') == 1,
            "Y must save the NSP")
    require('NcmStorageId.SdCard' in text and 'HOME install failed:' in text,
            "SD installation or error handling missing")
    require('var initialRoute = "/generate";' not in text, "Automatic installation is forbidden")
    return text


def helper_nacp(original: bytes) -> bytes:
    require(len(original) == 0x4000, "Expected 16 KiB NACP")
    nacp = bytearray(original)
    for lang in range(16):
        offset = lang * 0x300
        nacp[offset:offset + 0x300] = b"\0" * 0x300
        title = b"IronEmbers HOME Setup"
        author = b"Iron Embers Build"
        nacp[offset:offset + len(title)] = title
        nacp[offset + 0x200:offset + 0x200 + len(author)] = author
    nacp[0x3060:0x3070] = b"0.1.0\0" + b"\0" * 10
    return bytes(nacp)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=PROJECT / "outputs/switch-home/IronEmbersHome/IronEmbersHome.nro")
    parser.add_argument("--romfs-builder", type=Path, required=True)
    args = parser.parse_args()
    original = args.source.read_bytes()
    require(sha(original) == EXPECTED_SHA256, "Upstream NRO SHA256 mismatch; refusing to modify")
    native, _icon, nacp, romfs = split_nro(original)
    old_files = romfs_files(romfs)
    patched = patch_js(old_files["main.js"].decode("utf-8")).encode("utf-8")
    icon = (PROJECT / "work/switch-project/assets/icon.jpg").read_bytes()
    require(icon[:2] == b"\xff\xd8" and icon[-2:] == b"\xff\xd9" and len(icon) < 0x20000,
            "Invalid or oversized game JPEG icon")
    new_files = {**old_files, "main.js": patched, "ironembers-icon.jpg": icon}
    builder = args.romfs_builder
    require(builder.is_file(), "Local devkitPro build_romfs.exe is unavailable")
    work = PROJECT / "work/switch-forwarder-helper"
    work.mkdir(parents=True, exist_ok=True)
    # Keep extracted sources available for review and reproducibility.
    tree = work / "romfs"
    for name, content in new_files.items():
        path = tree.joinpath(*PurePosixPath(name).parts)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    node = shutil.which("node")
    require(node is not None, "Node.js is required to syntax-check the patched JavaScript")
    check_path = work / "main.mjs"
    check_path.write_bytes(patched)
    subprocess.run([node, "--check", str(check_path)], check=True)
    # Execute only the pure upstream title-ID algorithm on PC; no Switch API or keys.
    id_start = patched.decode().index('async function generateDeterministicID(')
    id_end = patched.decode().index('\n}\n', id_start) + 3
    id_check = work / "verify-title-id.mjs"
    id_check.write_text(
        patched.decode()[id_start:id_end] +
        f'\nconst actual = await generateDeterministicID({json.dumps(TARGET_NRO)}, {json.dumps(TARGET_NRO)});\n' +
        f'if (actual !== {json.dumps(TITLE_ID)}) throw new Error("Title ID mismatch");\n' +
        'console.log("Verified title ID: " + actual);\n', encoding="utf-8")
    subprocess.run([node, str(id_check)], check=True)
    built = work / "assets.romfs"
    subprocess.run([str(builder), str(tree), str(built)], check=True)
    built_romfs = built.read_bytes()
    require(romfs_files(built_romfs) == new_files, "Rebuilt RomFS did not round-trip byte-for-byte")
    generated = pack_nro(native, icon, helper_nacp(nacp), built_romfs)
    new_native, new_icon, new_nacp, verified_romfs = split_nro(generated)
    require(new_native == native and new_icon == icon, "Executable or icon verification failed")
    require(sha(native) == "db1998dfa7409c42237641efe39b7b3579a800322daafb35d348fdeaa45c648a",
            "Native runtime differs from the verified upstream 0.0.8 build")
    require(all(new_nacp[i * 0x300:i * 0x300 + 0x200].split(b"\0", 1)[0] == b"IronEmbers HOME Setup"
                and new_nacp[i * 0x300 + 0x200:(i + 1) * 0x300].split(b"\0", 1)[0] == b"Iron Embers Build"
                for i in range(16)), "Helper NACP language metadata mismatch")
    verified_files = romfs_files(verified_romfs)
    require(verified_files == new_files, "Final NRO asset verification failed")
    for name, content in old_files.items():
        if name != "main.js":
            require(verified_files[name] == content, f"Upstream asset unexpectedly modified: {name}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(generated)
    require(args.output.read_bytes() == generated, "Written helper differs from verified build")
    (args.output.parent / "HELPER-README.txt").write_text(
        "IronEmbers HOME Setup 0.1.0\n\n"
        "钢铁余烬 · Switch HOME 桌面入口助手\n"
        "请在完整 Application 模式的 hbmenu 中打开 IronEmbers HOME Setup。\n"
        "A：立即安装钢铁余烬的 HOME 入口到 SD 卡。\n"
        "Y：仅保存 sdmc:/IronEmbers-HOME.nsp，之后可交给 DBI 安装。\n"
        "B：退出。打开助手不会自动安装。\n"
        "游戏的 IronEmbers.nro 与 IronEmbers.pck 必须保留在 sdmc:/switch/IronEmbers/。\n"
        "本地助手检查已通过；主机运行和 HOME 图标仍待实际确认。\n\n"
        "This helper creates an NSP launcher only for:\n"
        "  sdmc:/switch/IronEmbers/IronEmbers.nro\n\n"
        "1. Hold R while opening an existing game to enter full-memory hbmenu.\n"
        "2. Open IronEmbers HOME Setup. Album/applet mode is not supported.\n"
        "3. Press A (Install to HOME) to install the launcher to SD now.\n"
        "Alternatively press Y (Save NSP) to save /IronEmbers-HOME.nsp.\n"
        "Open DBI MTP and install the saved NSP through 5: SD Card install.\n"
        "Press B to exit. Nothing is installed automatically.\n\n"
        "Leave the original game NRO and same-name PCK at their existing paths. No prod.keys file is\n"
        "required, read, saved, or exported. The existing upstream SPL method\n"
        "derives packaging material in console memory only. No key fragments\n"
        "are logged. No other game is selected or modified.\n\n"
        "Based on TooTallNate/switch-nsp-forwarder 0.0.8:\n"
        "https://github.com/TooTallNate/switch-nsp-forwarder/releases/tag/0.0.8\n"
        "Original native executable, forwarder loader, WASM packer, and other\n"
        "runtime assets are preserved. Only the app UI JavaScript and installer\n"
        "name/icon are customized. See LICENSES.txt and the verification JSON.\n",
        encoding="utf-8")
    license_footer = patched.decode("utf-8").partition("/*! Bundled license information:")[2]
    require(bool(license_footer), "Missing upstream bundled license notices")
    (args.output.parent / "LICENSES.txt").write_text(
        "Upstream project: https://github.com/TooTallNate/switch-nsp-forwarder\n"
        "Version: 0.0.8. package.json declares MIT. Nathan Rajlich (TooTallNate).\n\n"
        "MIT License\n\nCopyright (c) Nathan Rajlich and contributors\n\n"
        "Permission is hereby granted, free of charge, to any person obtaining a copy\n"
        "of this software and associated documentation files (the \"Software\"), to deal\n"
        "in the Software without restriction, including without limitation the rights\n"
        "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
        "copies of the Software, and to permit persons to whom the Software is\n"
        "furnished to do so, subject to the following conditions:\n\n"
        "The above copyright notice and this permission notice shall be included in all\n"
        "copies or substantial portions of the Software.\n\n"
        "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n"
        "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n"
        "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n"
        "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n"
        "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n"
        "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n"
        "SOFTWARE.\n\n"
        "Unmodified hacBrewPack WASM is GPL-2.0:\n"
        "https://github.com/The-4n/hacBrewPack\n"
        "https://github.com/The-4n/hacBrewPack/blob/master/LICENSE\n\n"
        "Original JavaScript bundle license notices follow:\n/*! Bundled license information:"
        + license_footer, encoding="utf-8")
    report = {
        "status": "local_helper_validation_passed",
        "verified_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "upstream_release": "https://github.com/TooTallNate/switch-nsp-forwarder/releases/tag/0.0.8",
        "source": str(args.source.resolve()), "source_sha256": sha(original),
        "output": str(args.output.resolve()), "output_sha256": sha(generated),
        "size": len(generated), "native_size": len(native), "native_sha256": sha(native),
        "native_unchanged": True, "preserved_romfs_files": len(old_files) - 1,
        "modified_romfs_files": ["main.js"], "added_romfs_files": ["ironembers-icon.jpg"],
        "helper_title": "IronEmbers HOME Setup", "game_title": "钢铁余烬 · Switch", "author": "Iron Embers Build",
        "target_nro": TARGET_NRO, "target_argv": TARGET_NRO, "required_pck": TARGET_PCK,
        "nsp_output_path": "sdmc:/IronEmbers-HOME.nsp", "automatic_install": False,
        "title_id": TITLE_ID, "title_id_algorithm": "upstream SHA256(path+argv), LE first64, mask 00fffffffffff000, OR 0100000000000000",
        "buttons": {"A": "install to NcmStorageId.SdCard", "Y": "save NSP only", "B": "exit"},
        "prod_keys_file_read": False, "sensitive_key_logging": False,
        "console_keys_exported": False,
        "javascript_syntax_checked": True, "title_id_node_python_agree": True,
        "romfs_roundtrip_verified": True, "helper_nacp_language_slots_checked": 16,
        "original_romfs_sha256": {name: sha(content) for name, content in old_files.items()},
        "output_romfs_sha256": {name: sha(content) for name, content in verified_files.items()},
        "helper_transferred": False, "hardware_tested": False,
        "nsp_generated_on_console": False, "home_title_installed": False,
        "requires_application_mode": True,
    }
    args.output.with_suffix(".verification.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (PROJECT / "outputs/switch-home/home-helper-validation.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
