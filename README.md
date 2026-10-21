# beatoraja 0.8.9 macOS arm64 启动包

这是 beatoraja 0.8.9 在 Apple Silicon（arm64）上的启动包。它不是 exch-bms2 或 mocha-repository 的官方构建。Bundle ID 是 `local.unofficial.beatoraja.macos-arm64`。

`dist/Beatoraja.app` 把 JavaFX、替换过的原生库、许可证和上游自带的 default 皮肤放在包内。发布包不附带 JDK，也不附带曲库、成绩或玩家配置。

本说明的修改日期：2026-10-21。

分发这个目录时，要按下面的许可履行义务。这些是发布条件，不是可以删掉或改掉的说明。

## 仓库结构与父仓库引用

本仓库用 `git submodule` 锁定上游父仓库的指定提交，提交里只记录 gitlink：

- `upstreams/beatoraja`：[exch-bms2/beatoraja](https://github.com/exch-bms2/beatoraja) 标签 `0.8.9`（`83574048ba489082eb46df7fe9806b464bf1f526`）
- `upstreams/libgdx`：[libgdx/libgdx](https://github.com/libgdx/libgdx) 标签 `gdx-parent-1.9.9`（`404ad6893f58fe880b91416df1a3af15eb3c6ed8`）

`.gitmodules` 里这两条都写了 `shallow = true`。克隆时按深度 1 拉取，避免把上游整段历史带下来。

本仓库自己的部分，针对的是 libGDX 1.9.9 在 `os.arch=aarch64` 下仍按 32 位文件名加载原生库这件事：

- `scripts/build-arm64-natives.sh`：从 `upstreams/libgdx` 交叉或本机编译 arm64 的 `libgdx.dylib`，以及带 OIS Objective-C++ 的 `libgdx-controllers-desktop.dylib`，并取出 LWJGL 2.9.3-rc1 与 FreeType arm64 切片。
- `scripts/patch-beatoraja-jar.sh`：把这些 arm64 切片和 `beatoraja.jar` 里的 x86_64 切片合成通用二进制，写回 jar 与 `natives/`。
- `scripts/beatoraja-launcher.sh`：只用 `od` 和 bash 读 Mach-O 头，确认目标是 arm64 的 Java 17 可执行文件之后才启动。
- `scripts/assemble-release.sh`：按下面的许可义务组装 `.app`。未传第三个参数时，图标用 `assets/AppIcon.icns`。
- `assets/AppIcon.icns`：应用程序图标。
- `LICENSES/`：随包分发的许可证原文。

## 许可证全文放在哪里

- 发布树：`LICENSES/`。目录里的 `README.md` 只做索引，条款在同目录的原文文件里。
- app 内：`Contents/Resources/licenses`，内容与 `LICENSES/` 相同。
- OpenJFX：`Contents/Resources/javafx/legal`，以及 `LICENSES/OpenJFX-legal/`。这是 OpenJFX 18.0.2 SDK 的 `legal/` 原样复制，里面有 GPL-2.0 全文、Classpath Exception（`ASSEMBLY_EXCEPTION` 与 `ADDITIONAL_LICENSE_INFO`）和各模块的第三方声明。

## 许可义务

### beatoraja（GPLv3）

`beatoraja.jar` 不是上游原样的二进制。为了在 arm64 上加载，jar 根目录里的 macOS 原生库已被替换，所以它是 GPLv3 下的修改版本。全文见 `LICENSES/GPL-3.0.txt`。

上游 0.8.9 源码：

https://github.com/exch-bms2/beatoraja/tree/0.8.9

分发这个修改版 jar 时，GPLv3 要求同时提供对应源码。Java 部分就是上面这个标签。被换掉的原生库，对应来源写在后面，不能只发出 jar、却不说明替换了什么。

### jar 里的 FFmpeg（GPL）

这个 jar 带有 Bytedeco JavaCPP Presets 的 FFmpeg 7.1.1-1.5.12，里面包含 GPL 构建（路径中带 `-gpl` 的那一组，以及按 GPL 配置编译的 FFmpeg）。GNU GPLv3 全文同样是 `LICENSES/GPL-3.0.txt`。

- FFmpeg 7.1.1 源码：https://github.com/FFmpeg/FFmpeg/tree/n7.1.1
- JavaCPP Presets 1.5.12：https://github.com/bytedeco/javacpp-presets/tree/1.5.12

这份 FFmpeg 随 jar 一起分发，许可义务跟着 jar 走。

### OpenAL Soft（LGPL）

`openal.dylib` 有两份，逐字节相同：一份在 jar 根，一份在 `natives/openal.dylib`。它是 x86_64 + arm64 通用二进制。二进制里的版本字符串同时有 OpenAL Soft 1.21.1 和 1.15.1。

- arm64：OpenAL Soft 1.21.1。许可证原文是 `LICENSES/OpenAL-Soft-1.21.1-LGPL-2.0.txt`（GNU Library General Public License 第 2 版，来自该标签的 `COPYING`）。安装名是 `@rpath/libopenal.1.dylib`。
- x86_64：OpenAL Soft 1.15.1，仍是上游 beatoraja 0.8.9 jar 里的那一版。许可证原文是 `LICENSES/OpenAL-Soft-1.15.1-LGPL-2.0.txt`。这一份上游 `COPYING` 与 1.21.1 的文本不完全相同，所以两份都附上。x86_64 切片的 LC_UUID 是 `54903F53-A683-3AEA-8B64-C7939B878F21`，与上游 0.8.9 jar 里的 `openal.dylib` 相同。安装名保持上游 jar 里的名字，这次没有改。

来源：

- https://github.com/kcat/openal-soft
- 1.21.1：https://github.com/kcat/openal-soft/tree/1.21.1
- 1.15.1：https://github.com/kcat/openal-soft/releases/tag/openal-soft-1.15.1

它是独立的 dylib，没有静态链进 jar。LGPL 要求接收者能够替换这份库；替换时要保留 LWJGL 2 所依赖的 OpenAL 入口。

### libGDX（Apache-2.0）

全文见 `LICENSES/Apache-2.0.txt`。

libGDX 1.9.9 把 `os.arch=aarch64` 当成 32 位，所以会加载 jar 根上不带 `64` 的文件名。上游 0.8.9 jar 里这三个不带 `64` 的文件是 i386。本包换成 arm64 薄二进制，安装名是 `@rpath/` 加文件名：

- `libgdx.dylib`（arm64）：用 libGDX 1.9.9 标签 `gdx-parent-1.9.9` 的 `gdx/jni` 为 arm64 编译。源码：https://github.com/libgdx/libgdx/tree/gdx-parent-1.9.9
- `libgdx-freetype.dylib`（arm64）：libGDX 1.12.1 官方 desktop natives 中的 arm64 FreeType 库，安装名改成 1.9.9 会加载的文件名。源码标签：https://github.com/libgdx/libgdx/tree/gdx-parent-1.12.1
- `libgdx-controllers-desktop.dylib`（arm64）：用 libGDX 1.9.9 的 `extensions/gdx-controllers/gdx-controllers-desktop/jni` 为 arm64 编译。手柄实现是该目录自带的 OIS 1.4（`ois-v1-4svn`），按其中的源码编译。JNI 包装属于 libGDX（Apache-2.0）。OIS 是 zlib/libpng 许可，短声明原文在 `LICENSES/OIS-zlib-libpng.txt`，版权人 Phillip Castaneda。源码和许可原文在上述 libGDX 1.9.9 标签的同一目录。

下面三个带 `64` 的文件也在 jar 根，是 x86_64 + arm64 通用二进制。arm64 切片与上面对应的薄二进制是同一镜像（LC_UUID 相同），用 lipo 并进原来的 x86_64 切片。x86_64 切片的 LC_UUID 与上游 0.8.9 jar 里的同名库相同。

| jar 根文件 | 架构 | 与谁的 LC_UUID 相同 |
| --- | --- | --- |
| `libgdx64.dylib` | arm64 `2B633E67-56B2-3DD7-B24A-E7669B4D509B` | 本包 `libgdx.dylib` |
| `libgdx64.dylib` | x86_64 `805F7A68-8FE9-3FC6-8CB5-7B16DA1343AE` | 上游 0.8.9 jar 的 `libgdx64.dylib` |
| `libgdx-freetype64.dylib` | arm64 `C38567E5-9A79-34A1-B81C-18D9CF7AB16E` | 本包 `libgdx-freetype.dylib` |
| `libgdx-freetype64.dylib` | x86_64 `92B4A6B6-1AF0-3DF7-BF62-1C779AA00A1B` | 上游 0.8.9 jar 的 `libgdx-freetype64.dylib` |
| `libgdx-controllers-desktop64.dylib` | arm64 `12879353-6574-3D9C-A5D0-D39D5605ED81` | 本包 `libgdx-controllers-desktop.dylib` |
| `libgdx-controllers-desktop64.dylib` | x86_64 `E73D2216-7533-3C9E-B07A-F60131C224CB` | 上游 0.8.9 jar 的 `libgdx-controllers-desktop64.dylib` |

`libgdx64.dylib` 两个切片的安装名都是 `@rpath/libgdx64.dylib`。这次没有改它，也没有改三个不带 `64` 的文件。

`libgdx-freetype64.dylib` 和 `libgdx-controllers-desktop64.dylib` 的 arm64 切片原来的安装名是构建目录上的绝对路径。2026-10-21 用 `install_name_tool` 把这两个通用二进制的 id 改成 `@rpath/` 加各自的文件名，x86_64 和 arm64 一起改，然后做了 ad-hoc 签名。改完后 `otool -D` 给出的是 `@rpath/libgdx-freetype64.dylib` 和 `@rpath/libgdx-controllers-desktop64.dylib`。`lipo -info` 仍然同时有 x86_64 和 arm64。

### LWJGL 2（BSD）

全文见 `LICENSES/LWJGL-2-BSD.txt`。

`liblwjgl.dylib` 有两份，逐字节相同：一份在 jar 根，一份在 `natives/liblwjgl.dylib`。它是 x86_64 + arm64 通用二进制。

- arm64 切片：LWJGL 2.9.3-rc1，来自 HMCL 发布的 Maven 构件 `org.glavo.hmcl:lwjgl2-natives:2.9.3-rc1-osx-arm64`：https://repo1.maven.org/maven2/org/glavo/hmcl/lwjgl2-natives/2.9.3-rc1-osx-arm64/ 。安装名是相对路径 `liblwjgl-arm64.dylib`。
- x86_64 切片：仍是上游 jar 里的 LWJGL 2.9.2。LC_UUID 是 `31F32C62-2348-CD5E-0939-54EBA85C18FA`，与上游 0.8.9 jar 的 `liblwjgl.dylib` 相同。安装名是相对路径 `liblwjgl-i86_64.dylib`。

这次没有改这个库的安装名。

### PortAudio（MIT）

`natives/libjportaudio.dylib` 是 x86_64 + arm64 通用二进制，安装名是 `@rpath/libjportaudio.dylib`。它不在 jar 里面。

已与官方 zip `beatoraja0.8.9-full-win64.zip` 中的 `natives/libjportaudio.dylib` 比较（`unzip -p` 之后 `cmp`）：

- 两边的 `lipo -info` 都是 x86_64 和 arm64。
- 两边的 `otool -D` 都是 `@rpath/libjportaudio.dylib`。
- arm64 的 LC_UUID 都是 `8D81C5B6-3E30-3547-8FD6-5E04A41DCCE7`。
- x86_64 的 LC_UUID 都是 `FA639FDE-2728-330D-9756-754DD9459AFD`。
- 整文件 `cmp` 不一致。官方原件带链接器签名，本包这份是 ad-hoc 签名。
- 去掉代码签名之后，arm64 切片和 x86_64 切片都逐字节一致。

因此它是上游 beatoraja 0.8.9 包里的那份通用二进制，不是本机重编的库。整文件字节不同，只因为签名换成了 ad-hoc。这里不记载构建者，也不记载 PortAudio 的源码版本。

PortAudio 是 MIT。项目地址：http://www.portaudio.com/ 和 https://github.com/PortAudio/portaudio 。全文是上游 `LICENSE.txt`，见 `LICENSES/PortAudio-MIT.txt`。

### JavaFX / OpenJFX

JavaFX 18.0.2 放在 `Contents/Resources/javafx`。这是 OpenJFX，许可为 GPL-2.0 with Classpath Exception。全文在包内 `Contents/Resources/javafx/legal`，发布树里的副本是 `LICENSES/OpenJFX-legal/`。

## 不要放进 git

发布包里的 `beatoraja.jar` 当前是 294039872 字节。改上面两个库的 install name 之前是 294040554 字节。两种大小都超过 GitHub 单文件 100MB 的限制。不要把 `beatoraja.jar` 或 `.app` 提交进 git。要发布，就把 zip 当作 GitHub Release 的附件。

`.gitignore` 忽略 `dist/`、`build/`、`*.zip`、`*.app/`、`*.jar` 和 `*.db`。父仓库的文件留在 submodule 工作区里，本仓库的提交只记录上面的 gitlink。

## 从零编译

需要 Xcode Command Line Tools（`clang`、`clang++`）、arm64 JDK 17、`curl`、`unzip`、`zip`、`lipo`、`install_name_tool`、`codesign`。从源码编译 `beatoraja.jar` 时还需要 Apache Ant。`scripts/build-arm64-natives.sh` 只用 arm64 JDK 17 的 JNI 头；`JAVA_HOME` 指向别的版本时，脚本会改用 `/usr/libexec/java_home -v 17 -a arm64` 或常见的 Temurin 17 / Zulu 17 安装位置。

### 第一步：克隆本仓库与子模块

```bash
git clone --recurse-submodules https://github.com/asdfghjkoiuy/beatoraja-macos-arm64.git
cd beatoraja-macos-arm64
```

已经有工作区、还没有子模块时：

```bash
git submodule update --init --depth 1
```

### 第二步：准备 beatoraja 安装目录与 OpenJFX

准备 OpenJFX 18.0.2 的 macOS aarch64 SDK。后面组装脚本的第二个参数是该 SDK 的 `lib` 目录，它的上一级要有 `legal/`。

安装目录可以是官方 beatoraja 0.8.9 发布包解压后的目录。标签 `0.8.9` 的源码树用 Ant 的 `build.xml` 编译 jar（上游 `Dockerfile` 的入口相同）：

```bash
cd upstreams/beatoraja
ant -lib /path/to/javafx-sdk-18.0.2/lib create_run_jar
```

产物是 `upstreams/beatoraja/build/beatoraja.jar`。把它放到安装目录根上。源码树里已经有 `natives/libjportaudio.dylib`、`skin/default`、`font/`、`defaultsound/`、`manual/`、`folder/`、`random/`。官方发布包还带有 `ir/minir-700.jar`，组装脚本需要这个文件。`liblwjgl.dylib` 和 `openal.dylib` 在 jar 里面，下一步会写到安装目录的 `natives/`。

### 第三步：编译 arm64 原生库并修补 jar

```bash
scripts/build-arm64-natives.sh
scripts/patch-beatoraja-jar.sh /path/to/beatoraja-0.8.9
```

`build-arm64-natives.sh` 从 `upstreams/libgdx/gdx/jni` 编译 `libgdx.dylib`（`-O2 -arch arm64 -fPIC -mmacosx-version-min=11.0 -DFIXED_POINT`，install name `@rpath/libgdx.dylib`），从 `upstreams/libgdx/extensions/gdx-controllers/gdx-controllers-desktop/jni` 编译 `libgdx-controllers-desktop.dylib`（`-O2 -arch arm64 -fPIC -mmacosx-version-min=11.0 -std=c++14`，`.mm` 和含 Objective-C 头的源文件用 `-x objective-c++`，链接 CoreServices、Carbon、IOKit、Cocoa）。FreeType 取自 Maven 构件 `gdx-freetype-platform-1.12.1-natives-desktop.jar` 里的 `libgdx-freetypearm64.dylib`，改名为 `libgdx-freetype.dylib` 并把 install name 设为 `@rpath/libgdx-freetype.dylib`。LWJGL 2 与 OpenAL 的 arm64 切片取自 `org.glavo.hmcl:lwjgl2-natives:2.9.3-rc1-osx-arm64`。两份构件都按 SHA256 校验。产物在 `build/arm64-natives/`。

`patch-beatoraja-jar.sh` 的第二个参数可以省略，默认就是 `build/arm64-natives`。它从目标 `beatoraja.jar` 抽出 x86_64 切片；若该文件已经是通用二进制，则先 `lipo -extract x86_64`，因此可以重复执行。再用 `lipo -create` 合成 `libgdx64.dylib`、`libgdx-freetype64.dylib`、`libgdx-controllers-desktop64.dylib`、`liblwjgl.dylib`、`openal.dylib`。三个带 `64` 的 libGDX 库和三个薄 arm64 库的 install name 设为 `@rpath/` 加各自的文件名。`liblwjgl.dylib` 与 `openal.dylib` 的 install name 保持各切片原来的值。全部做 ad-hoc 签名后，用 `zip -u` 写回 jar，并更新安装目录 `natives/liblwjgl.dylib` 与 `natives/openal.dylib`，再对 `natives/*.dylib` 签名。

### 第四步：组装 .app

```bash
scripts/assemble-release.sh \
  /path/to/beatoraja-0.8.9 \
  /path/to/javafx-sdk-18.0.2/lib
```

脚本写出 `dist/Beatoraja.app`。要换图标时，把 `.icns` 路径作为第三个参数传入。

## 运行

需要本机已安装的 arm64 Java 17（Temurin 或 Zulu）。启动脚本不会把某个家目录或某个 JavaFX SDK 路径写死。JavaFX 只用包内的 `Contents/Resources/javafx`，参数是 `--module-path` 指向该目录，以及 `--add-modules javafx.controls,javafx.fxml`。

Java 按下面的顺序查找。确认目标文件是绝对路径上的普通可执行文件，并且 Mach-O 头是 arm64 可执行文件、版本字符串为 17 之后，才会执行：

1. 包内 JRE（发布包默认没有）：`Contents/PlugIns/jre`，其次 `Contents/Resources/jre`
2. `JAVA_HOME` 下面的 `bin/java`（或 `Contents/Home/bin/java`）。`JAVA_HOME` 只当作目录前缀
3. `/usr/libexec/java_home -v 17 -a arm64`
4. 常见的 Zulu 17 / Temurin 17 安装位置，以及 Homebrew 的 `openjdk@17`

内存参数是 `-Xms4g -Xmx8g`。`-Djava.library.path` 和 `-Dorg.lwjgl.librarypath` 指向包内 `natives`。工作目录是包内游戏根 `Contents/Resources/beatoraja`。

找不到 Java 时，终端会打印原因，并用 `osascript` 的参数（不是拼进脚本正文）显示对话框。

下载后先把 `Beatoraja.app` 拖进「应用程序」，再从那里打开。macOS 对仍带隔离属性、并从「下载」文件夹直接打开的 app，会做 App Translocation，把实际启动路径指到一个只读的转位副本。beatoraja 要在包内游戏根写入数据库和配置。启动路径若是这个只读副本，写入会失败。先拖进「应用程序」再打开，用的是正常安装位置。

第一次启动时，beatoraja 会在包内游戏根生成空的数据库和配置。谱面目录需要在游戏里自己指定。

若系统提示无法验证开发者，在「隐私与安全性」中允许打开，或按住 Control 再点按后选择「打开」。

## 包里有什么

- 已替换 macOS 原生库的 `beatoraja.jar`
- `natives/`：`libjportaudio.dylib`、`liblwjgl.dylib`、`openal.dylib`
- `skin/default`
- `font/`、`defaultsound/`、`manual/`、`folder/`、`random/`
- `ir/minir-700.jar`
- JavaFX 18.0.2，以及 `Contents/Resources/javafx/legal`
- `Contents/Resources/licenses` 和包内的 `Contents/Resources/README.md`

没有 ModernChic、PeacefulPlay、曲库、成绩库、玩家目录、配置、截图、练习记录、备份或崩溃日志。皮肤目录只有上游自带的 default。

## 重新组装

从零编译见上面的四步。只重新打包时，准备一份已经换好上述原生库的 beatoraja 安装目录，以及 JavaFX SDK 18.0.2 的 `lib` 目录（其上一级要有 `legal/`）。发布树里要有 `LICENSES/` 和本说明。未传第三个参数时使用 `assets/AppIcon.icns`；传入路径则仍使用该图标。

```bash
scripts/assemble-release.sh \
  /path/to/beatoraja-install \
  /path/to/javafx-sdk-18.0.2/lib
```

脚本用 `cp -c` 复制允许清单里的文件，写成 `dist/Beatoraja.app`，把 `LICENSES/`、本说明和 JavaFX `legal/` 放进 app，对 app 执行 `chmod -R go-w` 去掉组和其他用户的写权限，并对 app 和放进去的 dylib 做 ad-hoc 签名，同时去掉 quarantine。曲库、玩家目录、配置和第三方皮肤不会被复制。
