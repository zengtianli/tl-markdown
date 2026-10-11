# Folio 产品页 · iPhone 增量构建

Mac 发行主页仍由 `python3 scripts/build-site.py --out build/site` 生成。
本轮只获准修改 `site/`，所以 iPhone 小节和素材的增量构建入口也放在这里：

```sh
cd /Users/tianli/Apps/folio
python3 site/build-iphone.py --base build/site --out build/site
```

该入口先核对已有 Mac 构建的完整白名单、各文件 SHA-256、原发行目录的 ZIP 与本地引用，
复用原构建器的校验和原子替换，只加入 `#iphone` 小节、对应样式、素材与资源事实。
Mac 正文、样式、版本、历史媒体与历史性能说明保留原字节。重复运行会替换自己的小节，
不会重复插入。完整重建 Mac 页面之后再运行本入口，才能把 iPhone 部分加入发布白名单。
原 `sop.site_build` 尚未改登记，收口任务需使用上面的增量入口准备完整站点。
Mac 安装包只指向 GitHub Release，本站不复制安装包；ZIP 校验仍使用本地原发行目录。
小节模板为 `site/iphone.html`，由这个入口挂入同一页；Mac 的 `site/index.html` 原样保留。

资源数字每次构建从 `ios/01-源程序/perf/lightweight.json` 读取；截图版本从
`site/media/iphone-capture.json` 读取。二者版本和环境分别标注，不拿新截图代替性能实测。
截图及视频可重跑脚本与原始证据见交接任务的 `output/scripts/`、`output/capture.json` 和 `work/raw/`。
