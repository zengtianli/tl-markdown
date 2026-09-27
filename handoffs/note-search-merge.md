# 全部笔记检索并入 Folio（2026-09-27）

- 用户决定：TL MdIndex 的全盘 Markdown 检索并入 Folio 后退役 MdIndex，减少一个 App。
- 实现：`Sources/Models.swift`「Note search」只读访问 md-index 的 FTS5 索引（`doc`/`doc_fts`，trigram），<3 字自动 LIKE 回退，`%`/`_` 按字面；`NoteSearchModel`（ViewModel.swift）后台队列、200 ms 防抖、新查询打断旧查询；`NotesPanel`（ContentView.swift）为侧栏第三个标签「搜索」，⌘⇧F 呼出，点命中行 `EditorStore.openNote` 打开并按 UTF-16 行偏移跳转。索引路径默认 `~/Apps/md-index/indexer/data/md_index.db`，可用 `MDINDEX_DB` 或设置覆盖。
- 验证：`Tests/NoteSearchTests.swift` 8 项（真实 SQLite trigram 夹具：FTS/LIKE 分流、真实行号、通配符字面、缺索引如实报错、不写索引、UTF-16 行偏移）；core 测试、主编辑器集成与 LaunchServices 打开测试全过；真实索引 4540 篇：「水库」LIKE 0.13 s，「汛限水位」FTS 0.17 s。离屏渲染核对侧栏布局（三段选择器改为「最近/大纲/搜索」避免撑宽侧栏）。未做：安装版窗口内实际点击跳转的 CUA 验收。
- 顺带修复：双语命名后 `build.sh` 用 display_name 作安装名导致打包断言失败，改用 `name_en`（安装名仍为 Folio.app）。
- 装机 1.1.0 (37)。未推送、未更新产品主页与发行包；公开发行需另行授权。
- MdIndex：`/Applications/TL MdIndex.app` 移至 `~/.Trash/mdindex-retire-20260927/`；源码仓移至 `~/Apps/_archive/mdindex-mac`（lifecycle archived）；hotkeys.yaml、products.yaml（retired）、md-index/README 已改。索引引擎 indexer 保留（kb、workspace、atlas、8791 图谱服务依赖）。
