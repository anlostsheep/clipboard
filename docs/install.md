# Install Clipboard

Clipboard 当前提供的是未 notarized 的开源 beta 构建。它可以用于小范围内测，但首次启动需要你手动信任 App。

## 通过 Homebrew 安装(推荐)

```bash
brew tap anlostsheep/clipboard
brew install --cask clipboardapp
```

本 cask 在安装后通过 postflight 移除 quarantine 属性,所以即使本构建是自签名、未公证,App
也能直接打开,不会遇到"未识别开发者"的 Gatekeeper 拦截。这相当于替你自动完成首次打开的手动
信任(即绕过 Gatekeeper 对该 App 的这层校验),前提是你信任本 tap。

更新:

```bash
brew upgrade --cask clipboardapp
```

卸载:

```bash
brew uninstall --cask clipboardapp          # 仅移除 App
brew uninstall --cask --zap clipboardapp    # 同时移除本机历史与偏好
```

如果你不使用 Homebrew,可继续走下面的直接下载方式(首次打开仍需手动信任)。

## 下载发布包

从 GitHub Release 下载同一版本的两个文件：

- `ClipboardApp-vX.Y.Z-macos.zip`
- `ClipboardApp-vX.Y.Z-macos.zip.sha256`

先校验压缩包完整性：

```bash
shasum -a 256 -c ClipboardApp-vX.Y.Z-macos.zip.sha256
```

期望输出：

```text
ClipboardApp-vX.Y.Z-macos.zip: OK
```

## 安装

解压 zip，然后把 `ClipboardApp.app` 移动到 `/Applications`：

```bash
unzip ClipboardApp-vX.Y.Z-macos.zip
mv ClipboardApp.app /Applications/
```

也可以在 Finder 中解压并拖入 Applications。

## 首次打开

因为当前发布包不是 Apple Developer ID 签名和 notarized，macOS 可能会阻止第一次打开。

推荐方式：

1. 在 Finder 中打开 `/Applications`。
2. 右键 `ClipboardApp.app`。
3. 选择 Open。
4. 在系统确认框中再次选择 Open。

如果仍然被阻止，打开 System Settings -> Privacy & Security，在安全提示区域选择 Open Anyway。

终端方式：

```bash
xattr -dr com.apple.quarantine /Applications/ClipboardApp.app
open /Applications/ClipboardApp.app
```

## 授权辅助功能

Clipboard 的自动粘贴能力需要 Accessibility 权限。首次启动后，按系统提示打开：

```text
System Settings -> Privacy & Security -> Accessibility
```

启用 `ClipboardApp.app`。如果只使用复制到剪贴板、不自动粘贴，也可以暂时不授权。

如果你是在源码仓库中验证授权状态，可以运行：

```bash
swift run ClipboardManualProbe accessibility
```

授权后期望输出：

```text
accessibility: authorized
```

## 更新

安装新版本前退出 Clipboard，然后替换 `/Applications/ClipboardApp.app`。

只要发布者使用相同 bundle identifier 和稳定自签名身份，macOS 通常会比 ad-hoc 构建更稳定地保留辅助功能权限。如果权限状态异常，先在 Accessibility 中移除旧条目，再重新添加新 App。

## 卸载

退出 Clipboard 后删除 App：

```bash
rm -rf /Applications/ClipboardApp.app
```

如果要同时删除本机历史和偏好设置：

```bash
rm -rf "$HOME/Library/Application Support/com.local.clipboard-manager"
defaults delete com.local.clipboard-manager 2>/dev/null || true
```

如果发布者覆盖过 `BUNDLE_IDENTIFIER`，本机数据目录也会跟随实际 bundle id 变化。

## 当前限制

- 当前发布包不是 Apple notarized app；直接下载 zip 时无法完全消除 Gatekeeper 首次打开提示(通过 Homebrew 安装会自动去掉 quarantine，不受此影响)。
- 自动粘贴依赖 Accessibility 权限。
- "登录时自动启动"（SMAppService 登录项）在 ad-hoc 签名的开发构建下不可靠：每次重新构建签名身份都会变化，登录项注册可能失效或在系统设置中产生重复条目。请使用发布包或稳定自签名构建（`Authority=ClipboardApp Local Code Signing`）使用与验证该功能；设置页在 ad-hoc 构建下也会显示相应提示。
- 剪贴板历史保存在本机，可能包含敏感信息。反馈问题时不要上传真实数据库、payload 文件或包含敏感内容的截图。
