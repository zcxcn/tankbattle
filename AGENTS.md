# Tankbattle 开发约定

## 范围与协作

- 默认开发 `pc-godot/` 的原生 PC 游戏；Android 不动，网页版及 GitHub Pages 只在明确要求时改动。Mac 导出按任务需要执行，不把一次临时导出变成每次必做事项。
- 使用中文简明沟通。用户重视实际画面、真实声效、可玩的节奏和成品；“继续”承接未完成目标。已授权的常规实现、验证、提交不重复确认。
- 默认单 agent；不为节省时间自行开子 agent。先完成相关工作，再交付可核验结果。
- 仓库已有提交、推送授权；后续明确限制优先。提交身份固定为 `Iron Embers Build <build@iron-embers.invalid>`，author/committer 均设置，不使用真人身份或伪装成具体他人。第三方素材作者署名必须保留。

## 最短工作路径

1. 先 `git status --short`，保留非本任务改动；核实分支，PC 历史分支为 `codex/pc-edition`，不要盲目切换。
2. 用下表定位模块；先 `rg -n` 找函数，再局部读取。不要递归扫描整个用户目录、整篇打印大文件或重读所有历史自检。
3. 修改前明确触发条件与预期行为；沿用生产代码和既有测试入口。新模型先导入、检查动作并实际渲染，再做完整发布。
4. 迭代只跑相关测试。跨系统发布在改动稳定后跑一次完整构建，构建期间不再编辑源码；此后有修改，只复查受影响部分，再重新导出。不要用旧测试结果证明未测的新改动。
5. 核验最终产物、更新相关自检说明，再匿名提交、推送并用 `git ls-remote` 确认。代码已推送不等于 ZIP 已上传。

## 代码导航（路径相对仓库根）

| 工作 | 入口 |
| --- | --- |
| 游戏状态、战役/无尽切换、伤害、UI 快照 | `pc-godot/scripts/game.gd` |
| 坦克、炮弹、爆炸、地雷、残骸 | `pc-godot/actors/`；武器参数在 `pc-godot/data/combat_loadout.gd` |
| 无尽波次、怪物、商店 | `pc-godot/scripts/endless_director.gd`、`pc-godot/actors/giant_monster.gd`、`pc-godot/data/endless_upgrades.gd` |
| 镜头/远程鼠标、手柄、界面 | `pc-godot/scripts/battle_camera_rig.gd`、`gamepad_input.gd`（同目录）、`pc-godot/ui/game_ui.gd` |
| 地形、城市、天气、履带 | `pc-godot/scenes/missions/`、`pc-godot/scripts/{river_terrain,city_architecture,battlefield_weather,track_marks}.gd` |
| 声音、设置、存档 | `pc-godot/autoload/{audio_service,settings_service,save_service}.gd` |

## 工具与验证入口

- Godot console：`work/tools/godot-4.7.2/editor/Godot_v4.7.2-stable_win64_console.exe`。版本和官方哈希以构建脚本为准；先检查现有工具，不重复下载或升级引擎。
- Windows 完整构建：`pwsh -NoProfile -File scripts/build-pc-godot.ps1`；相关测试已完成后的重导出加 `-SkipTests`，仍保留成品启动检查。
- Mac 构建：`pwsh -NoProfile -File scripts/build-pc-macos.ps1`。
- 日志放 `work/`，默认只读取末尾、计数和错误。PowerShell 在其他命令前保存/检查外部程序的 `$LASTEXITCODE`；Godot/Blender 还要检查日志中的脚本错误及预期完成标记。
- `work/`、`outputs/`、`pc-godot/.godot/` 不提交；源资产、必要的 `.import` 和 `.uid`、署名应提交。绝不删除整个用户目录或仓库；打包清理仅限构建脚本核实的输出路径。

## 按需资料

- [开发手册](docs/pc-realistic/DEVELOPMENT_PLAYBOOK.md)：只读任务对应小节，含测试选型、建模坑、发布检查与传文件诊断。
- 当前沉淀基线为 0.4.9；实际版本以 `pc-godot/export_presets.cfg` 为准。[0.4.9 自检](docs/pc-realistic/SELF_CHECK_0.4.9.md)记录巨兽/续波，[Mac 导出说明](docs/pc-realistic/MACOS_EXPORT_0.4.8.md)记录跨平台流程。
- 不把历史通过数、截图 FPS 或静态签名验证当成当前改动、性能或 M4 实机运行的证明。文档类改动检查路径、差异即可，无需重建游戏。
