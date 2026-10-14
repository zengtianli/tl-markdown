# Folio 本机迭代的持证机签名段

用户已经在 Chapter 明确授权本次本机迭代快装，要求稳定 Developer ID，不用公证、不发布、不发更新源、不装 Air。Mini 已实际查询无 Developer ID 私钥；Air 实际有 Developer ID Application: tianli Zeng (B9LJH93LA4)。这里只签当前源码候选一次，不编译，不碰真实状态/账户/后台。

输入在 `/Users/tianli/Apps/folio/handoffs/local-install-20261015/`：trial.zip 与 candidate-receipt.json，均是 Mini 原 build.sh --build-only 与原 Chapter build_receipt 的实际产物。签名入口是本仓 scripts/release_grade.py 的 sign-local，先核每个源码输入 SHA、包内身份/版本/主程序/CLI/图标及原构建记录，任何不符停止，不能绕 receipt。Air 的 Git 指针已知滞后但 Sources 实际同步；这里只按签入的候选/source 文件 SHA 签同字节候选，不以 Air HEAD 重编或修改来源记录。

可写仅 `/Users/tianli/Apps/folio/build/local-signing-product-basics-20261015/`；共享资源只读。不改源码、HEAD、用户数据、已装 App、证书或共享引擎。不另开重叠声明，不释放 Chapter 声明。写前按派出者精确身份核对：

```
/Users/tianli/Dev/.venv/bin/python /Users/tianli/Dev/tools/cc-home/tools/harness/claims.py --pid 46445 --session chapter-task:35f32cb39e815cba9ca2d3bb984c038f check /Users/tianli/Apps/folio/build/local-signing-product-basics-20261015
```

在 Air 登录会话执行以下原产品入口一次（不能纯 SSH 签名，不能公证）。结果未知先读 signing-receipt.json 和签名，不重放：

```
cd /Users/tianli/Apps/folio
/Users/tianli/Dev/.venv/bin/python scripts/release_grade.py sign-local handoffs/local-install-20261015/trial.zip --receipt handoffs/local-install-20261015/candidate-receipt.json --out build/local-signing-product-basics-20261015
```

完成条件：out/Folio-local-signed.zip 和 out/signing-receipt.json 都真实存在；所有 Mach-O 为同 Developer ID、runtime、时间戳，无设备清单；receipt 绑定原候选/原回执 SHA。若签名失败或输入未同步，写完整原错误及本步骤实际结果，不放宽门禁、不复编、不安装。将回执及原 ZIP 通过原交接产物取送回 Mini；build/ 不随普通源码同步，必须沿原取送核两端实际 SHA 后才能完成。除原 mac-pair 通知外不发消息。执行预算 15 分钟。
