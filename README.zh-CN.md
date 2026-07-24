# QuickRecorder Enhanced

面向 macOS 讲课录制的屏幕录制工具，重点改善麦克风语音并生成更小、可验证的归档文件。

[English](README.md) · [项目文档](docs/README.md) ·
[发布版本](https://github.com/Nongfsq/QuickRecorder-Enhanced/releases) ·
[原项目](https://github.com/lihaoyun6/QuickRecorder)

> QuickRecorder Enhanced 基于
> [lihaoyun6](https://github.com/lihaoyun6) 开发的
> [QuickRecorder](https://github.com/lihaoyun6/QuickRecorder) 继续维护，
> 但不是原项目的官方版本。

## 主要增强

- **麦克风降噪：** 提供一个经过听感测试的 RNNoise 选项，使用 48 kHz 单声道、
  80% 处理信号与 20% 原始信号混合。
- **讲课录制：** 面向文字可读性、低帧率、自适应 VFR、单声道和长时间录制的实用设置。
- **AV1 归档：** 使用 FFmpeg/SVT-AV1 进行录制后压缩，并记录进度、任务清单和时间戳验证结果。
- **音频导出可靠性：** 修复单声道 QMA 渲染，导出失败时明确报错，不再静默生成空文件。
- **权限行为：** ScreenCaptureKit 启动失败后不再自动循环申请权限。

RNNoise 只处理麦克风，不处理录制到的系统声音。

## 当前状态

目前发布版提供用于测试讲课录制与 RNNoise 降噪的**实验性 DMG**。它使用项目固定的
本地签名身份，但尚未使用 Developer ID 签名，也没有经过 Apple 公证。因此首次打开时，
macOS 可能要求在 Finder 中右键点击 App 并选择“打开”。

DMG 中的 App 主程序支持 `arm64` 与 `x86_64`。这个 Alpha 安装包暂不内置可选的
FFmpeg 运行库；在完成运行库许可证合规与 Universal 打包前，AV1 归档需要另行安装
兼容的 FFmpeg。

本项目从现在开始使用自己的版本与 Release 页面。原项目的 Sparkle 更新地址已经
停用；未来二进制版本会使用本项目自己的签名密钥和更新源。

## 构建

在 macOS 12.3 或更高版本中使用 Xcode 打开 `QuickRecorder.xcodeproj`。运行前请选择
自己的开发团队，并使用自己控制的 Bundle ID。

macOS 隐私授权同时识别 Bundle ID 与代码签名。独立身份第一次运行时需要重新授权
一次屏幕录制和麦克风，这是正常的身份迁移，不应反复弹窗。详细说明见
[构建与签名](docs/building.md)。

## 文档

- [功能说明](docs/features.md)
- [构建与签名](docs/building.md)
- [发布策略](docs/releases.md)
- [与原项目的关系](docs/upstream.md)
- [归档命令行工具](Tools/Archive/README.md)

## 发布版本

本项目自己的版本从 `v1.7.0-alpha.1` 开始。原项目的 tags 和安装包不会作为本项目
的 Release 重新发布。

Alpha Release 可以提供明确标注为“自签名、未公证”的实验性 DMG。面向普通用户的正式
安装包仍需完成 Developer ID 签名、Apple 公证、运行库许可证合规和本项目自己的更新密钥。

## 许可证与署名

QuickRecorder Enhanced 使用 [GNU AGPL v3.0](LICENSE)。原 QuickRecorder 项目和作者
保留在 [NOTICE.md](NOTICE.md) 中；第三方组件继续保留各自的许可证说明。
