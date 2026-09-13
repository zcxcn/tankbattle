# Switch 1 安装与运行

电脑已准备两个配套目录：

- `switch/IronEmbers/`：游戏本体，NRO 与 PCK 必须放在一起。
- `switch/IronEmbersHome/`：仅为此游戏生成 HOME 入口的助手。

通过 DBI MTP 把它们放到 SD 的同名路径。本仓库的安装脚本会检查已有目录并读回核验，避免覆盖未知游戏或存档。

## 在 Switch 上完成 HOME 安装

1. 退出 DBI，返回 HOME。
2. 按住右手柄顶部标有 R 的小肩键，同时按 A 启动一款已经安装的游戏；出现用户选择时继续按住 R，按 A 选用户。进入 hbmenu 后松开 R。
3. 打开 **IronEmbers HOME Setup**，按 **A** 安装。
4. 显示成功后返回 HOME，从 **钢铁余烬** 图标启动游戏。

若助手显示错误，记录错误内容；Y 可保存 `sdmc:/IronEmbers-HOME.nsp`，随后可用 DBI 安装。不要在未看到结果时反复执行同一步。MTP 无法替用户按主机按键，电脑传输成功不代表 HOME 注册成功。

游戏 NRO/PCK 不能在安装入口后删除。存档单独写入 `sdmc:/switch/IronEmbersSwitch/`，更新本体时保留该目录。

HOME 助手基于 [switch-nsp-forwarder 0.0.8](https://github.com/TooTallNate/switch-nsp-forwarder/releases/tag/0.0.8)，保持原生段与上游一致，固定本游戏路径及独立 TitleID，不读取或导出主机密钥文件。工具与素材许可随包保留。
