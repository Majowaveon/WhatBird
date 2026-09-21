# Godot 蓝图行为核对

> 历史审阅记录：下文的 `Source/`、UE 资产、`.cache/asset-json` 和解析器已在清理时归档移出工作区。`godot/data/blueprint_spec.json` 保留作为行为证据；原文件恢复入口见 [UE工程归档.md](UE工程归档.md)。这些历史路径不是当前运行依赖，文中旧转换命令应在恢复出的独立 UE 目录使用。

核对日期：2026-09-21。依据是仓库 C++、`.cache/asset-json` 中的 UAssetAPI 导出、UE 5.7 原生组件构造默认值，以及当时的 Godot 脚本。没有启动原 UE 游戏、没有执行 GUI 或 Godot 测试。本任务只负责规范与源码核对，运行验证由主迁移任务负责。

`tools/blueprint_spec.py --write` 生成 `godot/data/blueprint_spec.json`；`--check` 在内存重建并比较已保存结果。规范保存 24 个重点蓝图、61 个函数的指令及 VM 偏移，全部计算长度与 `ScriptBytecodeSize` 一致。偏移验证证明解码长度一致，不证明事件一定被调用，也不证明 Godot 运行效果完全相同。规范中的人工语义结论均给出函数、偏移或源码定位，不把编辑器节点名称当成可执行行为。

## 已确认的规则

| 主题 | UE 来源与精确语义 | Godot 源码核对 |
| --- | --- | --- |
| 菜单开始 | `WBP_Menu.ExecuteUbergraph_WBP_Menu` 入口 116，偏移 236 打开 `/Game/Map/TestYxh1.TestYxh1`。 | 世界默认地图为 `Map/TestYxh1`；菜单最终运行验证另行负责。 |
| 初始速度 | `BP_Player` CDO：MoveSpeed=200、JumpSpeed=200、SuperJumpSpeed=390、ChangeLevelJumpSpeed=700。Construction 偏移 22/51 设置 MaxWalkSpeed，103/132 设置 JumpZVelocity。组件模板的 300/210 会被覆盖，不能用作初始玩法值。 | `world.gd` setup 与 `player.gd` 默认值采用 200/200。 |
| 死亡 | `BP_Player` Die 入口 2218：移除 IMC_Default → StopMovementImmediately → LaunchCharacter(DieDirection, true, false) → Capsule collision=0 → 单次 Rebirth timer 1.5 秒。DieDirection=(100,300,100)，XY override=true、Z override=false。 | `world.gd` 用冻结输入、禁用碰撞和二维 death_velocity=(100,-100) 近似该流程，1.5 秒后重生；UE 的 Y 轴离开画面深度分量没有二维等价物。 |
| 重生与重置 | Rebirth 入口 2469：恢复 IMC_Default、碰撞 3，再进入 reset 1790。Reset 顺序：GM.ResetAllInteractables → StopMovementImmediately → 移动到 GM spawn position → SwitchAbility(saved form) → ResetHenshinCount。SwitchAbility 本身不扣次数、不检查解锁。 | `_respawn` 重置按钮、门、木块和补次数道具，恢复存档形态与次数。另有 checkpoint_room 恢复，这是 Godot 额外房间/相机策略；不能说 reset 蓝图显式存储或切换了房间。 |
| 初始出生与检查点 | `GM_Base` BeginPlay 入口 180 保存当前 Pawn 位置，SpawnBirdType=0。`BP_CheckPoint` overlap 入口 398 保存检查点自身位置和 PlayerState.GetCurrentAbilityType。 | 保存 object.global_position 和 player.bird，未将检查点强制指定为默认鸟。 |
| 房间切换 | `BP_ChangeSubLevelVolume` 比较新旧 tag，仅不等时执行 ChangeSubLevelByName(tag,-1)。不存在强制变形。原生 GM 根据房间配置恢复该房间次数。 | `change_room` 同名时返回、更新额度，保持当前形态。相机采用二维缩放和正弦缓动，UE 则是透视 FOV 与 SmoothStep，属于近似。 |
| 上升通道 | `BP_UpVolume` 偏移 943 严格比较 `velocity.Z > abs(velocity.X)`，满足才调用 ChangeLevelJump。后者 LaunchCharacter((0,0,700),false,true)。 | `-velocity.y > abs(velocity.x)` 才 bounce(700)，保留横向速度。 |
| 门 | 每 Tick 对所有 BPButtonRef.IsButtonTriggered 求 AND；空数组结果为 true。Unlock 锁存 IsUnlocked、隐藏 render、Box collision=0；Reset 显示 render、Box collision=3、IsUnlocked=false。 | `_update_doors`、open_door、reset_object 保留 AND/空数组/开门锁存规则。 |
| 按钮 | overlap 锁存 IsButtonTriggered=true。虽然数组名是 `BPDoorRef（废弃，请勿调用）`，编译字节码仍遍历它直接 Unlock；按钮 Reset 将状态设 false。 | 两套规则同时保留：门的 BPButtonRef AND 与按钮的旧 BPDoorRef 直接开门。Godot 只处理玩家碰撞；原按钮编译 handler 没有 BP_Player cast，这一点不能称完全等价。 |

碰撞数字使用 UE 的枚举：0=NoCollision，1=QueryOnly，3=QueryAndPhysics；Godot 的 layer/mask 数字不是这些枚举的直接复制。

## 拾取物

`BP_BaseItem.ReceiveActorBeginOverlap` 先 cast BP_Player，成功才调用虚函数 `Apply(ItemFunction)`。Base Apply 先对 RenderComponent 执行 SetHiddenInGame(true,true)，再禁用 TriggerBoxComponent 碰撞。它不 DestroyActor。Base Reset 调用父 Reset，然后重新显示 RenderComponent 并将触发盒恢复为 QueryOnly=1。

- **解锁鸟**：`BP_ItemUnlockBird.Apply(ItemFunction)` 调用 Base Apply，然后 PlayerState.UnlockBird(BirdType)。C++ `HeronPlayerState.h` 的 UnlockBird 仅 `UnlockedBirds.Add(NewBird)`，不调用 SwitchAbility、不扣次数、不启动变形动画。编译 Apply 路径没有拾取专用动画。拾取前播放 NPC idle flipbook 是外观默认值，不能算收集动画。`BP_ItemUnlockBird.Reset` 是空函数，不调用父 Reset，所以已拾取解锁物不会随死亡/重置再出现。
- **补次数**：`BP_ItemAddHenshinTimes` 默认 `添加次数=1`。Apply 调父逻辑并 AddHenshinCount；继承 BaseItem.Reset，所以可重新出现。C++ 遇到 RemainingTransformCount<0（无限）直接返回，否则加上 Count；允许超过 MaxTransformCount，源码没有对负结果做下界截断。
- `TestYxh1` 放置了 Mallard、Woodpecker 解锁物，以及一个 +1 道具。形态来自实例 BirdType，不应根据子类名称猜测；子类 CDO 没有序列化 BirdType 覆盖，也不是强制变形证据。
- 当前 Godot 的 unlock_bird 不变形，重置白名单不包含解锁物、包含补次数道具，核心规则一致。`player.gd` 对加次数结果额外 clamp 到零；对当前地图 +1 无影响，但任意负 Count 时与 C++ 不同。

## 木块、弹簧与碰撞

木块 `ReceiveBeginPlay` 入口 104 执行 Array_Random，候选为 FB_Wood0、FB_Wood1、FB_Wood4、FB_Wood5，然后 SetFlipbook。只在首次 BeginPlay 随机，Reset 不再随机。当前 `world_object.gd` setup 从 FlipbookList 随机一次并保存 base_flipbook，符合此规则。

木块破坏并非立即移除实体碰撞。`DestructThis` 先设置 HasTriggeredBroken=true 并隐藏 render，然后设置 1.0 秒单次 timer；DelayDestroy 入口 38 才调用 SetEnabled(false)，关闭 Box 碰撞。Reset 调 SetEnabled(true)：显示、碰撞 3、HasTriggeredBroken=false；编译 Reset 没有取消此前 timer。最终 Godot 实现已保留 1 秒延时关闭碰撞，并增加重置代数校验：Reset 后旧计时器不再影响新状态。这项保护是有意修复，区别于原蓝图没有取消旧计时器的行为。

弹簧须区分可执行导出与编辑器意图：

- BP_Spring 的 ExecuteUbergraph、ReceiveBeginPlay、ReceiveActorBeginOverlap 都只有 `Return Nothing; EndOfScript`，每个 3 字节。针叶/冰雪 Actor 子类没有自己的字节码。不是函数重名覆盖导致的误读。
- 编辑器节点中可见 BP_Player cast、SuperJump、PlaySoundAtLocation、RandomFloatInRange、K2_PlayAnimationOverride(AnimS)。这支持「弹跳装置」设计意图，但此次没有解码隐藏在 Extras 中的全部 pin 连线/数值。Godot overlap 触发 390 跳跃、播放 pop/音效是意图恢复，不能声称源编译 overlap 已这样执行。0.15 秒 cooldown 是 Godot 防重复触发措施，没有已确认的源参数。
- 普通/冰雪动画蓝图初始状态为 state0=idle，AS_Idle_* 循环，rate=1、start=0，带 DefaultSlot override。针叶动画蓝图不同：SelectByBool 默认 false，FalseAnimation 指向 PlaySequence_1 的 idle；未带 `_1` 的 PlaySequence 是 pop，而且没有 RegisteredOverrideSlots。不能简单选择第一个 PlaySequence 作为 idle。
- 三类 idle 都是 2 帧、1 FPS，总周期 2 秒；pop 都是 7 帧、12 FPS，原片时长 7/12≈0.583333 秒。当前 Godot 目录 aliases 均指向正确 idle，play_spring 按帧时长求回退时间，已避免固定 0.35 秒截断。针叶 pop 的单次覆盖依然属于 Godot 意图恢复。
- `ABaseInteractable.cpp` 将 TriggerBox half-extent 设为 (10,10,10)，无碰撞 render；BP_Spring trigger scale=(0.75,0.75,0.75)，因此 actor scale=1 时二维触发尺寸为 15×15。render 相对 UE 位置 (-2,0,5)、scale=0.5。实例覆写可能不同，应读取规范的 placed_geometry，而非给所有实例硬编码 15。

水体的 BoxExtent 未序列化并不表示没有碰撞。UE5.7 `BoxComponent.cpp:22` 原生默认 half-extent=(32,32,32)，`ShapeComponent.cpp:48` 默认 profile=OverlapAllDynamic。BP_WaterTriggerVolume CDO 只增加 Water tag，Box 模板 scale=0.5；关卡实例自己的 scale 覆盖模板，不能再乘一次 0.5。当前转换器补齐 32，world_object 对 root transform 只应用一次，几何规则匹配。

`TestYxh1` 的 11 个 WaterTrigger 都是深度很薄的区域，Godot Y=-UE Z。下表是未额外扩张的盒尺寸，不包括玩家胶囊。

| 实例标签后缀 | 中心 (Godot X,Y) | 宽×高 |
| --- | --- | --- |
| w0l4 | (1656,-67) | 76.8×19.2 |
| w0l5 | (1661,303) | 320×19.2 |
| w0l6 | (1187,360) | 64×19.2 |
| w1l1 | (1168,760) | 166.4×19.2 |
| w1l2 | (1277,1143) | 352×19.2 |
| w1l3 | (552,1145) | 57.6×19.2 |
| w1l3_1 | (688,1033) | 70.4×19.2 |
| w1l4 | (232,1144) | 121.6×19.2 |
| w1l5 | (280,1544) | 121.6×19.2 |
| w1l56 | (-17,1416) | 134.4×19.2 |
| w1l6 | (-288,1496) | 70.4×19.2 |

该地图另有 30 个弹簧（12 普通、18 针叶）和 1 个 BP_WaterPlane。WaterPlane 使用引擎 Plane mesh + M_PixelWater，显式 NoCollision；它是水外观，不是 WaterTrigger 的尺寸来源。Godot 初版曾按原 Plane 的位置、宽度和深度投影为二维水面。现已按画面需求移除此梯形投影，改成房间配置的屏幕底部横向水带，只在有底部水草的房间启用。水面处于玩家与前景草之间，用 BackBufferCopy 截屏镜像到水带，叠加像素波纹、渐暗与动态像素高光；不增加游泳触发区域。Substrate 的物理反射、折射与光照仍未移植，属于明确的二维近似。

水的玩法来自原生代码：HeronPlayer 遇到 Water tag 先设 bIsInWater=true，非 Mallard 死亡，Mallard 调 EnterWater。但 MallardAbility.EnterWater 在 bIsInWater=true 时提前返回；EndOverlap 先清 flag 后 ExitWater 又提前返回。BP_WaterTriggerVolume 与 BP_MallardAbility 都没有字节码覆盖修复这些条件。Godot 通过环境计数推导水中速度/重力/摩擦并在退出时恢复，属于明确的原生 bug 修复；不得描述为原 UE 正常执行了相同代码路径。

## 后续企鹅滑行调整

2026-09-21 按设计者要求调整 Godot 企鹅滑行：针对滑行帧相对站立帧底部多出的 10 像素留白修正轴心；冰面采用独立加速度 450、松键减速度 60 和摩擦 0.5，反向输入先消耗原方向速度。滑行中起跳或离开平台后，保留实际起跳水平速度与滑行动画直到落地，碰墙停止水平动量，变身/死亡/重置清除状态。普通地面及其他形态保留原移动逻辑。这些为本轮手感需求，不声称来自已核对的 UE 原始行为。`godot/tests/penguin_regression.gd` 覆盖贴地、惯性、反向、腾空保持和状态清理；正式地图没有增加企鹅解锁点。

## 音频与变形特效

MS_BGM 的根对象在 UAssetAPI 中是 RawExport；helper.props 对它得到空对象不能代表「没有参数」。解码器对原始 base64 进行有边界的 UE5.7 属性读取，恢复 Nodes、Edges、BGMList 和节点 InputLiterals，并校验数组/结构体完整消耗声明长度。没有把所有原始 float 当成当前节点覆写。

已确认 BGMList 包含且序列化顺序为：

1. `832628__rotlily__calm-ambient-piano-loop`
2. `761294__rotlily__melancholic-piano-loop`

播放通过 Random Get，列表顺序不是实际播放顺序。OnPlay 与上一首 Wave Player.OnFinished 的触发反馈进入 Trigger Any，再驱动 RandomGet.Next；RandomGet.OnNext 同时启动 Wave Player 和 ADSR Attack。WavePlayer.OnNearlyFinished 驱动 ADSR Release，OutEnvelope 控制立体声 Mixer Gain0。ADSR 唯一显式节点覆写是 Attack Time=0.5 秒；没有显式 Delay 节点。不能把 0.5 秒称为开始前静音延迟，也不能从依赖类声明中的默认 literal 推断全部实际 ADSR 参数。

当前 audio.gd 已使用相同两首音频并在结束后再选曲，加入 0.5 秒 volume_db 淡入；它仍不是 MetaSound 包络等价实现：dB 插值不同于源包络，OnNearlyFinished release、原生未连接引脚默认值、共享随机状态/重复策略、精确混音增益未核对完成。不要写成「所有 MetaSound 已精确复刻」。

MS_Ambient 的可读图确认 AmbentGrass、AmbientBird 分别输入两个 Wave Player，两个 Loop=true，混合输出。Godot 两轨并行播放并在 finished 后重播，内容匹配，但无缝采样级循环未验证。MS_SFXLand 的 Wave Player Start Time=0.015 秒是音频内部起播位置，不是事件延时；audio.gd 已对 SFXLand 使用 play(0.015)。MS_Glide 的两个波形、Stop 和 ADSR 路由保存在 JSON，Godot 直接播放/停止样本仍是近似。

`BP_HeronPlayerController_Child.PlayHenshinVFX` 入口 10 已确认：读取 Pawn.GetActorLocation，在该位置 SpawnSystemAtLocation(NS_Henshin)，rotation=0、scale=1、autoDestroy=true、autoActivate=true、pool=0、preCull=true。NewBirdType 被保存但后续不读取；没有额外形态规则或按鸟种改色逻辑。

当前 `HeronPlayerController.h/.cpp` 没有 PlayHenshinVFX 声明或调用；SwitchBird 仅检查解锁/非同形态/额度，再 SwitchAbility 与 AddHenshinCount(-1)。检索现有玩法蓝图导出也只在 child asset 本身发现该名称。因此「此事件存在」成立，「每次 C++ 变形一定触发该事件」未获证实。若在 Godot 加上变形 VFX，应标成恢复已有资源的设计意图。声音则由 BirdAbilityBase.OnEnterAbility 播放，SwitchAbility 在初始化/恢复形态时也会走这条路径，不能仅从用户变形输入推断所有播放场景。

NS_Henshin 有两个 enabled、world-space、GPUComputeSim emitter（Minimal、Minimal001），都用 M_HenshinSprite；固定剔除 bounds 为 X/Z ±100、Y ±1。该 bounds 不是粒子发射半径。UAssetAPI 中 NiagaraVariableWithOffset 的 Value 为空，虽然 ParameterData 有字节，缺少可可靠绑定的名字/offset；本次没有声称精确粒子半径、寿命、颜色和 burst 数。最终 Godot 在用户成功变形时显示短暂像素粒子环，参数是迁移版的视觉近似，未冒充从 Niagara 精确提取的半径、寿命或颜色。

## 本次验证与边界

已完成 `--write` 和 `--check`，结果一致；24 个蓝图、61 个函数的 VM 长度全部匹配。原始资产 SHA-256 与函数所属 export/owner 保存在 JSON，可追溯；此工具不会编辑 UE 源码或 Godot 玩法脚本，也不生成 Python bytecode 缓存。

本审计针对阅读时的源码快照，主迁移任务仍可能继续修改。重点快照 SHA-256 前 12 位：world.gd=`7aebc70fe2c4a`，world_object.gd=`4242a63e0355`，player.gd=`905f027e6dce`，audio.gd=`0352a1d5ed99`。这些值用于辨认本次核对所指版本，不表示最新版本的测试结论。

仍需主任务验收：木块延时碰撞、死亡动画与三维离屏分量近似、复活房间策略、水面材质、弹簧意图恢复、完整 MetaSound 包络/增益，以及变形 VFX 调用可达性和视觉近似。没有执行重复的游戏测试，也没有宣称关卡完整通关或像素/音频逐帧一致。
