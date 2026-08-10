# 真机安装

本项目的最低运行版本为 iOS 26.0。下面的步骤适用于使用 Xcode 26.6+ 将 Debug 版本安装到已连接的 iPhone；不会把个人 Apple 团队标识或签名资料写入仓库。工程已经配置 `AppIcon` 资源目录，执行构建时会自动把正式的 1024 × 1024 不透明图标编译进应用，无需在 Xcode 中手工替换图标；`Info.plist` 的 `UILaunchScreen` 也必须保留，否则系统可能以 320 × 480 兼容模式启动并使编辑器无法全屏。

## 首次准备

1. 在 Xcode 打开 **Settings → Accounts**，登录拥有 Apple Development 权限的 Apple ID，并确认其 Team 可用。
2. 用 USB 连接 iPhone，按设备提示信任此 Mac；在 iPhone 的 **设置 → 隐私与安全性 → 开发者模式** 中开启 Developer Mode，然后重启设备。
3. 解锁 iPhone，运行以下命令确认 Xcode 能看见真机：

   ```bash
   xcrun devicectl list devices
   xcodebuild -project PhotoEdit.xcodeproj -scheme PhotoEdit -showdestinations
   ```

   `xcodebuild` 输出中的 `platform:iOS` 条目的 `id` 是构建用设备 ID；`devicectl list devices` 的 `Identifier` 是安装和启动用设备 ID。两者在同一台设备上可能不是同一个字符串。

4. 在 Xcode 的 **Signing & Capabilities** 中选择开发 Team，并使用该 Team 可注册的唯一 Bundle Identifier。仓库默认的 `com.taoking.PhotoEdit` 仅适用于拥有它的 Team；其他 Team 应使用自己的反向域名，例如 `com.example.photoedit`。不要把个人 Team ID、profile 或个人 Bundle Identifier 写进 `project.yml`；以下命令会临时传入它们。

## 日常更新：推荐使用 Xcode

1. 打开 `PhotoEdit.xcodeproj`，选择 **PhotoEdit target → Signing & Capabilities**。
2. 确认 **Automatically manage signing** 已开启，Team 和 Bundle Identifier 均为本机开发配置。
3. 在 Xcode 顶部选择已连接的 iPhone，按 `⌘R`。Xcode 会构建、签名并覆盖安装旧版本。
4. 首次安装或更换签名账号后，按下文“信任开发者”完成手机侧确认。

## 手动安装已经构建好的 App 包

这一节适合“代码已经构建完成，只想把安装包再次装到手机”的情况。iPhone 不能直接运行 macOS Finder 中双击的 `.app`，也不能通过 AirDrop 安装未经当前设备授权签名的包。这里的安装包必须是针对 `iphoneos` 构建、使用当前 Apple Development Team 签名的 `PhotoEdit.app`；Simulator 的 `Debug-iphonesimulator/PhotoEdit.app` 不能装到真机。

### 方法一：在 Xcode 中拖入 `.app`

1. 用 USB 连接并解锁 iPhone，确认已经信任此 Mac，且 Developer Mode 已开启。
2. 打开 Xcode，选择 **Window → Devices and Simulators**。
3. 在左侧选择目标 iPhone，等待状态变为 Connected。
4. 在 **Installed Apps** 区域点击 `+`，或直接把已签名的 `PhotoEdit.app` 拖入该区域。
5. 等待安装完成后，从 iPhone 桌面手动打开 PhotoEdit。若系统提示未信任开发者，按“信任开发者”一节操作。

构建产物通常位于自定义 Derived Data 目录：

```text
<DerivedData>/Build/Products/Debug-iphoneos/PhotoEdit.app
```

只要 Bundle Identifier 和签名 Team 与手机上原版本一致，重复安装会覆盖应用并保留 Application Support 中的当前编辑会话。更换 Bundle Identifier 会安装成另一个应用；主动卸载旧应用会同时删除其会话数据。

### 方法二：用命令行安装已有 `.app`

先列出设备，取得 `devicectl` 使用的 Identifier：

```bash
xcrun devicectl list devices
```

然后验证签名并覆盖安装。以下变量只在当前终端有效：

```bash
export PHOTOEDIT_DEVICE_ID='DEVICECTL_DEVICE_IDENTIFIER'
export PHOTOEDIT_BUNDLE_ID='com.example.photoedit'
export PHOTOEDIT_APP='/absolute/path/to/PhotoEdit.app'

codesign --verify --deep --strict --verbose=4 "$PHOTOEDIT_APP"
xcrun devicectl device install app \
  --device "$PHOTOEDIT_DEVICE_ID" \
  "$PHOTOEDIT_APP"
```

安装完成后，可以直接在手机桌面打开；设备保持解锁时也可以从 Mac 启动：

```bash
xcrun devicectl device process launch \
  --device "$PHOTOEDIT_DEVICE_ID" \
  --terminate-existing \
  "$PHOTOEDIT_BUNDLE_ID"
```

如果返回 `Locked`，说明包已经安装，但 iOS 拒绝从 Mac 远程启动锁屏设备。解锁手机后手动打开即可，不需要重新构建或安装。

### 收到 `.ipa` 时

Xcode 的 **Devices and Simulators → Installed Apps** 可以接受符合当前设备签名条件的开发 `.ipa`。Personal Team 构建的包只能安装到其 provisioning profile 包含的设备，并且通常约 7 天后失效。来源不明、未签名、使用其他 Team 签名或不包含当前设备 UDID 的 `.ipa` 不能通过上述步骤安装；不要通过关闭系统安全检查来绕过签名要求。

## 构建、安装与启动

命令行方式适合留存明确构建记录。以下命令在仓库根目录执行；所有变量仅在当前终端有效。将占位符替换为本机实际值：

```bash
export PHOTOEDIT_TEAM_ID='YOUR_TEAM_ID'
export PHOTOEDIT_BUNDLE_ID='com.example.photoedit'
export PHOTOEDIT_DEVICE_ID='DEVICECTL_DEVICE_IDENTIFIER'
export PHOTOEDIT_UDID='IOS_DEVICE_UDID'
export PHOTOEDIT_BUILD_DIR='/tmp/photoedit-device-build'

xcrun devicectl device info details --device "$PHOTOEDIT_DEVICE_ID"

# 仅在 project.yml 或 AppIcon 资源配置改动后需要重新生成工程。
xcodegen generate

xcodebuild \
  -project PhotoEdit.xcodeproj \
  -scheme PhotoEdit \
  -configuration Debug \
  -destination "platform=iOS,id=$PHOTOEDIT_UDID" \
  -derivedDataPath "$PHOTOEDIT_BUILD_DIR" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$PHOTOEDIT_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$PHOTOEDIT_BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  'CODE_SIGN_IDENTITY=Apple Development' \
  build

export PHOTOEDIT_APP="$PHOTOEDIT_BUILD_DIR/Build/Products/Debug-iphoneos/PhotoEdit.app"

codesign --verify --deep --strict --verbose=4 "$PHOTOEDIT_APP"
xcrun devicectl device install app \
  --device "$PHOTOEDIT_DEVICE_ID" \
  "$PHOTOEDIT_APP"

xcrun devicectl device process launch \
  --device "$PHOTOEDIT_DEVICE_ID" \
  --terminate-existing \
  "$PHOTOEDIT_BUNDLE_ID"
```

之后重复安装时，保持设备已连接并重新执行这一节的签名构建、校验、安装与启动命令即可。使用免费个人开发 Team 时，开发签名通常约 7 天后到期；重新构建并覆盖安装即可续期。

如果只需要把上一次已经构建且签名仍有效的包重新装到同一台手机，可以跳过 `xcodegen generate` 和 `xcodebuild`，直接执行上一节“手动安装已经构建好的 App 包”的签名校验与安装命令。

## 信任开发者

若命令显示安装成功、但手机无法启动应用，iOS 可能尚未信任当前开发者。该安全步骤无法由命令行绕过：

1. 保持 iPhone 解锁，打开 **设置 → 通用 → VPN 与设备管理**。
2. 在“开发者 App”下选择当前 Apple Development 开发者并点击“信任”。
3. 回到电脑重新执行启动命令，或直接从手机桌面打开 PhotoEdit。

## 常见问题

- `Signing for "PhotoEdit" requires a development team`：尚未传入 `DEVELOPMENT_TEAM`，或 Xcode 未在 Signing & Capabilities 中选中 Team。
- `No Account for Team`：该 Team 的 Apple ID 未登录到 Xcode，或登录账号没有开发权限。回到 Xcode 的 Accounts 页面登录正确账号后重试。
- `No profiles for '<Bundle ID>'`：确认 Team 可以注册 `$PHOTOEDIT_BUNDLE_ID`，并保留 `-allowProvisioningUpdates` 让 Xcode 下载或创建 profile；不要尝试复用其他应用的 exact bundle ID profile。
- 找不到或无法安装设备：解锁设备、重新插拔并信任此 Mac，确认 Developer Mode 已开启，然后再次运行 `xcrun devicectl list devices`。
- 已安装但无法打开：先确认 Developer Mode，再按上一节信任开发者；不要删除其他应用或更换其 Bundle ID/profile 来绕过系统签名检查。

安装成功后，请按 [real-world-validation.md](real-world-validation.md) 在真机检查 Photos 权限、真实 RAW、HDR、导出与视频工作流。

同时请在 iPhone 上导入一张竖幅和一张横幅照片，检查默认收起状态的全图预览、底部工具横向滚动、展开/收起参数，以及连续双指缩放和拖拽的边界。模拟器无法替代这项多点手势与真实照片显示验证。
