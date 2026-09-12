# 第三方声明

自有 Swift 界面以独立子进程调用 FFmpeg，没有复制 LosslessCut 源码。自有代码 MIT；FFmpeg 和依赖不适用该 MIT 许可。

发行包内 FFmpeg 9.0.1 启用 `--enable-gpl --enable-version3`，其适用 GPL-3.0-or-later。附带的依赖遵循各自许可，完整版权及许可文本保留于 ThirdParty 和应用 Resources/Licenses。

## 对应源码

本次 Release 的 `JIAYU-VideoSplit-1.0.1-ThirdPartySource.tar.gz` 包含对应源代码归档、逐项 URL/SHA-256 清单和安装版本的 Homebrew 配方。x264 按配方指定的 Git commit 归档。每个源码包自带完整版权声明。配方描述编译选项；`scripts/bundle_engine.py` 是本项目执行的复制、动态库路径重定位和临时签名步骤，没有修改 FFmpeg 功能代码。

本机链接的 Apple 系统框架属于系统组件，不随应用复制。品牌图标由 AI 生成，未包含字体文件。

## 实际包含的组件

- **dav1d**: https://code.videolan.org/videolan/dav1d
- **ffmpeg**: https://ffmpeg.org/
- **lame**: https://lame.sourceforge.io/
- **libvmaf**: https://github.com/Netflix/vmaf
- **libvpx**: https://www.webmproject.org/code/
- **openssl@3**: https://openssl-library.org
- **opus**: https://www.opus-codec.org/
- **svt-av1**: https://gitlab.com/AOMediaCodec/SVT-AV1
- **x264**: https://www.videolan.org/developers/x264.html
- **x265**: https://github.com/Multicorewareinc/x265
- **xz**: https://tukaani.org/xz/

参考项目：https://github.com/mifi/lossless-cut （仅作功能参考）。
