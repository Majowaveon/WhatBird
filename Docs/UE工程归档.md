# UE 工程残留清理与恢复

清理日期：2026-09-21。当前分支 `ref/godot`，清理前 Git HEAD 为 `801d91a`。当前 Godot 的运行、编辑和场景生成不依赖旧 UE 工程。

## 归档位置

本机仓库外备份目录：

`F:/ProjectBackups/ggj26_heron-ue-before-cleanup-20260921-162058/`

- `unreal-source-and-migration.zip`：实际 UE 二进制资产、源码、配置、构建文件、专用文档、提取工具及解析缓存。
- `manifest.json`：全部文件相对路径、大小、SHA-256、清理标记及归档状态。

归档包含 7,693 个文件，压缩后 194,123,225 字节；其中 7,669 个文件已从工作区移除，共 765,887,937 字节（约 730.4 MiB）。其余是为恢复原工程保留的上下文副本，例如旧 README、开发指引与原美术资源。

归档写入后逐文件解压读取并核验 SHA-256；删除前再次核对源文件未改变。备份含实际 `.uasset/.umap` 数据，不只依赖 Git LFS 指针。Git 历史与 `.git/lfs` 未改动。

## 从工作区移除

- `Content/`、`Source/`、`Config/`。
- `.uproject`、对应 IDE 配置和工程缩略图。
- `.clangd`、`.clang-format`、clangd 初始化脚本及编译数据库。
- 旧 `justfile`、PaperZD 调试精灵生成文件。
- UE 专用能力、蓝图、关卡配置说明；通用设计草稿 `Docs/XBDraft.md` 保留。
- `tools/uasset_dump/`、`tools/ue_export/`、`assetlib.py`、`convert_world.py`、`convert_paper2d.py`、`blueprint_spec.py`。
- `.cache/asset-json/`、`.cache/ue-tools/` 及旧 Python 缓存。

没有删除 `Resources/`：其中含原宣传图、游戏截图和 `credits.psd` 美术源文件，不应当作引擎残留。也没有修改当前 Godot 玩法、场景、动画、音频、水面改动或启动器。

## 继续保留

- 整个 `godot/`，包含可编辑场景、原生资源和场景生成器。
- `godot/data/world.json` 与 `paper2d.json`：当前启动和玩家动画仍会读取。
- `godot/data/blueprint_spec.json` 与 `Docs/Godot蓝图行为核对.md`：迁移证据，里面的 UE 路径是历史引用，不是当前运行依赖。
- `tools/verify_godot.py`、Godot 检查记录及当前启动脚本。
- `Resources/`、`Docs/XBDraft.md`、Git 历史与本地工具配置。

## 恢复

需要重新打开原 UE 工程或重新从 `.uasset` 提取时，将 ZIP **解压到新的独立目录**。归档保留原相对路径，旧工程入口是其中的 `ggj26_heron.uproject`。运行旧解析器需要恢复相同目录结构，并准备 UE5.7、PaperZD、.NET 等原工具链。

不要将归档直接覆盖到当前 Godot 工作区，否则会恢复旧入口、README 和开发规则。不要仅为日常关卡编辑恢复 UE 工程。

本机归档不在 Git 中；团队若也需要保留原 UE 工程，应另行保存这份归档或保留可用的原远端 LFS 资产。当前清理没有创建提交、推送、远端删除或历史改写。

此次只完成文件/依赖核对和备份完整性校验，遵循此前要求未运行游戏或测试。旧测试报告不代表本轮场景版本已验收。
