---
name: game-development-knowledge
description: Develop, extend, debug and validate playable games using reusable production lessons for engine projects, 3D assets, combat AI, input, terrain, progression, performance and native releases. Use for practical game development and game-development knowledge maintenance; skip unrelated app work and general gaming discussion.
---

# 游戏开发知识库

这是一份跨项目、按需读取的工程经验库。源于实际游戏开发，侧重避免反复踩坑；不是引擎 API 手册，也不代替当前项目代码、用户选择和本次验证。

## 使用路径

先识别目标平台、当前引擎和要改变的玩家行为。已有项目先看工作区状态与项目入口，只加载下列相关主题，通常一至两篇。不要为使用知识库而重建项目或改造整个架构。

| 当前工作 | 按需阅读 |
| --- | --- |
| 新项目、引擎选型、接手旧项目、节省上下文 | [工作流与架构](references/workflow.md) |
| 下载模型、骨骼动画、PBR、植被和视觉质量 | [资产与渲染](references/assets.md) |
| 射击反馈、声音、敌人行为、镜头和手柄 | [战斗与输入](references/combat-input.md) |
| 丘陵河流、导航、天气、波次、奖励和存档 | [世界与进度](references/world-progression.md) |
| 卡顿、回归测试、截图与性能证据 | [性能与验证](references/performance-validation.md) |
| Windows/Mac 打包、发布、传文件 | [发布与交付](references/release.md) |
| 保存新经验、修正旧结论、后续任务交接 | [维护与交接](references/maintenance.md) |

先复现问题或定义可观察的验收行为，再做最小相关改动。验证应覆盖真实生产调用链；画面变化必须看实际渲染，成品变化必须检查实际产物。

本库不携带某个仓库的提交、发布、账号或系统修改权限。不要把历史数值、工具路径、一次机器故障、匿名提交身份或平台偏好推广成所有项目的默认要求。具体引擎/Blender/SDK API、许可证及平台要求按目标版本核验。

本库的经验边界与更新方法见维护文档；历史测量只能作为排查线索。无需为了阅读文档运行游戏测试。
