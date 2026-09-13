# Switch 1 0.1.0 自检

2026-09-13。分支 `codex/switch1-edition`，基于 PC 0.4.13。新增独立 `switch-godot/`，PC、Android、网页源代码未改动。

## 实现范围

- Godot 3.5.1 社区 Switch 运行时 / GLES2，1280×720，目标帧率上限 30；此数值是配置，不是主机实测性能。
- 原三款可操控坦克模型及关节、四种武器、地雷、脉冲、第三人称/俯视、双摇杆与按钮。
- 复用七章关卡定义及敌人职业参数，每关 Boss；重新适配楼宇、丘陵、树林、河流、桥梁与通行。
- 五种原始巨怪模型、无尽波次、接近/蓄力攻击、倒下、奖励、三类六级升级。
- 原录制炮声、爆炸、真人无线电、三首 BGM、引擎声、流体图集爆炸、概率殉爆、雨雪与履带痕迹。
- 本次是原生 3D 适配版；GLES2 场景与有限特效替代 PC Forward+ 的部分渲染功能，不声称 PC 功能与画面逐项等效。

## 当前证据

- `final-check.log`：43 项通过，覆盖模型关节、关卡数量、桥梁/水域、地雷与脉冲、Boss 生成及死亡、连续 1→4 波、奖励不重复、升级购买与真实 A 键菜单事件。
- `final-smoke.log`：6 项通过，真实物理循环验证炮口→炮弹→敌人伤害、76 米接敌射击、敌车追击、玩家按钮开火、巨怪移动和命中。
- `package-smoke.log`：以最终导出的同一份 PCK 重新运行上述 6 项。并非复用源项目结果。
- 四张桌面运行时截图检查了菜单、城市第三人称、丘陵俯视与巨怪场景；发现并修复纹理夹取导致的地表长条拉伸。
- 实际 NRO 原生段与锁定模板一致，AArch64 入口、ASET、NACP 所有 16 个语言槽、图标格式、PCK 全部资源 MD5 校验通过。
- 音频验证使用 Dummy 驱动：已验证事件、资源和播放调用，未把它当作主机扬声器试听。
- 主机 MTP/HOME 安装状态以 `outputs/switch/*receipt.json` 的实际回执和用户明确反馈为准，不把静态校验当成安装或真机启动。
- 本次已完成游戏 33 个文件、HOME 助手 4 个文件的 MTP 全量读回，逐文件 SHA256 一致。游戏位于 `sdmc:/switch/IronEmbers/`，助手位于 `sdmc:/switch/IronEmbersHome/`。HOME 入口安装与启动仍等待主机反馈。

## 产物

`outputs/switch/IronEmbers/IronEmbers.nro`：45,159,776 字节。

`outputs/switch/IronEmbers/IronEmbers.pck`：572,584,416 字节；SHA256 `225f74d5314b36dea3d1b19a665ae76d528f59e62a9a6e70dacefd7575257239`。

HOME 助手单独位于 `outputs/switch-home/IronEmbersHome/`，目标固定为 `sdmc:/switch/IronEmbers/IronEmbers.nro`，TitleID `01cdcf1458845000`。助手检查游戏和 PCK 存在；A 安装到 SD 的 HOME 入口，Y 保存 NSP，B 退出。助手本身不代表入口已安装。

## 仍需主机验证

完整 Application 模式启动、主机帧时间/内存、实物 Joy-Con/Pro Controller、扬声器、存档重载、HOME/休眠恢复与退出。固定社区后端未证明完整发送连接与焦点事件，脚本事件测试只覆盖游戏响应部分。

导入阶段旧编辑器报告退出时 ObjectDB 泄漏警告；游戏自检与成品运行无脚本错误。该编辑器退出警告不能泛化成游戏运行内存泄漏结论。
