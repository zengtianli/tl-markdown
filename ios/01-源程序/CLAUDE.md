# Folio 移动文稿入口

本组件仅负责 iPhone、iPad 与 Vision 的 Files 权限、SwiftUI 入口和 WebKit 桥接；Mac 由原 Folio 组件承担，Watch 无独立有用的文稿流程。

唯一业务源为族根 `Sources/Models.swift`（DocumentIO、SessionDisk）与依赖 `IndexEngine.swift`；唯一 Markdown 编辑器为族根 `Resources/Editor`，不得复制另一套算法或渲染器。修改原 Mac 源须交其 owner。先读本 README 与 project.yaml。

`scripts/env.sh` 显式定位族根，XcodeGen 环境引用在仓外构建仍读原件。任何缓存复用须先核 Chapter lane-inputs 和 sim_lane receipt 是否同时绑定这些跨根输入；未证明时禁止声称可缓存复用。

只有 `-folio-demo` 使用虚构 fixture 与独立 Demo 状态；正常启动不注入演示。不得把生产文稿、授权书签或状态加入包/测试/推广材料。原文件只在明确保存时写，编辑仅原子写本地恢复记录；错误不得丢弃草稿或覆写外部修改。

构建和模拟器走共享串行车道。源码完成、静态检查、编译、实际 Files 操作、三条平台 UI 与性能分别留证；当前不得提前写 passed 或完整交付。未授权上传、推送、签合同、外发或安装 GUI。
