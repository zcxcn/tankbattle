# PC 游戏开发手册

这是按需查阅的经验库，不要求每个任务通读。自动入口为根目录 `AGENTS.md`。
基于截至 0.4.9 的实际工作；代码、当前用户要求及本次验证结果优先于历史记录。

## 1. 小范围定位，避免重复探索

- 开始读状态、目标函数、对应测试；跨模块时再扩展。脚本超过几百行，用 `rg -n` 加 `Get-Content | Select-Object -Skip … -First …`。
- 项目不是一个网页外壳：PC 使用 Godot / Forward+ / Jolt；网页版是另一条实现路线。PC 游戏请求默认不跑 npm、Android 或网页部署。
- 先定复现方式和验收结果，避免只更改数值后宣称修复。例如“第一波后没怪”要分别检查游戏状态、活体、待生成队列、生成阻塞和波次时间。
- 独立只读检查可并行；修改、导入、导出有依赖，按顺序执行。不要让多个 editor/import/export 同时写同一 `.godot/` 缓存。
- 本地下载、转换、渲染工具只按已知目录查找。路径失效才扩大搜索；不要每次重新调研引擎或搜全盘。
- 进展说明报告新发现、剩余问题，不重复计划。保留详细日志在文件，工具输出只要错误、计数和产物摘要。

## 2. 已验证的本机工具

以下路径相对仓库根；`work/` 被忽略，换机器/工作树时先检查是否存在。

| 用途 | 入口 |
| --- | --- |
| Godot 编辑器/测试 | `work/tools/godot-4.7.2/editor/Godot_v4.7.2-stable_win64_console.exe` |
| 导出模板 | `work/tools/godot-4.7.2/templates/` |
| Blender 便携版 | `work/asset-review/smooth-prototype/tools/blender-5.2.1-windows-x64/blender.exe` |
| 7z 解包 | `work/tools/7zr.exe` |
| Python | `$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe` |

Godot 与模板的固定版本和哈希在 `scripts/build-pc-godot.ps1`、`scripts/build-pc-macos.ps1` 中。
无需再次下载已有的完整导出模板包，也不要把工具路径中的本机用户名写进产物元数据。

## 3. 测试选择与执行

从现有测试中选择覆盖行为的最小集合，不机械地为每次文案/材质颜色修改新增测试。

| 改动 | 首选测试（均在 `pc-godot/tests/`） |
| --- | --- |
| 巨兽网格、骨骼、伤害、倒地 | `giant_monster_test.tscn`；视觉 `siege_beasts_visual_test.tscn` |
| 连续波次、清场、巨型基地碰撞 | `endless_waves_test.tscn` |
| 无尽完整玩法、武器、奖励、模式切换 | `endless_mode_test.tscn` |
| 商店和存档隔离 | `endless_progression_test.tscn`、`endless_ui_test.tscn` |
| 摄像机/远程鼠标/手柄 | `camera_regression_test.gd`（`--script`）、`remote_mouse_test.tscn`、`gamepad_regression_test.gd`（`--script`） |
| 炮弹、仰角、命中 | `ballistics_test.tscn`、`barrel_elevation_test.tscn`、`hit_feedback_test.tscn` |
| 炮声/受击声音 | `weapon_audio_test.tscn`、`impact_audio_test.tscn` |
| 地形与实际通行 | `river_terrain_test.tscn`、`world_traversal_test.tscn`、`river_navigation_test.tscn` |

示例：在仓库根运行生产调度器连续波次检查。

```powershell
$taskGodot = 'work/tools/godot-4.7.2/editor/Godot_v4.7.2-stable_win64_console.exe'
New-Item -ItemType Directory -Force -Path work | Out-Null
& $taskGodot --headless --fixed-fps 60 --path pc-godot res://tests/endless_waves_test.tscn -- --test > work/endless-waves.log 2>&1
$taskExit = $LASTEXITCODE
Get-Content work/endless-waves.log | Select-Object -Last 12
if ($taskExit -ne 0) { throw "Godot test failed: $taskExit" }
```

- `--fixed-fps 60` 适合已有的确定性物理场景；不要盲目加到依赖真实音频时间的所有测试。
- `pacing_regression_test.tscn` 沿用构建脚本的实时模式；快进会让其 120 秒模拟超时在真实音频退出前触发。敌车射程用 `enemy_range_test.tscn` 验证实际 AI 发射/命中，而不只断言配置数字。
- 读失败标记和最终计数；工具返回 0 或“打开场景成功”不代表所有断言通过。完整测试名单以构建脚本为准。
- 测试使用独立 `SaveService._directory`，通常为 `user://tests/<名称>_<进程号>`。不覆盖玩家真实存档和设置；需要共享进程时保存并恢复原值。
- 退出沿用 `tests/test_shutdown.gd`，让真实音频线程回收后退出，避免未清理播放对象。
- 波次回归要让生产调度器自己推进，不用直接 `begin_wave()` 或强改时间来“证明”续波正确。另测 backlog、人口上限、入口被占、暂停及重试。
- 小范围逻辑通过后做视觉验证，模型/玩法稳定后再跑一次完整构建。最终又改了姿态，则复查骨骼、倒地、相关碰撞及截图，重导出即可；不重跑无关的整套音频/天气测试。
- 文档修改只检查链接、路径、差异和事实；不要构建二百多 MB 的游戏来验证 Markdown。

## 4. 模型工作流与已踩过的坑

现有可复用转换入口：`scripts/pc048_convert_monster.py`（FBX 巨尸）、
`scripts/convert-siege-beasts.py`（旧 Blender 岩魔/爬行兽）、`scripts/inspect-monster-blend.py`（只打印结构）。

1. 先找许可明确、有原作网格、UV、法线和骨骼的素材。仅换色/缩放不算新的原始模型。
2. 下载到 `work/`，记录源链接、许可和哈希；查作者修订说明。Forest Monster 曾替换非商业树皮，当前转换明确使用新版包内 `texture/tree.png`。
3. 下载的 `.blend` 使用 `--background --disable-autoexec`。不执行素材附带的任意 Python；本地自编转换脚本可用 `--python` 指定。
4. 先检查对象、材质、图片、骨骼和动作名称。旧文件可能处于 Pose 模式、对象被隐藏；转换前回到 Object 模式，解除目标对象/集合隐藏。
5. 去掉相机、灯光和编辑控制网格，保留变形骨架和蒙皮。只移除“非游戏网格”，不要误删仍需要的 IK 约束；保留原动作时可能需要烘焙其约束。
6. 把旧材质显式转为 glTF PBR；保留纹理和法线，确认 roughness/gloss 含义。多网格、多 surface 按各自原始材质乘 tint，不能用一个覆盖材质抹掉全部细节。
7. 新资产统一脚底零点、1 米标称高度、朝 -Z。Blender -Y 经 glTF 变成 +Z，需要明确转换；原巨尸有独立历史比例/朝向，不能一刀切。
8. 保留蒙皮绑定矩阵；新增尾巴/背甲要有权重，尾骨先设正确旋转模式再打关键帧。按局部骨骼轴计算手臂姿态，不能靠同一个欧拉角猜所有骨架方向。
9. Blender 的 ACTIVE_ACTIONS 导出可能把 Walk 改名为 Animation；转换脚本明确保留语义名称。测试检查实际骨骼变化，而不只是 AnimationPlayer 存在。
   Blender 5 的旧动作还需显式指定 `animation_data.action_slot`；蒙皮导出前应用原作 Mirror 修改器，否则可能只剩半边身体。见 `scripts/convert-colossal-monsters.py`。
10. 导入后用实际 Godot 渲染检查正面、侧面、坦克参照、楼高参照及倒地。确认脚底高度、法线、动作、标签、贴图、相机视野和全部尸体网格淡出。

截图要等待本轮捕获完成标记，并核对文件时间，避免看见同名的旧截图。性能测量不要与
全量测试/转换并行；加载和编译时的瞬时 FPS 不能代表稳定游戏帧率。

Godot 导入 GLB 可能在资源目录提取图片；这些图片及其 `.import` 是实际依赖，不能误当缓存删掉。
`.godot/` 是可再生缓存，`.uid` / `.import` 则应沿用仓库规则保留。
头部、大厦级模型别只把 `height` 数值放大：连带检查碰撞半径、生成净空、近战距离、
相机仰角、脚步频率、震动上限、尸体边界和回收配额。

## 5. 无尽模式必须保持的关系

- `game.gd` 管模式，`endless_director.gd` 管波次、名单与奖励；怪物负责运动、攻击和死亡。战役存档与无尽记录隔离。
- 清场 = 待入场为零且活体为空。尸体不阻止续波；仍有待入场增援时不要误判清场。清场通知/倒计时只设置一次，不能每帧重置而永远等不完。
- 保留未清场情况下的定时增援、人口/尸体/待生成队列上限，以及入口尝试其他位置的逻辑。
- 奖励与结算只能发生一次；已摧毁、无效、非成员或结束状态的敌人不能重复发奖。
- 大体型碰墙时根节点尚未到门前；攻击起始和命中检查都必须使用相容的体型距离，且保留遮挡、蓄力与躲避窗口。
- 贴地估计不要遍历所有编辑骨骼，使用真实皮肤权重引用的变形骨骼。长尾侧倒比整身前翻更合适；手臂展开过大会把尸体撑高。
- 变形骨骼索引按共享 mesh/skin 缓存并在开战前预热；不要在击杀帧逐顶点扫描权重。尸体位置仍取死亡时真实姿势。性能对比用相同探针与条件，区分单条 CPU 路径耗时和整局帧率。
- 第一波回归必须包含正常 `game._process`/HUD、清场后暂停恢复、入口全部占用；只手动调用 director 的快进测试不能覆盖所有用户流程。新行为见 `endless_recovery_test.tscn`。
- 暂停冻结波次、怪物、前摇、晕眩、倒地与回收。换模式/重试必须清理活体、尸体、升级和旧 director。
- 参数以当前代码为准；0.4.9 的人数、身高、波次和验证结果在对应自检文档，不在这里重复维护。

## 6. 发布与 Mac 导出

顺序：定向检查 → 实际视觉检查 → 稳定后完整构建 → 最终产物检查 → 文档 → 提交。
不要在模型还不断变化时启动发布，然后又重打整包；导入、截图和产物必须对应最后版本。

- Windows：`scripts/build-pc-godot.ps1` 已涵盖官方工具哈希、测试、导出、版本、credits、manifest、ZIP 和 EXE 启动。最终重导出 `-SkipTests` 仅用于已有相应测试证据时。
- 成品在 `outputs/pc-godot/windows-x86_64/`；运行 `IronEmbers.exe` 必须保留旁边的 `.pck` 和署名文件。
- Mac：运行 `scripts/build-pc-macos.ps1`，沿用 `macOS Universal`。现有官方模板是 Universal 2，不要仅改为 arm64：导出器会寻找并不存在的同名 arm64 模板，而不会自动裁剪 universal。
- M4 原生执行 arm64，包内同时保留 x86_64。不需要安装 Godot 或 Rosetta。渲染/纹理支持以已验证配置和实际导出内容为准，不凭 ARM64 名称推断格式不支持。
- `package-macos.py` 保留原 ZIP 的 Unix 模式和符号链接，只在签名 app 外添加 README/credits/manifest。不要先在 Windows 解压应用再用普通压缩工具重打，避免丢失执行位。
- `verify-macos-package.py` 验证双架构、CodeDirectory、资源哈希和执行位；同一签名可包含不同摘要算法的 CodeDirectory，不能把所有同槽条目一律当错误。
- Windows 上的静态验证或读取 Mac PCK 不能证明 M4/Gatekeeper 实机成功；明确说明尚未完成实机运行。未公证时走包内 Apple 官方“仍要打开”流程，不关闭全局安全检查。
- 升版本时局部查找 `export_presets.cfg`、UI 页脚、启动日志、Windows/Mac 构建与 smoke/verify/package 脚本、README；历史自检保持原版本。
- 新素材署名必须进入 Windows 的 credits 清单；Mac 打包按规定文件名收集。不可只放源仓库而遗漏成品。
- `outputs/` 不在 Git 中。不要把本地 ZIP 链接说成 GitHub 公共下载链接，也不要顺手发布 Release 或部署网页。
- 匿名提交后核实 author/committer；推送结束后再核对远端 SHA，上传大素材尚未完成时不报告已同步。

## 7. 仅在传文件/远程桌面任务时查阅

- 本机 RDP 曾有 listener `fDisableCdm=1`；经用户批准的 UAC 修改后读回为 0，但之后仍未出现映射。
- `\\tsclient\` 不存在，只能说明当前会话没有可访问的映射；不能单凭这一点断言 Mac 未配置。注册表存储值为 0 也不能独自证明服务已重新加载或重定向握手成功。
- 分别检查 Windows 策略/服务/会话、Mac Windows App 的 Folders/Redirect folders 与访问权限。已经重复重连失败，就收集客户端设置或采用用户选定的其他传输路径，不循环给同一条建议。
- 文本剪贴板可用不代表文件剪贴板可用；把文件放入 Windows FileDrop 剪贴板不等于已经传到 Mac。
- 游戏 ZIP 应先完整传到 Mac 再解压。只有目标文件存在或用户确认收到，才报告传输成功。
- 不为普通游戏开发改系统远程桌面策略；需要 UAC 时说明具体设置和权限原因，不自行重启远程桌面服务、注销或重启机器打断用户会话。

## 8. 维护这份经验库

- 新经验只保存会重复用到的决策、失败原因和入口。日志、截图、每版哈希和通过数放对应自检文档。
- 修正已被证伪的推断，不把助手以前的断言自动当事实。区分“配置已写入”“测试通过”“实际试玩”“已上传”。
- 根 `AGENTS.md` 保持短小；细节在本文件按主题更新，避免每次任务自动加载越来越长的历史。
