# AGENTS.md

## 项目

啥鸟?! / WhatB?! 是 Global Game Jam 2026 的 2D 动作解谜游戏，当前使用 Godot 4.5.1 和 GDScript。UE 工程、C++ 和一次性提取工具已从工作区归档移除，恢复入口见 `Docs/UE工程归档.md`。

## 入口和目录

- `godot/project.godot`：Godot 工程。
- `godot/scenes/main.tscn`：菜单和游戏入口。
- `godot/scenes/maps/testyxh1.tscn`：正式总地图。
- `godot/scenes/rooms/*.tscn`：20 个原生可编辑房间，包含 TileMapLayer 和机关节点。
- `godot/scripts/`：玩家、机关、镜头、界面和音频实现。
- `godot/resources/`：TileSet、SpriteFrames 等可编辑资源。
- `godot/assets/`：实际使用的美术、字体与音频。
- `godot/data/world.json`、`paper2d.json`：当前启动、动画索引和显式数据驱动回退仍需要，不能当 UE 残留删除。
- `Resources/`：宣传图、原截图和 PSD 源文件，不能当引擎缓存删除。
- `tools/verify_godot.py`：Godot 检查入口。

## 修改约定

- 房间布局以 `.tscn` 为准，默认运行不从旧 JSON 覆盖场景编辑。
- `godot/tools/bake_editable_map.gd` 是从已转换数据重新生成场景的工具。未经明确授权，不使用 `--overwrite` 覆盖策划或美术修改。
- 机关关联使用 NodePath，重命名或移动节点时保留有效引用。
- 使用 Godot 4.5 原生 API 和显式类型的 GDScript，沿用现有命名与格式。
- 不将 `.godot/` 导入缓存、构建产物、机器凭据或本地环境路径写入运行逻辑。
- 不提交或推送，除非用户明确要求。

## 运行

在仓库根目录运行 `godot --path godot`，或 Windows 双击 `play.bat`。F5 运行完整流程；打开单个房间后 F6 使用独立预览入口。美术/策划指南见 `godot/关卡编辑指南.md`。

## 检查

`python tools/verify_godot.py --godot godot` 运行现有集成和跳跃检查。`godot/tests/campaign_playtest.gd` 是局部物理路线测试，不代表完整通关。旧测试报告不能当成可编辑场景版本已经验收；本轮若用户要求不测试，遵从并明确记录。不要为了通过检查而覆盖或重新生成关卡。
