# 许可证全文

这里的许可证文件是上游原文，没有改写条款。本文件只说明哪一份文本对应哪一个组件。

修改日期：2026-10-21。

- `GPL-3.0.txt`：GNU General Public License 第 3 版全文。适用于修改过的 `beatoraja.jar`，以及 jar 内按 GPL 构建的 FFmpeg（路径中带 `-gpl` 的那一组）。
- `OpenAL-Soft-1.21.1-LGPL-2.0.txt`：OpenAL Soft 1.21.1 仓库 `COPYING` 原文，即 GNU Library General Public License 第 2 版。对应 `openal.dylib` 的 arm64 切片。
- `OpenAL-Soft-1.15.1-LGPL-2.0.txt`：OpenAL Soft 1.15.1 仓库 `COPYING` 原文，同样是 GNU Library General Public License 第 2 版。对应 `openal.dylib` 的 x86_64 切片。两份上游文本并不逐字相同，所以都原样附上。
- `Apache-2.0.txt`：Apache License 2.0 全文。适用于 libGDX。
- `LWJGL-2-BSD.txt`：LWJGL 2.9.3 源码 `org/lwjgl/LWJGLUtil.java` 文件头中的 BSD 许可，原样复制。适用于 jar 根和 `natives/` 里的 `liblwjgl.dylib`。
- `PortAudio-MIT.txt`：PortAudio 仓库 `LICENSE.txt` 原文（MIT）。项目地址是 http://www.portaudio.com/ 和 https://github.com/PortAudio/portaudio 。适用于 `natives/libjportaudio.dylib`。
- `OIS-zlib-libpng.txt`：OIS 1.4 的 zlib/libpng 短声明，摘自 libGDX 标签 `gdx-parent-1.9.9` 里 `extensions/gdx-controllers/gdx-controllers-desktop/jni/ois-v1-4svn/ReadMe.txt` 的 LICENSE 段，文字未改。
- `OpenJFX-legal/`：OpenJFX 18.0.2 SDK 的 `legal/` 目录原样复制。GPL-2.0 全文、Classpath Exception 和附加说明在 `OpenJFX-legal/javafx.base/` 的 `LICENSE`、`ASSEMBLY_EXCEPTION`、`ADDITIONAL_LICENSE_INFO`。其余模块目录包含同一许可证和各自的第三方声明。

app 包内还有两份副本，避免只发出 `.app` 时丢掉这些文本：

- `Contents/Resources/licenses`：本目录的副本
- `Contents/Resources/javafx/legal`：SDK `legal/` 的副本
