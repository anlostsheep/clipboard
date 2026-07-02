# Clipboard Gatekeeper / quarantine 修订设计(cask postflight 去 quarantine + 透明披露)

## 背景:前一个前提被 E2E 证伪

`2026-06-24-distribution-trust-chain-homebrew-design.md` 与
`2026-07-02-clipboard-go-live-pat-publish-design.md` 的免费路分发设计,建立在一个**错误前提**
上:"Homebrew 安装 cask 时会去掉 quarantine 属性,所以未公证的自签名 App 打开时不撞
Gatekeeper。"

v0.1.0 发布后的真机 E2E(macOS 26 Tahoe,官方 Homebrew 6.0.6)证伪了它:

| 安装方式 | 结果 |
|---|---|
| `brew install --cask clipboardapp`(默认) | app 带 `com.apple.quarantine` → `spctl` **rejected** |
| `brew install --no-quarantine …` | `invalid option`(该 CLI flag 在 Homebrew 6.x 已移除) |
| `HOMEBREW_CASK_OPTS="--no-quarantine"` + 清缓存重装 | app **仍带**新 quarantine → 仍 rejected |

结论:当前 Homebrew **默认给 cask 安装打 quarantine,且没有受支持的开关能去掉**。未公证的
自签名 App 经 Homebrew 装完,首次打开照样撞 Gatekeeper"无法验证开发者"拦截 —— 与直接下载
无异。原设计"免 Gatekeeper 摩擦"这个贯穿整个子项目的卖点因此不成立。

## 上游决策(本次重评估已定)

- **仍严格走免费路**:不购买 Apple Developer Program,不做 notarization / Developer ID
  签名(免费 Apple ID 无法公证)。
- 因此免摩擦只能靠 **cask 自己在安装后移除 quarantine**(postflight),而非依赖 Homebrew。
- 采取**透明披露**:在 caveats 与文档中明说 app 未公证、且本 cask 为便利移除了 quarantine
  (即绕过 Gatekeeper 对该 app 的这层校验),让用户知情。

## 已验证的技术可行性

在真机上实测(设计前研究,非实现):

- 手动 `xattr -d -r com.apple.quarantine <app>` 后,`com.apple.quarantine` 消失(仅剩无害的
  `com.apple.provenance`),Gatekeeper 不再评估 → 首开拦截消除。
- 给 tap cask 加 postflight 去 quarantine 后:`brew style --fix` 自动修正 stanza 顺序、
  exit 0;`brew audit --cask anlostsheep/clipboard/clipboardapp` **exit 0、无 offense**。
  即该 postflight **能过我们 tap 的 CI audit**。

## 目标

1. 让 `brew install --cask clipboardapp` 装完的 App 首次打开**无 Gatekeeper 拦截**,方式是
   cask postflight 在安装/升级后移除 quarantine。
2. 用**准确**的机制表述替换所有"Homebrew 自动去 quarantine"的错误文档。
3. 透明披露未公证与 quarantine 移除的安全取舍。
4. 不发新 app release、不改 App 代码、不引入网络调用。

## 非目标

- Notarization / Developer ID / 付费 Apple Developer Program。
- 让直接下载(非 Homebrew)路径免摩擦(不公证做不到;维持现有文档化的手动步骤)。
- 提交 homebrew-cask 官方库(官方会拒绝 quarantine 操作;自建 tap 即可)。
- 修改 bundle id、发新版本号、重建 app 产物。

## 架构与改动

两仓库结构、`publish-release.sh`(curl+PAT)发布流程均**不变**。本次改动限于 cask 内容与
文档:

### 改动一:cask 加 postflight(seed + tap 两处)

在 `packaging/homebrew/Casks/clipboardapp.rb`(seed,权威 bootstrap 源)与 tap 的
`Casks/clipboardapp.rb`(权威 live cask)中加入:

```ruby
postflight do
  system_command "/usr/bin/xattr",
                 args: ["-d", "-r", "com.apple.quarantine", "#{appdir}/ClipboardApp.app"]
end
```

放在 `brew style` 认可的 stanza 顺序位置(以 `brew style --fix` 为准)。它在
`Scripts/update-cask.sh` 只改 `version`/`sha256` 的回写中原样保留,未来发版不受影响。

### 改动二:cask caveats 透明披露(seed + tap 两处)

caveats 增补:app 未公证;本 cask 在安装后移除 quarantine 属性,使其可直接打开(这会绕过
Gatekeeper 对该 app 的校验);更新经 `brew upgrade --cask clipboardapp`。

### 改动三:修正失效的文档表述

把以下文件中"Homebrew 安装 cask 会去掉 quarantine"的错误说法,改为准确的"本 cask 通过
postflight 在安装后去掉 quarantine",并加透明说明:

- `README.md`
- `docs/install.md`
- `packaging/homebrew/README.md`(seed;tap README 由它同步)

`publish-release.sh` 内嵌的 release notes 文案如暗示"Homebrew 免 Gatekeeper",也一并校正为
准确表述。

### 改动四:给当前 live cask 补 postflight(操作)

v0.1.0 的 tap cask 目前无 postflight。直接给 tap cask 加 postflight + caveats 并推送
(版本仍 `0.1.0`,**不发新 release**;当前下载数为 0,无存量用户受影响)。

## 数据流(修订)

```
安装:  brew install --cask clipboardapp
          -> 下载 v0.1.0 资产(sha256 校验)
          -> 安装到 /Applications
          -> postflight: xattr -d -r com.apple.quarantine  <-- 新增,消除首开拦截
          -> 直接打开,无 Gatekeeper
升级:  brew upgrade --cask clipboardapp  -> 同样触发 postflight,保持免摩擦
直接下载:不变,仍需文档化的手动 Gatekeeper 放行
```

## 测试与验证

- `brew style`(postflight 正确排序后)通过。
- tap CI `brew audit --cask` 绿(已验证)。
- 真机 E2E(复验之前失败的两项):
  - `brew install --cask clipboardapp` 后 `xattr -p com.apple.quarantine /Applications/ClipboardApp.app` **无输出**。
  - App 打开**无需** Gatekeeper 右键 Open 步骤。
  - 授予辅助功能后自动粘贴可用;`shasum -a 256 -c` OK。
- 现有 Swift 门禁 `Scripts/verify.sh` 不受影响(本次不碰 App 代码),但作为回归仍应通过。

## 错误处理 / 风险

- **安全绕过**:移除 quarantine 即绕过 Gatekeeper 对该 app 的校验。缓解:caveats/文档透明
  披露;用户安装本 tap 即代表信任来源。
- **仅惠及 Homebrew 用户**:直接下载仍需手动放行(不变、已文档化)。
- **未来 Homebrew 收紧 audit**:若某版本 `brew audit` 开始拒绝 quarantine 操作,tap CI 会
  先变红提示;届时回退到"诚实摩擦"(文档承认 Homebrew 用户也需首开放行)。近期风险低。
- **postflight 目标路径**:使用 `#{appdir}/ClipboardApp.app`;真机手动对
  `/Applications/ClipboardApp.app` 去 quarantine 已验证生效。

## 完成标准

1. seed cask 与 tap cask 均含去 quarantine 的 postflight,且 `brew style` + `brew audit`
   通过(tap CI 绿)。
2. `brew install --cask clipboardapp` 装完 `xattr` 无 quarantine,App 打开无 Gatekeeper
   拦截。
3. README / `docs/install.md` / tap README(及 release notes 文案)不再声称"Homebrew 自动
   去 quarantine",改为准确的 postflight 机制 + 透明披露。
4. `docs/manual-acceptance-checklist.md` 中两条相关验收项复核为通过并追加日期记录。
5. 未发新 app release、未改 App 代码、未引入网络调用;notarize/App Store/bundle-id 变更
   保持范围外。

## 备注:被本设计取代的表述

`2026-06-24` 与 `2026-07-02-...-pat-publish` 两份历史设计中"Homebrew 去 quarantine → 免
Gatekeeper"的表述,自本设计起以本文为准更正。历史文档作为决策留痕保留原样,不回改。
