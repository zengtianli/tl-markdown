# CLAUDE.md — Folio

SwiftUI macOS app（脚手架生成自 macapp_scaffold）。产品范围与实际架构先读本项目
`README.md` 和 `catalog.yaml`；上级 `~/Apps/mac/CLAUDE.md` 是舰队架构约定。
默认能全 Swift 就全 Swift；生成的 Python demo 只是连通性示例，不是强制运行时依赖。
只有实际依赖重型 Python 库或总部外部消费者时，才保留相应后端通路。

新需求先读 playbook：`~/Dev/tools/configs/playbooks/native-console-app.md`（决策树 + 全部坑单）。

## 构建

项目目录为 `/Users/tianli/Apps/mac/folio`。Bundle ID、内部构建 target 与用户数据目录保持兼容，避免丢失默认文件关联和已有会话。

```bash
cd ~/Apps/mac/folio
./build.sh          # 构建 + 装 /Applications（Xcode 自动挑，见下）
```

**别自己写 `DEVELOPER_DIR=/Applications/Xcode.app/...`。** 本机 `xcode-select` 指向
CommandLineTools（`xcodebuild` 在那儿直接报 requires Xcode），而盘上可能同时躺着好几个
Xcode、其中一些已被当前 macOS 判为不支持。该用哪个由总部 SSOT 现算：

```bash
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh && xcode_env_use macosx
# build.sh 里已经内置这一行；想单独看它挑了谁：
python3 /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.py list
```

## 硬约束（与范本 ssot-console 一致）

- `build.sh` 对签名后的真实 .app 自动运行 `scripts/test_file_open.py`：通过 LaunchServices 验证冷启动、运行中多文件、Unicode/空格、两种扩展名和重复打开；读取隔离会话中真实文档内容。失败不安装。发布时再通过 CUA 核对安装版窗口内容；组件测试或 open 返回 0 不能替代。

- bundle id `cyou.tianli.TLMarkdown`；部署目标见 pbxproj `MACOSX_DEPLOYMENT_TARGET`。
- **若使用外部 Python 后端**：stdout 纯 JSON；`gui-*` 子命令一律 exit 0，失败 = `{"ok": false, "error": "人话"}`；
  字段 snake_case（Swift 侧 `.convertFromSnakeCase` 自动映射）。改 `Models.swift` = 同步改后端输出。
- 需要共享 Python 后端时放 `~/Dev/tools/dev/lib/tools/` 下（平台-子公司模型），按实际接口接入；
  全 Swift 应用移除 demo，核心读写用生产代码测试，不额外维持占位后端。
- 新增源文件要动 pbxproj 4 处（PBXBuildFile / PBXFileReference / Sources group / Sources build
  phase）—— 小增量优先 append 进现有 5 文件，MARK 分节。
- UI 坑单（语义色零硬编码 / 禁 `fixedSize(h:false,v:true)` / detail 根 minWidth 600 / 并发 drain /
  GUI PATH 注入）已以代码+注释固化在 Sources/ 里，删注释前先读 playbook。
