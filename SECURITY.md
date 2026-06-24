# Security Policy

Clipboard 会处理剪贴板历史，其中可能包含密码、token、私有文档、截图、文件路径和私人消息。所有 bug report、日志、数据库和截图都应默认视为可能包含敏感信息。

## 支持版本

项目当前处于 early beta。正式 release 流程建立前，安全修复以默认分支为准。

## 报告安全问题

不要在公开 issue 中粘贴敏感剪贴板内容、数据库文件、payload 文件、证书、keychain 或私有日志。

目前请通过私有渠道联系项目维护者。如果暂时没有私有渠道，可以先创建一个不包含秘密信息的最小公开 issue，只描述受影响区域，再通过其他方式沟通细节。

报告时请包含：

- macOS 版本和 CPU 架构。
- App 构建来源：本地 debug、ad-hoc 包、稳定自签名包。
- 是否已授予辅助功能权限。
- 使用非敏感示例剪贴板内容的最小复现步骤。
- 期望行为和实际行为。

不要包含：

- `~/Library/Application Support/<bundle-id>/clipboard.sqlite`
- `~/Library/Application Support/<bundle-id>/payloads/` 下的文件
- `~/Library/Application Support/<bundle-id>/imports/reports/` 下的导入报告
- 私有签名 keychain、证书或密码
- 包含真实剪贴板内容的截图或日志

## 本地数据

Clipboard 的历史记录保存在本机：

- 元数据：`~/Library/Application Support/<bundle-id>/clipboard.sqlite`
- Payload 文件：`~/Library/Application Support/<bundle-id>/payloads/`
- 导入报告：`~/Library/Application Support/<bundle-id>/imports/reports/`
- 偏好设置：macOS `UserDefaults`

当前代码库不使用网络 API。如果未来加入网络、同步、崩溃上报、分析统计或自动更新，必须在 `README.md` 中说明，并按隐私敏感改动进行 review。

## 隐私控制

当前控制项包括：

- 暂停采集。
- 忽略下一次复制。
- 忽略 Universal Clipboard 记录。
- 忽略配置的 pasteboard types。
- 忽略配置的来源 App bundle ids。
- 默认过滤常见 concealed / transient pasteboard types。

这些控制项能降低暴露风险，但不会让剪贴板历史适合公开分享。提交任何 issue 或 PR 附件前，请先审查其中的数据。

## 签名材料

自签名 beta 包使用本地签名身份。不要提交生成的证书、keychain、私钥、密码或导出的签名材料。

本地签名流程见 [docs/release-signing.md](docs/release-signing.md)。
