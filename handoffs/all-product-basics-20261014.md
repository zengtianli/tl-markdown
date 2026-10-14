# Folio product_basics — 2026-10-15

## 范围与完成条件

仅 Folio Mac：Sources 中产品设置、命令动作与隔离自检块；scripts/accept/product_basics.py 固定验收入口；project.yaml 的 sop.product_basics 与 sop.accept.product_basics；本报告。候选 build/ 与原始验收产物随原入口生成。共享生命周期、Chapter 标准与登记引擎只读，不复制或修改；保留现有 project.yaml 产品展示差异及 sync-conflicts handoff。无安装、推送、发布、公证或更新源写入。

完成条件：当前源码候选与 build-receipt 绑定，真实离屏功能覆盖固定 14 项，执行 chapter sop accept --app folio-mac --check product_basics --json，由 Chapter 记录证据。隔离云目录往返与真实 Apple 跨设备传输分别报告。

## 进度

### 本机快装接续（用户本轮已明确授权）

- 本轮只续本机迭代安装与已装包 product_basics：build.sh、scripts/release_grade.py、scripts/verify-install.py 的本地安装块及必要固定校验、原 handoff；四项源码与前轮通过结果复用。共享引擎不写，其他修改/暂存/后台保留。
- 完成条件：同 bundle、同 Developer ID 稳定签名，当前源码构建来源与真实安装字节相符，旧包可回溯；不公证、不发更新源、不公开发布；已装包完成固定 14 项验收。
- Mini 当前仅 Apple Development 身份；已装 Folio 为 Developer ID Application: tianli Zeng (B9LJH93LA4)。Air 实际持有该 Developer ID 私钥。现有安装入口强制公证，本轮按用户授权补显式本地迭代模式，公开发行等级保持原门禁。
- 本轮代码提交 `688a027077eb2315423829020bbac6d99d0d29cd`、`860ba6c`、`61769bd6edfd814a62264735c79e969b390408be`：原 build.sh 增加 --install-local；原 release_grade.py 的稳定签名检查与公开公证检查分开，公开 check/install 仍强制公证；本地签名、原候选/签名回执链与原子安装保留旧包；verify-install.py --local 使用原 Chapter build-receipt 包裹真实安装。没有改共享引擎或登记，不用分发开关免闸。
- 1.2.1 (155) 真实候选由原 build.sh --build-only 生成，主程序 SHA256 `dbad87c0cb58da28c26faf5726a95c85f6a8d9e10ea45b505885c4dc1fd4bbd1`，源码提交 `61769bd6edfd814a62264735c79e969b390408be`；原回执 `build/accept/product_basics/local-candidate-receipt.json`，源码指纹 `fad4c48b2e3c45e0321c32318cb966155be93ecea02c4d9b0fa2f4ced352bb9b`。持证机冻结输入 `handoffs/local-install-20261015/trial.zip` SHA256 `9d5f26c00be7cd939a0ea1aa31967bfd4b3a5ec85c1a2e7e886758e1c44084c7`，`candidate-receipt.json` SHA256 `4c748b959152a849140cd0d237acbb2ec67c5c840cfdfe3b8e73129956520eda`。
- 原快装模式实际拒绝 ad-hoc 候选；`release_grade.py check /Applications/Folio.app` 只读检查原正式 1.2.1 (143) 仍通过，含 Notarized Developer ID。真实已装主程序仍为 `c3e8b00da53bf11dd5bce92f4c40f9ed81eb980ed326703f1ad7167a306e39c6`，未替换、未启动或重启，没有消耗本轮一次装机授权。
- `Tests/LocalInstallTests.py` 三项通过：复制真实 Developer ID 旧包到 build/ 的隔离目标，调用生产安装事务及真实 CLI 链接器；成功换包/保留原包、实际 CLI 链接冲突回滚、换包后验签故障注入回滚。HOME/目标均隔离，真实已装 App 字节保持不变。原日志 `build/local-install-tests.log`；回滚故障注入仅属事务测试，不冒充四项产品验收。
- 已按要求执行默认 `chapter sop accept --app folio-mac --check product_basics --json`，实际已装版因旧构建来源拒绝，退出 1；原件 `perf/acceptance/run-o_6o1ctu/product_basics.json`，完整原因「拒绝未绑定当前源码的产品：当前构建输入与装机来源不同」。没有对同输入重复验收。
- 显式选上述新候选及原回执，再执行同一固定 Chapter 入口，退出 0、passed，全部 14 项通过。原件 `perf/acceptance/run-nbdeezo_/product_basics.json`；原始 checks `perf/acceptance/product-basics-28ea860470ca4a3ea36de12d2d85d026/raw.json` SHA256 `df4e16e4c1752b5ee0af1d45e8a6db42ffa4a3db19a53f9d8259f1c02088c86e`，subject:candidate、failed:[]。这不是已装版通过，正式证据仍由原 app_sop 写入。

### 快装受阻与原队列接续

- 原 mac-pair 签名任务 `20261015-0409-folio-local-sign` 已签入原队列，冻结四个实际输入和 ZIP/签名回执两个产物，使用 --force-queue 等待，未绕互斥。发送 preflight 的完整挡因：project_has_writer（claim:chapter-task:35f32cb39e815cba9ca2d3bb984c038f，mini，owner PID 46445）；active_claim（/Users/tianli/Apps/folio/build/local-signing-product-basics-20261015 被 /Users/tianli/Apps/folio 的 Chapter · folio-mac 与两机交接声明覆盖）。本会话没有另开或释放声明。
- Air 已回传该任务的原 status：state:deferred、phase:capabilities、reason:capability_unknown_or_unavailable、missing:[agent,apple-release]，updated:2026-10-15 04:14:38。原 wait --limit 30 返回 75，「等待准入条件或产物回传，未重复执行」。Air 的只读 workers 回读 role:air、capacity:1，不能代替缺失能力准入，更不能当作签名完成。暂无签名输出、暂无安装回执；不在 SSH 会话直接签、不修改共享能力登记或引擎。
- 签名及本机安装尚未完成，交还 Chapter/原 mac-pair 队列处理环境准入。本轮当前可用安装版仍是 (143)，候选 (155) 的四项行为及必要事务验证已完成；没有公证、发布、推送、更新源或手机安装。

在本仓接续原任务（保留同一 task ID，不重发或改签合同）：

```sh
python3 /Users/tianli/mac-pair/pair.py wait 20261015-0409-folio-local-sign --limit 30
```

原队列实际返回两份产物并核双方 SHA 后，在本仓沿原入口完成已授权一次快装与已装包验收：

```sh
ditto -x -k build/local-signing-product-basics-20261015/Folio-local-signed.zip build/local-signing-product-basics-20261015/received
/Users/tianli/Dev/.venv/bin/python scripts/verify-install.py --local --signed-app build/local-signing-product-basics-20261015/received/TLMarkdown.app --candidate-receipt handoffs/local-install-20261015/candidate-receipt.json --signing-receipt build/local-signing-product-basics-20261015/signing-receipt.json
chapter sop accept --app folio-mac --check product_basics --json
```

快装入口会再次完整核原候选源码、签名回执、同身份 designated requirement、隐藏基础行为及安装字节，并保留旧程序；运行中的目标会拒绝换包并留原队列接续，不关闭用户进程。安装后需回读 perf/build-receipt.json、实际版本/签名/CLI 与后台进程，并更新本报告；当前没有声称这些后置步骤已经完成。若原任务截止后失败，按原队列新一轮接续，不重写历史合同。

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
