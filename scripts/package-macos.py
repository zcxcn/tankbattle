"""Add documentation alongside a signed Godot app without altering its bundle."""
import hashlib
import json
import pathlib
import stat
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
README = """钢铁余烬 · Iron Embers 0.4.12 / macOS Universal

适用于 MacBook Pro M4，以及 Apple Silicon 芯片的 Mac（macOS 13 或更新版本）。
通用包内含 ARM64 原生应用，包含完整战役及无尽防守，无需安装 Godot、Rosetta 或额外模型。

启动：
1. 将整个 ZIP 传到 Mac，并在访达中双击解压。
2. 将 IronEmbers.app 拖到“应用程序”文件夹。
3. 双击 IronEmbers.app。

首次打开：
此个人测试包使用 ad-hoc 本地签名，未经过 Apple 开发者公证。
若 macOS 提示无法验证开发者，先尝试打开一次，然后进入：
“系统设置 → 隐私与安全性 → 安全性 → 仍要打开”，确认 IronEmbers。
无需关闭系统的全局安全检查。
Apple 官方说明：https://support.apple.com/en-us/102445

操作：WASD 移动，鼠标瞄准，左键射击；1–4 / R 换武器；C 换视角；
E 脉冲，M 地雷，N 音乐，Esc 暂停。无尽模式在暂停菜单购买升级。
标准手柄：左摇杆移动，右摇杆瞄准，RT 开火，X 换武器，Y 换视角，Start 暂停。
远程桌面使用 F8 切换绝对鼠标；本地鼠标无需开启。

首次进入可能需要编译着色器。使用 Retina 高分辨率时可在作战设置降低画质。

构建检查：官方 Godot 4.7.2 模板；ARM64、应用结构、执行权限、资源和签名静态检查。
本包在 Windows 交叉导出，尚未在实体 Mac / M4 上运行验证。
第三方模型、贴图和录音的来源及许可见 credits/。
Godot 官方导出说明：https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html
"""


def plain_entry(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    return info


def main() -> None:
    source, destination = map(pathlib.Path, sys.argv[1:3])
    assert source.resolve() != destination.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    manifest = {"product": "Iron Embers", "version": "0.4.12", "engine": "Godot 4.7.2", "architecture": "universal (arm64 + x86_64)", "signing": "ad-hoc; not notarized", "runtime_test": "not run on macOS", "files": []}
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        assert original.testzip() is None, "Original export ZIP has a damaged member"
        for item in original.infolist():
            content = original.read(item)
            # Reuse ZipInfo to preserve Unix permissions and any symlinks.
            archive.writestr(item, content)
            if not item.is_dir():
                manifest["files"].append({"path": item.filename, "size": len(content), "sha256": hashlib.sha256(content).hexdigest()})
        extras = {"README-MAC.txt": README.encode("utf-8")}
        credits = {"THIRD_PARTY_ASSETS.md", "README.md", "CREDITS.md", "LICENSE.txt", "SOURCE_LICENSE.txt", "provenance.json", "download-manifest.json", "Publisher-README.txt"}
        asset_root = ROOT / "pc-godot/assets"
        for path in sorted(asset_root.rglob("*")):
            if path.is_file() and (path.name in credits or path.name.endswith(("-License.txt", "-Credits.txt"))):
                extras["credits/" + path.relative_to(asset_root).as_posix()] = path.read_bytes()
        for name, content in extras.items():
            archive.writestr(plain_entry(name), content)
            manifest["files"].append({"path": name, "size": len(content), "sha256": hashlib.sha256(content).hexdigest()})
        archive.writestr(plain_entry("build-manifest.json"), json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8"))
    digest = hashlib.file_digest(destination.open("rb"), "sha256").hexdigest()
    destination.with_suffix(".zip.sha256").write_text(f"{digest}  {destination.name}\n", encoding="utf-8")
    print(f"MAC_PACKAGE {destination.name}: {destination.stat().st_size} bytes, SHA256={digest}")


if __name__ == "__main__":
    main()
