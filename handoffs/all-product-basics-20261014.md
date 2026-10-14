# Folio product_basics — 2026-10-15

## 范围与完成条件

仅 Folio Mac：Sources 中产品设置、命令动作与隔离自检块；scripts/accept/product_basics.py 固定验收入口；project.yaml 的 sop.product_basics 与 sop.accept.product_basics；本报告。候选 build/ 与原始验收产物随原入口生成。共享生命周期、Chapter 标准与登记引擎只读，不复制或修改；保留现有 project.yaml 产品展示差异及 sync-conflicts handoff。无安装、推送、发布、公证或更新源写入。

完成条件：当前源码候选与 build-receipt 绑定，真实离屏功能覆盖固定 14 项，执行 chapter sop accept --app folio-mac --check product_basics --json，由 Chapter 记录证据。隔离云目录往返与真实 Apple 跨设备传输分别报告。

## 进度

- 已读取固定标准、唯一要求数据和现有生命周期/原生 UI 验收入口；当前未登记 product_basics。
- 已确认现有设置、iCloud 配置同步与更新均复用总部共享实现；正在核对实际快捷键和错误恢复路径。
- 已沿总部 vendor-lifecycle.py 接入原共享更新选项/值校验及 AppShortcuts；Folio 配置窗口增加应用内重新载入快捷键开关/组合，CLI 增加 shortcuts 状态和设置。原读取磁盘与草稿保留业务复用 EditorStore.reload。
- 已补生命周期真实自检的固定 14 项检查，统一 product_basics 固定脚本支持 --app/--receipt；默认验 /Applications/Folio.app，本轮通过显式环境参数验候选。
- 无窗口 scripts/test.sh --core-only 全部通过，包含生产文件、Store、Watcher、索引/28 项图谱、真实 CLI 回归。
- 当前源码候选 1.2.1 (150) 已由原 build.sh --build-only 生成，build/accept/product_basics/build-receipt.json 由 Chapter 原 build_receipt API 环绕真实构建生成；候选未安装。
- 已执行 chapter sop accept --app folio-mac --check product_basics --json；最终退出 0、passed。源码提交后 chapter basics --app folio-mac --json 只读 fresh 回读仍为 all_passed:true、problems:[]。
- 首轮实际失败原件保留在 perf/acceptance/product-basics-3d2d97791c764d009b18f01f9026fd3d/：快捷键与更新全部通过；设置错误保留及云往返/损坏恢复/不可用回落未通过。进程全程 window_visible:false、app_active:false；生产状态保护检查通过。已增加真实响应、同步错误与实际字号诊断，并在测试基线前排空前一个重新载入操作的自动保存，使用 JSON 语义对照（仍完整比较设置、文档、草稿与最近记录）。重建后按改变的输入重新运行固定门禁，未沿同因循环。
- 第二轮诊断原件 perf/acceptance/product-basics-25d7ab0c413040429da887e5ae36d7a0/ 证明设置错误保留通过；云端字号 28 被生产范围校验拒绝（真实范围 13–26），本机字号 20 保留。测试合法远端值改为 24，关同步后的本地编辑改为 25；保留损坏云文件/目录不可用测试。快捷键偏好仅本机保存，沿原五字段阅读配置同步，不破坏 Store 迁移白名单。

## 实际结果

- 本轮源码提交：`d62c3cb1e37ba876d10a390b75bdaa3f7fa04010`。仅提交四项基础能力与必要接线/文档；project.yaml 末尾他人的产品展示登记差异仍未暂存，iOS、其他 perf 验收及后台作业保留。
- 候选 App：`build/DerivedData/Build/Products/Release/TLMarkdown.app`，bundle `cyou.tianli.TLMarkdown`，1.2.1 (150)，主程序 SHA256 `fd082644e2965c33d0bec3650ecaaa8db2e4c12554fbca2c5bf01ede01ffe531`。内嵌真实 CLI 为 1,003,920 字节。
- 原快构建试包：`build/trial/TLMarkdown-1.2.1-150-trial.zip`，SHA256 `1543f6ad0256fa6d93ed8d8227e9cb1ae29efe082352339bf020e1fbbecbb6d9`。这是 ad-hoc 候选，未安装，不是对外发行包。
- 独立原构建回执：`build/accept/product_basics/build-receipt.json`，SHA256 `05812b9aec66230961612603153dea57e2351fa58ce50072fea48ea6d101ce6d`；源码指纹 `bbe98bdf2f7c37631eb48f66ea48f187b49ae8cb057151e9c4679d427864fcf9`。构建发生于提交前的真实工作区，receipt.source.commit 如实为 `a040730f432b156b9ae1454c9d0e85c757b33114`，包含本轮源码改动；提交后再次调用原 verify_build_receipt 返回 true，未重写或伪造回执。输入为 Sources/**、CLI/**、Editor/**、Resources/**、TLMarkdown.xcodeproj/**、Info.plist、icon/**、build.sh、scripts/build-cli.sh、project.yaml。
- 正式固定门禁命令（显式选候选，脚本默认仍验已装版）：

  ```sh
  SOP_FOLIO_BASICS_APP="$PWD/build/DerivedData/Build/Products/Release/TLMarkdown.app" SOP_FOLIO_BASICS_RECEIPT="$PWD/build/accept/product_basics/build-receipt.json" chapter sop accept --app folio-mac --check product_basics --json
  ```

  最终退出 0、ok:true、product_basics.status:passed。Chapter 原件 `perf/acceptance/run-s9qdmcyu/product_basics.json`，SHA256 `4379e9dd58746d94aa5c83c8d83b709e034dadd74cf6d73b3398ae66dcb0c7e5`；`perf/delivery-evidence.json` 的 product_basics 由原 app_sop 写入 passed，本轮未手写该文件。
- 实际原始 checks：`perf/acceptance/product-basics-ad1a4cf6bbe4416183088412083a2568/raw.json`，SHA256 `5d5ed61c4db82881712ed6bf2c8cc843e7418e6ea19e8e43c3e5d9905b2b2dd2`。它绑定真正 App/CLI 和回执，不是顶层 ok 或源码 presence。
- 进程内原件：`perf/acceptance/product-basics-ad1a4cf6bbe4416183088412083a2568/lifecycle/lifecycle.json`，SHA256 `88f10f4ba2bc62412fb880fe3aad6b2f7759f8da8b2664a3804bbb355ecbd006`；78 个真实产品检查加 3 个脚本身份/清理检查，共 81 项全部 true。真实设置截图 `lifecycle/lifecycle-window.png` 沿该原目录保留。

| 必测行为 | 实际覆盖（全部通过） |
|---|---|
| settings.interaction | 离屏原生配置窗口构造/渲染，实际同步开关 target/action |
| settings.persisted_readback | 窗口接收导入、保存，新进程 bundled CLI 读回字号/宽度 |
| settings.error_preserves_data | 非法输入真实拒绝，全部会话 JSON 语义不变，原非法导入回归也通过 |
| shortcuts.action_path | 原菜单 target/action 调用 EditorStore.reload，读入磁盘正文、另存未保存内容为草稿 |
| shortcuts.disable_restore | 实际设置开关关闭/恢复 keyEquivalent，新 CLI 读回持久偏好 |
| shortcuts.conflict_or_reserved_keys | 共享适配器拒绝 ⌘Q 及已有菜单组合，原绑定不变 |
| icloud.push_pull | 原 AppConfiguration 写隔离云副本，再接收远端合法字号 24，窗口及新 CLI 一致 |
| icloud.unavailable_local_fallback | 云目录被真实不可用文件占位，明确错误，本机设置/文档/草稿保留且可读 |
| icloud.conflict_or_corrupt_recovery | 损坏云 JSON 被拒绝，两端不被覆盖；恢复原云文件后真实 reconcile 成功 |
| icloud.disable_preserves_data | 关闭后本机改字号 25 可持久保存，云字节不变，文档与未保存草稿仍在 |
| updates.check_result | 真 CLI 查隔离发行记录；原窗口同一检查业务路径以 present:false 运行并显示新版结果 |
| updates.failure_recovery | 缺失/损坏发行记录报告真实错误，恢复记录后检查成功 |
| updates.options_or_store_entry | 原共享 options 命令保存间隔/开关，新进程读回，非法间隔拒绝 |
| updates.data_preservation | 检查/options/dry-run 不替换候选、不下载包、不改会话，生产状态保护检查通过 |

## 覆盖边界与接续

- 本轮 UI 全程 `window_visible:false`、`app_active:false`，activation policy prohibited；不显示窗口、不进入 Dock、不合成输入。两个唯一临时偏好域及副本工作目录清理均为 true；只注销本轮副本的 LaunchServices 登记。
- iCloud 已覆盖本机隔离云目录经生产协调/同步代码的发送、接收和错误恢复；没有操作真实 iCloud 数据或 Apple 账户，没有声称 Apple 服务器跨设备传输已验证。快捷键绑定留本机；阅读配置仍为原五字段白名单，文档/草稿/索引不上传。
- 原无窗口核心回归通过；下载版 App 与 CLI typecheck 通过；APP_STORE + APP_LIFECYCLE_KVS 的 macOS 14 typecheck 通过；vendor-lifecycle --check 验证消费的共享源码与总部逐字节一致。新增适配器在 store/ 工程排除，保留商店编译边界；未构建/上传商店发行包。
- 未安装、未推送、未公开发布、未部署、未公证、未写真实更新源。Chapter 后续独立 install 阶段沿原入口核构建/安装来源；本轮无需要用户决定的事项，无剩余阻挡代码任务的问题。
