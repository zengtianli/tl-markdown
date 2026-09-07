# Folio 命名与质量更新

产品名来自 catalog.yaml，经构建注入 CFBundleDisplayName，UI读取Bundle。中英文README统一英文名；BundleID、数据路径、仓目录与remote保留。图标沿用字形，去TL角标。

生产原生/文件测试54项、可选预览15项通过。此轮保持已验证原生架构，不凭空重写。

构建复用 `/Users/tianli/Dev/tools/dev/lib/tools/macapp/` 的 Xcode 选择器、CodingKey检查、图标工厂。安装脚本不强杀运行实例。
