#!/bin/bash
# 从本机已有的 beatoraja 安装、JavaFX lib 和图标组装 arm64 发布包。
# 不下载文件，不附带 JDK，不复制曲库、玩家目录、配置或第三方皮肤。
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "用法: $0 <beatoraja安装目录> <javafx的lib目录> [AppIcon.icns]" >&2
  echo "未传入图标时使用仓库内的 assets/AppIcon.icns。" >&2
  exit 1
fi

SRC="$(cd "$1" && pwd)"
JAVAFX_LIB="$(cd "$2" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -eq 3 ]; then
  ICON="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
else
  ICON="${ROOT}/assets/AppIcon.icns"
fi
APP="${ROOT}/dist/Beatoraja.app"
GAME="${APP}/Contents/Resources/beatoraja"
LAUNCHER="${ROOT}/scripts/beatoraja-launcher.sh"

need() {
  if [ ! -e "$1" ]; then
    echo "缺少：$1" >&2
    exit 1
  fi
}

need "${SRC}/beatoraja.jar"
need "${SRC}/natives/libjportaudio.dylib"
need "${SRC}/natives/liblwjgl.dylib"
need "${SRC}/natives/openal.dylib"
need "${SRC}/skin/default"
need "${SRC}/font/VL-Gothic-Regular.ttf"
need "${SRC}/ir/minir-700.jar"
need "${SRC}/defaultsound"
need "${SRC}/manual"
need "${SRC}/folder"
need "${SRC}/random"
need "${JAVAFX_LIB}/javafx.controls.jar"
need "${JAVAFX_LIB}/javafx.fxml.jar"
need "${ICON}"
need "${LAUNCHER}"
need "${ROOT}/README.md"
need "${ROOT}/LICENSES"
JAVAFX_LEGAL="$(cd "$(dirname "${JAVAFX_LIB}")/legal" && pwd)"
need "${JAVAFX_LEGAL}/javafx.base/LICENSE"
need "${JAVAFX_LEGAL}/javafx.base/ASSEMBLY_EXCEPTION"
need "${JAVAFX_LEGAL}/javafx.base/ADDITIONAL_LICENSE_INFO"

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" \
  "${APP}/Contents/Resources/javafx" \
  "${GAME}/natives" \
  "${GAME}/skin" \
  "${GAME}/ir"

cp -c "${SRC}/beatoraja.jar" "${GAME}/beatoraja.jar"
cp -c "${SRC}/natives/libjportaudio.dylib" \
  "${SRC}/natives/liblwjgl.dylib" \
  "${SRC}/natives/openal.dylib" \
  "${GAME}/natives/"
cp -cR "${SRC}/skin/default" "${GAME}/skin/"
cp -cR "${SRC}/font" "${SRC}/defaultsound" "${SRC}/manual" "${SRC}/folder" "${SRC}/random" "${GAME}/"
cp -c "${SRC}/ir/minir-700.jar" "${GAME}/ir/minir-700.jar"
cp -c "${JAVAFX_LIB}/"* "${APP}/Contents/Resources/javafx/"
mkdir -p "${APP}/Contents/Resources/javafx/legal" "${APP}/Contents/Resources/licenses"
cp -cR "${JAVAFX_LEGAL}/." "${APP}/Contents/Resources/javafx/legal/"
cp -cR "${ROOT}/LICENSES/." "${APP}/Contents/Resources/licenses/"
cp "${ROOT}/README.md" "${APP}/Contents/Resources/README.md"
cp -c "${ICON}" "${APP}/Contents/Resources/AppIcon.icns"
cp "${LAUNCHER}" "${APP}/Contents/MacOS/beatoraja"
chmod 755 "${APP}/Contents/MacOS/beatoraja"

cat > "${APP}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>beatoraja</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>local.unofficial.beatoraja.macos-arm64</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>beatoraja</string>
	<key>CFBundleDisplayName</key>
	<string>beatoraja</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.8.9</string>
	<key>CFBundleVersion</key>
	<string>0.8.9</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSRequiresAquaSystemAppearance</key>
	<false/>
</dict>
</plist>
EOF

find "${APP}" -name .DS_Store -delete
chmod -R go-w "${APP}"
chmod 755 "${APP}/Contents/MacOS/beatoraja"
xattr -dr com.apple.quarantine "${APP}" || true

while IFS= read -r -d '' lib; do
  codesign --force --sign - "${lib}"
done < <(find "${APP}" -type f -name '*.dylib' -print0)
codesign --force --sign - "${APP}"
xattr -dr com.apple.quarantine "${APP}" || true

python3 - "${APP}" << 'PY'
import os, sys
app = sys.argv[1]
game = os.path.join(app, "Contents", "Resources", "beatoraja")
errors = []
if os.path.exists(os.path.join(app, "Contents", "PlugIns", "jre")):
    errors.append("发布包不应包含 JDK")
skin = os.path.join(game, "skin")
names = sorted(os.listdir(skin)) if os.path.isdir(skin) else []
if names != ["default"]:
    errors.append("皮肤目录应为且仅为 default，实际为: " + ", ".join(names))
banned = [
    "songdata.db", "songinfo.db", "config.json", "config_sys.json",
    "config_player.json", "player", "practice", "screenshot",
    "backup-pre-0.8.9", "oldbeatoraja.jar",
]
for name in banned:
    if os.path.exists(os.path.join(game, name)):
        errors.append("不应包含 " + name)
for dirpath, dirnames, filenames in os.walk(game):
    for name in dirnames + filenames:
        lower = name.lower()
        if lower.startswith("hs_err") or lower.startswith("score") and lower.endswith(".db"):
            errors.append(os.path.join(dirpath, name))
        if lower.endswith(".dll") or lower.startswith("beatoraja_log"):
            errors.append(os.path.join(dirpath, name))
home_mark = ("/Users/" + os.environ["USER"]).encode()
secret_mark = ("cpass" + "word").encode()
for dirpath, dirnames, filenames in os.walk(app):
    for name in filenames:
        path = os.path.join(dirpath, name)
        try:
            data = open(path, "rb").read()
        except IsADirectoryError:
            continue
        if home_mark in data or secret_mark in data:
            errors.append("敏感字符串: " + path)
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY

echo "已组装：${APP}"
