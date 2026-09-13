# 钢铁余烬 · Switch 1 0.1.0

基于原 PC 游戏素材与关卡定义适配的原生 3D 自制程序。运行时为 Stary2001 Godot 3.5.1 Switch 分支 / GLES2；PC Godot 4.7 工程保持独立。此包需已经具备 homebrew 运行环境的 Switch 1。

## 运行

完整复制本目录到 `sdmc:/switch/IronEmbers/`。`IronEmbers.nro` 和 `IronEmbers.pck` 必须放在一起。

从完整 Application 模式 hbmenu 启动“钢铁余烬 · Switch”：在 HOME 里按住右手柄顶部的小肩键 R，同时按 A 启动一款已有游戏；若出现用户选择，继续按住 R 并按 A，进入 hbmenu 后松开 R。不要用只有受限内存的相册 applet 模式。

本包是 hbmenu 应用；复制到 SD 不会自动注册 HOME 图标。MTP 读回哈希只验证传输，实际启动、声音、帧率和休眠恢复需在主机测试。

## 操作

| 操作 | Switch | PC 预览 |
| --- | --- | --- |
| 转向 / 行驶 | 左摇杆 | A/D、W/S |
| 瞄准 | 右摇杆 | 鼠标 |
| 发射 | ZR | 空格 / 鼠标左键 |
| 切换武器 | L / R | 1 / 2 |
| 地雷 / 脉冲 | Y / ZL | Q / E |
| 第三人称 / 俯视 | X | C |
| 切换 BGM | − | M |
| 暂停 | + | Esc |
| 菜单选择 / 确认 | 方向键 / A | 方向键 / Enter |

七章战役包含清敌、占点、摧毁目标和每关 Boss；主菜单也可直接进入青岚河谷。无尽模式防守北方基地，击杀巨怪获得资金，每波后进入整备界面，选“出发”继续下一波。火力、装填、装甲各六级。地雷只由玩家放置，脉冲排雷并短暂瘫痪近敌。

## 构建

使用 Python 3 标准库和工具锁定文件中的社区编辑器及 Switch 模板。先把两个原始发行归档放在一个目录，再执行：

```powershell
python -X utf8 switch-godot/tools/stage.py --tool-cache <归档目录>
python -X utf8 switch-godot/tools/build.py
pwsh -NoProfile -File switch-godot/tools/install-mtp.ps1
```

归档来源与 SHA256 见 `tools/toolchain-lock.json`。构建复制 `pc-godot/assets/` 的源素材到 `work/switch-project/`，将三份玩法数据转换为 Godot 3 语法；不把整个 Godot 4 场景直接交给旧引擎。中间目录、导入缓存与成品分别在 `work/`、`outputs/switch/`，不提交。

画面适配采用 GLES2 材质、有限数量的流体动画爆炸、空间批次树木和合并楼宇网格；不是 PC Forward+ 渲染器的逐项等效移植。车辆模型、三首音乐、真人无线电和五种巨怪模型沿用有署名的 PC 素材；署名见随包 `credits/`。

新输入适配覆盖固定运行时的真实按钮映射，并同时消费输入事件。上游运行时的设备断连/系统焦点通知是否完整，需主机验证；脚本单元验证不能证明主机已经发送这些通知。
