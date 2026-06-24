# 分发信任链(免费路 / Homebrew 主导)设计

## 背景

Clipboard 的核心剪贴板管理体验在高频工作流上已经达到 Maccy 级别的对齐,并在隐私控制、
导入保真度、Universal Clipboard 处理和存储健壮性上超过 Maccy。当前阻碍把它推荐给普通
macOS 用户的差距不在功能本身,而在*采用与信任门槛*:没有一键安装、没有自动更新方案,
直接下载又会撞上 Gatekeeper 摩擦。

本设计是更大目标"公开发布比肩 Maccy"的第一个子项目。它只聚焦分发信任链,且走**免费路**
(不购买付费的 Apple Developer Program)。有两个上游产品决策已经定下,并框定本设计:

1. **目标受众**:面向陌生用户的开源公开发布,让人能装上即用,主要通过 Homebrew 推荐。
2. **更新机制**:Homebrew 主导,**应用内零网络调用**。保留项目"无任何网络调用"的隐私
   属性。更新通过 `brew upgrade --cask` 流转。不引入 Sparkle、不做 appcast、不做应用内
   更新检查。

## 范围

交付一条可复现、低摩擦的分发链,使得:

- 新用户用一条干净的 Homebrew 命令安装,App 打开时**不需要**右键 Open 那一套 Gatekeeper
  操作(Homebrew 安装 cask 时会去掉 quarantine 属性)。
- 更新通过 `brew upgrade --cask clipboard` 流转。
- 发布可复现、可版本化,且来自单一事实源。
- 保留稳定自签名签名,使得辅助功能(Accessibility)权限在版本更新间保持稳定
  (自动粘贴功能依赖它)。
- 直接下载(非 Homebrew)的用户仍保留一条有文档、可用的安装路径。

## 目标

1. 在一个独立的 tap 仓库中发布 Homebrew Cask,让安装命令保持干净。
2. 提供一条维护者本地的一键发布流水线(`Scripts/publish-release.sh`),保留稳定自签名
   签名。
3. 确立 git tag `vX.Y.Z` 为版本的单一事实源,贯通到 App bundle 的 Info.plist、release
   资产名和 cask。
4. 刷新安装/发布文档,以 Homebrew 为首,同时保留直接下载的备选路径。
5. 保持应用内零网络调用,以及现有的零网络隐私属性不变。

## 非目标(本轮明确不做)

- Notarization 或 Developer ID 签名。
- Sparkle、appcast,或任何应用内更新检查 / 应用内网络调用。
- Mac App Store、DMG 打包,或提交 homebrew-core。
- 截图、release notes 文案打磨,以及产品页(这些属于后续子项目)。
- 修改 bundle identifier。本轮沿用现有的 `com.local.clipboard-manager`。敲定正式的
  reverse-DNS identifier(以及它隐含的一次性数据目录迁移)留作 1.0 前的独立身份决策,
  避免把"改数据位置(会孤立你现有历史)"这个单向门和分发机制纠缠在一起。

## 免费路的天花板(诚实表述)

不公证的话,*直接下载*就做不到像 Maccy 那样完全零摩擦的首次打开。免费路把大部分差距
补上的办法,是把推荐的安装走 Homebrew —— cask 安装时会自动去掉 quarantine 属性,所以
Homebrew 用户不会看到"未识别开发者"的拦截。直接下载的用户仍需要文档化的 Gatekeeper
绕过步骤。这是一个明确声明的限制,而非发布阻塞项。

## 架构

两个仓库:

```
主仓库  anlostsheep/clipboard
  - Scripts/publish-release.sh      本地:verify -> 稳定签名构建 -> 打包 ->
                                    GitHub Release -> 回写 cask
  - GitHub Release vX.Y.Z           ClipboardApp-vX.Y.Z-macos.zip + .sha256 + release notes

Tap 仓库  anlostsheep/homebrew-clipboard   (新建)
  - Casks/clipboard.rb              指向上面的 Release 资产,sha256 锁定
  - .github/workflows/audit.yml     对 cask 跑 brew audit + brew style
```

用户侧流程:

```
brew tap anlostsheep/clipboard
brew install --cask clipboard      # Homebrew 去掉 com.apple.quarantine -> 直接打开
brew upgrade --cask clipboard      # 后续更新
```

维护者的构建与稳定签名留在**本地**,因为稳定自签名身份只存在于维护者的 keychain 里,
而它正是让辅助功能权限跨版本保持稳定的东西。完全 CI 驱动的发布在 CI 里只能 ad-hoc
签名,会导致每次更新都重置辅助功能权限 —— 对一个依赖自动粘贴的工具是倒退。发布步骤
(创建 GitHub Release、回写 cask)由本地流水线用 `gh` 完成。

## 组件

### 组件一:Homebrew Cask(`Casks/clipboard.rb`)

tap 仓库里的一个标准 cask。关键 stanza:

- `version "X.Y.Z"` 和 `sha256 "..."` —— 两者由发布脚本每次发版回写。
- `url "https://github.com/anlostsheep/clipboard/releases/download/v#{version}/ClipboardApp-v#{version}-macos.zip"`
- `name "Clipboard"`、`desc`、`homepage`
- `app "ClipboardApp.app"`
- `depends_on macos: ">= :sonoma"`(macOS 14+)
- `auto_updates false` —— App 不自更新;更新由 Homebrew 负责。
- `zap trash:` —— 在 `brew uninstall --zap` 时清除
  `~/Library/Application Support/com.local.clipboard-manager` 及对应的 `UserDefaults`
  plist。
- `caveats` —— 说明自动粘贴需要辅助功能权限,以及这是一个自签名、未公证的 beta。

不需要写显式的 `--no-quarantine` / quarantine stanza:Homebrew 安装 cask 时已经会去掉
quarantine 属性,这恰恰是让免费路的 App 不撞 Gatekeeper 拦截就能打开的关键。

### 组件二:`Scripts/publish-release.sh`(维护者本地发布)

一个新脚本,编排已有的 `package-release.sh` 加上发布动作。顺序:

1. **前置校验**:git 工作树干净、在 `master`、`gh` 已登录、版本号已确定、git tag 尚不
   存在、tap 仓库本地路径可达。
2. 以 `REQUIRE_STABLE_CODE_SIGNING=1` 调用 `package-release.sh`,产出稳定签名的
   `dist/ClipboardApp-vX.Y.Z-macos.zip` 及其 `.sha256`。
3. 创建并推送 git tag `vX.Y.Z`。
4. `gh release create vX.Y.Z` 上传 zip 和 `.sha256`,release notes 来自模板
   (未公证 / 自签名 beta、Homebrew 安装说明、直接下载的 Gatekeeper 提示)。
5. 回写 tap 的 cask:更新 `version` 和 `sha256`,提交并推送到 tap 仓库。
6. 打印验证命令。

构建与签名保持本地且稳定;只有发布动作通过 `gh` 触网。

### 组件三:版本单一事实源

git tag `vX.Y.Z` 是单一事实源。它驱动:`package-release.sh` 的 `VERSION` ->
`build-app-bundle.sh` 把 `CFBundleShortVersionString` / `CFBundleVersion` 写入 App 的
Info.plist -> release 资产文件名 -> cask 的 `version`。这消除当前"VERSION 靠环境变量
到处传"的漂移。

### 组件四:文档(双渠道)

- `docs/install.md`:以 Homebrew 为首(两条命令);保留直接下载 zip 作为备选,沿用现有的
  Gatekeeper 绕过说明。
- `docs/release-process.md`:把手动发布清单换成 `publish-release.sh` 流程加上 tap 维护
  说明。
- `README.md`:安装段落以 `brew install --cask` 打头。

## 数据流

```
维护者:  publish-release.sh -> GitHub Release + 回写 cask
安装:    brew tap -> brew install --cask -> Homebrew 去 quarantine -> 直接打开
更新:    brew upgrade --cask -> 拉取新 Release 资产(校验 sha256) -> 替换 .app
```

## 错误处理

`publish-release.sh` 在每种失败模式下都以清晰、具体的信息中止:

- 工作树脏、分支错、tag 已存在、`gh` 未登录、tap 仓库路径缺失、sha256 不匹配,或检测到
  ad-hoc(非稳定)签名。
- 如果该 tag 的 GitHub Release 已存在,拒绝执行而非静默覆盖。
- 顺序上尽量减少半发布状态:先把本地产物(构建、zip、sha256)备齐,再做任何远端推送
  (tag、release、cask)。在远端步骤之前失败,不会留下悬空的 tag 或 release。

## 测试与验证

这是发布工程,所以"测试"指的是流水线验证,而非单元测试。

tap 仓库 CI:

- `brew audit --cask Casks/clipboard.rb` 通过。
- `brew style Casks/clipboard.rb` 通过。

干净用户 / 另一台机器上的端到端验证:

- `brew tap anlostsheep/clipboard && brew install --cask clipboard` 安装成功。
- App 打开**不需要**右键 Open 步骤。
- `xattr -p com.apple.quarantine /Applications/ClipboardApp.app` 无输出。
- 辅助功能权限可授予,自动粘贴可用。
- `brew upgrade --cask clipboard` 能升级到更新的已发布版本。
- `brew uninstall --cask --zap clipboard` 移除 App 及其数据目录。
- cask 的 `sha256` 与已发布资产一致(`shasum -a 256 -c`)。

现有门禁仍为必需:

- `Scripts/verify.sh` 通过(在 `package-release.sh` 内部被调用)。
- 已发布的 bundle 是稳定自签名:`codesign -dv --verbose=4` 显示
  `Authority=ClipboardApp Local Code Signing`。

## 手工验收

向 `docs/manual-acceptance-checklist.md` 新增条目:

- 全新 Homebrew 安装后,App 打开无需 Gatekeeper 右键步骤。
- Homebrew 安装后 quarantine 属性已不存在。
- `brew upgrade --cask` 从版本 N 升到 N+1。
- 辅助功能权限在 Homebrew 升级后保持(稳定签名守住)。
- `brew uninstall --zap` 移除 App 及本机数据目录。
- 直接下载 zip 路径在文档化的 Gatekeeper 绕过步骤下仍可用。

## 完成标准

本子项目完成的条件:

1. tap 仓库 `anlostsheep/homebrew-clipboard` 存在,且 `Casks/clipboard.rb` 通过校验
   (`brew audit` + `brew style`)。
2. `Scripts/publish-release.sh` 用一条本地命令产出稳定签名的 GitHub Release 并回写 cask。
3. git tag `vX.Y.Z` 是版本的单一事实源,贯通 Info.plist、release 资产和 cask。
4. `brew install --cask clipboard` 打开 App 时不撞 Gatekeeper 拦截,且
   `brew upgrade --cask` 能更新它。
5. 辅助功能权限在 Homebrew 升级后仍存活(稳定签名得以保留)。
6. `docs/install.md`、`docs/release-process.md` 和 `README.md` 以 Homebrew 为首,并保留
   直接下载备选。
7. `docs/manual-acceptance-checklist.md` 反映新的验收条目。
8. 不引入任何应用内网络调用。Notarization、Sparkle / 应用内更新、App Store、DMG、
   截图/产品页,以及 bundle-id 变更均保持在范围之外。

## 风险

- **免费路下直接下载的首次打开摩擦。** 不公证就无法避免;通过把推荐安装走 Homebrew 并
  文档化绕过步骤来缓解。
- **本地发布步骤不是完全自动化。** 这是为保留稳定签名(及辅助功能权限持久性)、又不付费
  买 Developer ID 而刻意付出的代价。仅 CI 发布因此被明确否决。
- **多维护一个仓库。** tap 仓库增加了维护面,但正是它让安装命令保持干净
  (`anlostsheep/clipboard/clipboard`)。
- **cask 与 Release 漂移。** 如果 cask 的 `sha256`/`version` 与 Release 资产失同步,安装
  会失败;发布脚本每次发版原子地回写两者,且 tap CI 会审计 cask。
- **bundle identifier 仍像占位符。** 本轮沿用 `com.local.clipboard-manager`;敲定正式
  identifier 是非目标中注明的独立的 1.0 前决策。
