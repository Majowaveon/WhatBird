# Godot 开发工具

当前仓库是独立的 Godot 项目。旧 UE 工程、`.uasset` 解析器、媒体导出器和解析缓存已归档移出工作区，见 [UE 工程归档](../Docs/UE工程归档.md)。不再需要 Unreal 或 .NET SDK 来运行或编辑游戏。

## 运行

```sh
godot --path godot
```

Windows 可使用根目录 `play.bat`。美术/策划入口是 `godot/scenes/rooms/*.tscn`，操作说明见 [关卡编辑指南](../godot/关卡编辑指南.md)。

## 验证

```sh
python tools/verify_godot.py --godot godot
```

验证器负责 Godot 导入、现有集成测试和跳跃回归，日志默认位于 `.cache/godot-verification`。可用 `--logs <目录>` 指定输出位置。它会检查退出码和脚本错误，而非仅依赖 Godot 的退出码。

局部物理路线诊断：

```sh
godot --headless --path godot --script res://tests/campaign_playtest.gd
```

该脚本不是完整通关验证，顶层 `full_campaign_completed=false` 时会按设计返回 1。旧报告是历史结果，不能替代可编辑场景版本的验收。此次清理未运行游戏或测试。

## 可编辑场景生成

当前默认运行入口是 `godot/scenes/maps/testyxh1.tscn`，引用 20 个房间场景。

`godot/tools/bake_editable_map.gd` 和 `native_tiles.gd` 只使用现有 Godot 数据和媒体，不依赖已归档的 UE 源文件：

```sh
godot --headless --path godot --script res://tools/bake_editable_map.gd
```

发现总地图已存在时，生成器拒绝覆盖。**只有在明确需要丢弃/替换现有场景编辑、且已备份或提交后，才添加 `-- --overwrite`。** 日常美术和策划修改直接编辑 `.tscn`，不必重新生成。

生成器为底部有水草的原房间写入 `foreground_water_enabled` 和 `foreground_waterline` 初值，不再生成旧 `BP_WaterPlane` 装饰定位节点。日常开启或调低水面直接编辑房间根节点的 `Foreground Water` 参数，无需重新生成。

`godot/data/world.json`、`paper2d.json` 仍被启动与玩家动画使用，不能删除。

## 发布

先创建输出目录，然后执行：

```sh
godot --headless --path godot --export-release "Windows Desktop" <绝对输出路径>/WhatB.exe
```

`godot/.godot`、`godot/build` 和日志不纳入 Git。现有 Windows 导出包位于 `F:/GodotBuilds/ggj26_heron/editable-scenes`；这是本机交付位置，不是运行时依赖。
