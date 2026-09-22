# 企鹅与雪地测试场景

在 Godot 编辑器打开下面的 `.tscn`，按 **F6** 单独运行。两个场景都通过现有房间预览入口启动，默认使用企鹅，四种形态全部解锁、变身次数不限。它们没有接入正式总地图，F5 仍运行原来的游戏。

| 场景 | 可以测试的内容 |
| --- | --- |
| `penguin_ice.tscn` | 企鹅站立、行走、跳跃、下落、滑行五组动画与 NPC 企鹅；普通地面—蓝色冰面—普通地面的速度变化；右侧台阶的起跳、落地。 |
| `snow_playground.tscn` | 雪地地形、冰块、冰雪弹簧、高台按钮、三段雪地门和终点 NPC。踩弹簧后继续向右登上高台，碰到按钮开门，再通过右侧冰面。 |

在仓库根目录也可以直接启动：

```sh
godot --path godot res://scenes/tests/penguin_ice.tscn
godot --path godot res://scenes/tests/snow_playground.tscn
```

- **A / D 或左右方向键**：移动。
- **空格 / W / 上方向键**：跳跃，长按跳得更高。
- **1 / 2 / 3 / 4**：夜鹭 / 绿头鸭 / 企鹅 / 啄木鸟。
- **R**：回到起点，复原按钮与门。
- **Esc**：暂停。

底部显示当前形态、地面/空中状态、运动状态和水平速度。普通地面速度上限为 200，企鹅在蓝色冰面上逐渐加速到 300。松键后会继续滑动并缓慢停下；反向输入先减速，再向反方向加速。可以在冰面上切换夜鹭和企鹅，对比手感。

滑行中起跳（或滑出冰面边缘）会保留起跳时的水平速度和滑行动画，空中松键、反向输入不会改变这次腾空的水平速度。碰墙会停止水平移动；落回冰面继续滑行，落到普通地面恢复普通控制。变身、死亡或 R 重置会清除腾空滑行状态。普通地面起跳仍使用原来的跳跃动画和空中控制。

`player.gd` 中 `ice_acceleration = 450`、`ice_braking_deceleration = 60`、`ice_ground_friction = 0.5` 控制冰面加速、松键减速和摩擦；这是按本轮滑行需求调整的手感，不是原 UE 参数的等价复刻。

## 编辑

- `Terrain` 下的 TileMapLayer 保存实际布局，可以直接绘制。复用现有 `w0l1` TileSet 的 `tile_6.png` 图集（source 1）；`SnowCover` 只画雪沿，不参与碰撞。修改共享 TileSet 会影响引用它的正式房间；需要改变图块或碰撞定义时先另存资源。
- `Actors/IceZone/Trigger/CollisionShape2D` 决定冰面效果范围。改变蓝色冰块长度时，同时调整这个区域。
- 雪地场景的 `SnowButton` 与 `SnowDoorBottom/Middle/Top` 通过 NodePath 关联，移动或改名后要保留有效引用。
- `PlayerStart` 是出生点；根节点的 `camera_bounds` 是镜头范围。
- `Decoration` 下有说明文字和动画展示；`TestHUD` 显示操作和运行状态。只有这两个测试场景使用 `test_scene_hud.gd`。
- 这两个场景没有通关结算或跳转，便于反复试跑。终点 NPC 是展示节点。

## 霜羽山口战役雪地章节

主菜单「开始」进入总地图 `scenes/maps/testyxh1.tscn`，森林啄木鸟段结束后从 `w2l7` 的上山弹簧进入雪地。雪地没有独立选关入口，包含两个原生房间：

- `w3l1`：与企鹅 NPC 相遇，通过实际接触解锁企鹅形态；右侧安全冰面用于试滑。
- `w3l2`：利用企鹅滑行速度激活冰封蝴蝶，再越过裂隙触碰第二只蝴蝶，打开 AND 雪门并通关。

每段都有检查点，R 会恢复该段机关并保留永久形态解锁。正式开局只有夜鹭，企鹅必须在相遇后获得。编辑时可分别打开 `w3l1.tscn`、`w3l2.tscn` 按 F6；预览仍按既有规则全解锁。

```sh
godot --headless --path godot --script res://tests/frostpass_playtest.gd
```

回归脚本使用 Godot headless 和 Input actions，不操作桌面窗口。从明确的森林末段局部起点验证上山衔接、NPC 解锁、企鹅速度条件、双机关开门、检查点复原、战役重开及 F6；它不代表从开场跑完全部 22 房间。

场景回归检查（需要先完成 Godot 项目导入）：

```sh
godot --headless --path godot --script res://tests/test_scenes_regression.gd
godot --headless --path godot --script res://tests/penguin_regression.gd
```
