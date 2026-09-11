# macOS 0.4.8 测试包

本包包含完整六关战役与无尽防守，面向 MacBook Pro M4 使用。
Godot 官方 Universal 2 模板同时包含 arm64 / x86_64；M4 原生执行 arm64，无需 Rosetta。

文件：`outputs/pc-godot/Iron-Embers-macOS-Universal-0.4.8.zip`

- 大小：217,542,209 字节。
- SHA-256：`7239267c05e339dec0833155a43146b1dc6569e829969d6661e6e7dc614f6d73`。
- 解压后：`IronEmbers.app`、中文 `README-MAC.txt`、`credits/`、逐文件哈希清单。
- 将整个 ZIP 传到 Mac 后再解压，拖动 app 到“应用程序”并打开。
- 使用 Godot 内置 ad-hoc 签名，未作 Apple 开发者公证。首次被拦截时，尝试打开一次，然后在“系统设置 → 隐私与安全性 → 仍要打开”中允许该应用；[Apple 官方说明](https://support.apple.com/en-us/102445)。

## 构建与检查

```powershell
pwsh -NoProfile -File scripts/build-pc-macos.ps1
```

构建复用已缓存并校验的 Godot 4.7.2 官方编辑器与模板；导出模板归档 SHA-512 与 `macos.zip` SHA-256 均固定在脚本中。
开启 ASTC 纹理导入以支持单独 ARM64 导出配置，同时保留 BPTC/S3TC 数据。本次 Universal 导出按 Godot 官方策略选用 BPTC/S3TC；M4 支持这些 BC 压缩纹理。保留 Forward+，Apple Silicon 使用 Metal。
直接导出 ZIP 保留 Unix 执行权限；附加说明与许可位于应用包之外，不修改已签名的 bundle。
[Godot 官方 macOS 导出说明](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html)。

只读检查命令：

```text
python scripts/verify-macos-package.py outputs/pc-godot/Iron-Embers-macOS-Universal-0.4.8.zip --require-extras
```

本次验证通过：ZIP CRC、0755 执行权限、Info.plist、版本、双架构 Mach-O、82,402 个签名代码页、20 个特殊哈希槽、9 个签名资源和30项系统库依赖。游戏资源包为184,424,848字节。
实际导出的 PCK 另在 Windows Godot 宿主下启动主场景并进入战役，输出 `IRON_EMBERS_SMOKE_PASS`。
日志：`work/mac-package-verify.json`、`work/mac-package-content-smoke.log`；导出过程见 `work/build-macos-universal-0.4.8.log`。
初次检查将 Godot SHA256/SHA1 双 CodeDirectory 误判为重复；检查器已按 Apple XNU 的有效结构分别验证两种摘要，最终包校验通过。

**未在实体 Mac / M4 上运行，也未执行 macOS 的 codesign / Gatekeeper 原生验证。** 上述为构建主机上的包结构、嵌入式签名哈希及游戏资源检查，不代表 M4 实机性能测试。
