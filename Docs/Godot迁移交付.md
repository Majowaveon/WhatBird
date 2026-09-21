# Godot 迁移交付

日期：2026-09-21。分支：`ref/godot`。本文记录迁移阶段的实现与验证；随后按要求清理了旧 UE 工程。`Content/Source/Config/.uproject`、旧构建文件和一次性提取链已归档移出工作区，恢复入口见 [UE工程归档.md](UE工程归档.md)。未创建提交或推送。

2026-09-21 追加：按设计者确认恢复「短按低跳、长按高跳、松开收住上升」。此前版本把跳跃固定为单次初速度，教程第一根木柱只能靠二次滑翔越过；这是当时的迁移遗漏。新增 `tests/jump_regression.gd`（38 项：高度随按住时长增长、上限封顶、30/120Hz 一致、松开截断、碰顶取消、不叠滑翔、不剪弹簧、变身/重生/死亡清除状态），并保留原集成 108 项与物理路线 17/17 复测通过。当前保存的 UE 源码/蓝图未见 JumpMaxHoldTime 或长按参数，该手感为设计者确认的意图恢复，参数在 `player.gd` 可调。

2026-09-21 追加企鹅测试场景与手感调整：新增可 F6 运行的 `godot/scenes/tests/penguin_ice.tscn`、`snow_playground.tscn`，不接入正式总地图。按设计者要求修正滑行帧贴地位置，增加松键滑动与反向制动惯性；从冰面滑行起跳后，保持起跳水平速度和姿势直到落地，碰墙停止，变身/死亡/重置清除状态。这是后续玩法调整，不作为原 UE 行为完全等价的声明。

## 可编辑场景更新

当前正式地图改为 `godot/scenes/maps/testyxh1.tscn`，组合 `godot/scenes/rooms/` 下的 20 个房间。60 个瓦片图采用可绘制的 `TileMapLayer` 和外部 `TileSet`，275 个机关/装饰节点已保存到场景中。门按钮使用 NodePath 关联，房间额度、解锁形态、道具数量、弹簧力度和破坏延时可在检查器中编辑。

运行时默认读取保存的场景，不用旧 JSON 覆盖编辑。保留 `--data-driven` 显式回退。F6 房间预览入口和出生点已接入。使用说明见 `godot/关卡编辑指南.md`。

**本轮按用户要求快速迁移，未运行游戏测试、画面对比或发布版烟雾检查。** 只执行资源/场景生成与构建。下面的测试数据是此前数据驱动版本的历史记录，不是本轮可编辑版本的验证结论。

## 交付入口

- Godot 4.5.1 工程：`godot/project.godot`
- 运行与开发说明：`godot/README.md`
- 本轮可编辑场景版 Windows 文件：`F:/GodotBuilds/ggj26_heron/editable-scenes/WhatB-Editable.exe`
- 本轮压缩包：`F:/GodotBuilds/ggj26_heron/editable-scenes/WhatB-Editable-Windows.zip`
- 此前数据驱动跳跃版备份：`F:/GodotBuilds/ggj26_heron/previous-jump-version/`
- 转换工具说明：`tools/README.md`
- 蓝图行为与差异：`Docs/Godot蓝图行为核对.md`

C 盘空间不足，因此 Windows 构建和 Godot 导入缓存放在 F 盘。缓存不被 Git 跟踪，工程运行不硬编码该缓存路径。运行包不需要 Godot 或 Unreal 安装。

## 实现范围

菜单所引用的正式地图 TestYxh1 已重建为 Godot 二维场景运行时：20 个房间、60 个 TileMap 实例、原始组件位置与缩放、门按钮引用、检查点、变身预算和通关入口。

媒体导出为 2,547 PNG、32 WAV、5 字体；Paper2D 转换包含 325 精灵、58 Flipbook、12 TileSet、35 TileMap、93 层和 22 玩家动画。所有媒体经过解码及 Godot 资源加载验证。

四形态、角色控制、跳跃/滑翔、游泳/冰面参数、啄击、木块、门、按钮、弹簧、上升通道、解锁/次数道具、死亡和保存形态重生、原菜单/致谢/HUD/提示、音乐音效均有独立 Godot 实现。

## 验证证据

| 项目 | 结果 | 记录 |
| --- | --- | --- |
| 媒体导出和加载 | 历史记录：2,584 文件通过 | 外部 UE 归档中的 tools/ue_export/verification_report.json |
| 可重复转换 | 历史记录：Paper2D 和蓝图规范 --check 通过 | 外部 UE 归档中的 tools/convert_paper2d.py、tools/blueprint_spec.py |
| Godot 导入与脚本 | 零脚本错误 | tools/verify_godot.py |
| 集成检查 | 108 项通过 | godot/tests/verification.json |
| 输入驱动物理目标 | 17/17 目标通过 | godot/tests/campaign_playtest.json |
| 发布版启动/落地/退出 | 20 房间，角色落地，无错误/警告 | F:/GodotBuilds/ggj26_heron/smoke.log |
| 发布版指纹 | SHA-256 与构建信息 | F:/GodotBuilds/ggj26_heron/build.json |

真实输入测试分三段：原出生点推进到 w0l2；隔离起点的鸭子区域推进到 w1l2；隔离起点的啄木鸟区域推进到 w2l3。拾取、变身、攻击、机关和换房通过物理触发完成，没有直接设置解锁或开门状态代替该测试。测试保留了两次先前路线尝试超时；最终目标均满足。

桌面窗口验证了原素材菜单、致谢、返回、进入正式关卡以及角色/背景/前景显示。桌面后台按键受到前台焦点限制，所以游戏物理操作主要由 Godot Input 驱动自动测试验证，不冒称完成了全部桌面手工操作。

## 明确边界

1. **尚未从头连续通关全部 20 房间。** 因此 campaign_playtest 的 `full_campaign_completed` 和顶层 `passed` 有意保持 false，命令退出码为 1；17/17 是所列局部物理目标，不是完整游戏验收。
2. 关卡现已保存为逐房间 `.tscn` 和 `TileMapLayer`，支持原生编辑。数据驱动版仅作显式回退。重新执行生成器会覆盖场景修改，已有美术/策划编辑须先提交或备份；本轮原生场景版本尚未经过游戏验收。
3. 原测试地图中的三维 Landscape、HLOD、天空等未作为正式玩法内容迁移。数据留存不等于全部原 UE 示例关卡可运行。
4. Substrate 水面、Niagara 变身、透视深度、后期和 MetaSound 的精确混音/包络使用 Godot 二维近似；没有逐像素/逐采样一致性承诺。前景水后续改为按房间开启的屏幕底部横向水带（镜像屏幕内容、像素波纹、渐暗和动态高光），由前景草遮挡，不再使用旧平面的透视投影；仍是二维近似而非 Substrate 复刻，不改变原有游泳水池与触发区。
5. 修复了原生水环境状态错误，按编辑器意图恢复弹簧，并保护重生后的木块免受旧计时器影响。与原保存字节码不一致的地方已单独记录。
6. 角色物理参数有原始数据依据，但 UE CharacterMovement 与 Godot CharacterBody2D 不同，完整关卡难度与手感仍需要长时间实玩验收。

结论：当前交付是可以独立运行、保留真实正式关卡和素材的 Godot 移植版本，已完成上述验证；不是占位演示，也不是“原工程全部资产与编辑器能力无损转换、完整通关已验收”的声明。
