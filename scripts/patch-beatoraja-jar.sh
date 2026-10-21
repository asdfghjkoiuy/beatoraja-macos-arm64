#!/bin/bash
# 把 build/arm64-natives 里的 arm64 切片与安装目录 beatoraja.jar 中的 x86_64 切片合成通用二进制。
# 已是通用二进制时先抽出 x86_64，因此可以重复执行。
# 不改 liblwjgl.dylib 与 openal.dylib 各切片原有的 install name。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "用法: $0 <beatoraja安装目录> [arm64-natives目录]" >&2
  echo "未传入第二个参数时使用仓库内的 build/arm64-natives。" >&2
  exit 1
fi

INSTALL="$(cd "$1" && pwd)"
if [ "$#" -eq 2 ]; then
  NATIVES="$(cd "$2" && pwd)"
else
  NATIVES="${ROOT}/build/arm64-natives"
fi
JAR="${INSTALL}/beatoraja.jar"
NATIVE_DIR="${INSTALL}/natives"

die() {
  echo "错误：$*" >&2
  exit 1
}

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令 $1"
}

for tool in unzip zip lipo install_name_tool codesign; do
  need_tool "${tool}"
done

[ -f "${JAR}" ] || die "缺少 ${JAR}"
[ -d "${NATIVE_DIR}" ] || die "缺少 ${NATIVE_DIR}"

for name in \
  libgdx.dylib \
  libgdx-freetype.dylib \
  libgdx-controllers-desktop.dylib \
  liblwjgl.dylib \
  openal.dylib
do
  [ -f "${NATIVES}/${name}" ] || die "缺少 arm64 库 ${NATIVES}/${name}"
  archs="$(lipo -archs "${NATIVES}/${name}")"
  [ "${archs}" = "arm64" ] || die "${name} 应为 arm64 薄二进制，实际为 ${archs}"
done

work="$(mktemp -d "${TMPDIR:-/tmp}/beatoraja-patch.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/jar" "${work}/x64" "${work}/out"

(
  cd "${work}/jar"
  unzip -qq -o "${JAR}" \
    libgdx64.dylib \
    libgdx-freetype64.dylib \
    libgdx-controllers-desktop64.dylib \
    liblwjgl.dylib \
    openal.dylib
)

extract_x86_64() {
  local src="$1" dest="$2"
  local archs
  archs="$(lipo -archs "${src}")"
  case " ${archs} " in
    *" x86_64 "*) ;;
    *) die "$(basename "${src}") 没有 x86_64 切片（${archs}），无法重复合成" ;;
  esac
  if [ "${archs}" = "x86_64" ]; then
    cp "${src}" "${dest}"
  else
    lipo -extract x86_64 "${src}" -output "${dest}"
  fi
}

# jar 内的文件名：arm64 来源文件名
pairs=(
  "libgdx64.dylib:libgdx.dylib"
  "libgdx-freetype64.dylib:libgdx-freetype.dylib"
  "libgdx-controllers-desktop64.dylib:libgdx-controllers-desktop.dylib"
  "liblwjgl.dylib:liblwjgl.dylib"
  "openal.dylib:openal.dylib"
)

for pair in "${pairs[@]}"; do
  jar_name="${pair%%:*}"
  arm_name="${pair##*:}"
  extract_x86_64 "${work}/jar/${jar_name}" "${work}/x64/${jar_name}"
  lipo -create \
    "${work}/x64/${jar_name}" \
    "${NATIVES}/${arm_name}" \
    -output "${work}/out/${jar_name}"
  fat=" $(lipo -archs "${work}/out/${jar_name}") "
  case "${fat}" in
    *" x86_64 "*) ;;
    *) die "${jar_name} 合成后的架构是${fat}" ;;
  esac
  case "${fat}" in
    *" arm64 "*) ;;
    *) die "${jar_name} 合成后的架构是${fat}" ;;
  esac
done

for name in libgdx.dylib libgdx-freetype.dylib libgdx-controllers-desktop.dylib; do
  cp "${NATIVES}/${name}" "${work}/out/${name}"
  install_name_tool -id "@rpath/${name}" "${work}/out/${name}"
done

for name in libgdx64.dylib libgdx-freetype64.dylib libgdx-controllers-desktop64.dylib; do
  install_name_tool -id "@rpath/${name}" "${work}/out/${name}"
done

for lib in "${work}/out/"*.dylib; do
  codesign --force --sign - "${lib}"
done

chmod u+w "${JAR}"
shopt -s nullglob
for lib in "${NATIVE_DIR}/"*.dylib; do
  chmod u+w "${lib}"
done
shopt -u nullglob

cp "${work}/out/liblwjgl.dylib" "${work}/out/openal.dylib" "${NATIVE_DIR}/"
for lib in "${NATIVE_DIR}/"*.dylib; do
  codesign --force --sign - "${lib}"
done
cp "${NATIVE_DIR}/liblwjgl.dylib" "${NATIVE_DIR}/openal.dylib" "${work}/out/"

jar_names=(
  libgdx.dylib
  libgdx64.dylib
  libgdx-freetype.dylib
  libgdx-freetype64.dylib
  libgdx-controllers-desktop.dylib
  libgdx-controllers-desktop64.dylib
  liblwjgl.dylib
  openal.dylib
)
for name in "${jar_names[@]}"; do
  touch "${work}/out/${name}"
done
(
  cd "${work}/out"
  zip -u "${JAR}" "${jar_names[@]}"
)

echo "已更新 ${JAR}"
echo "已更新 ${NATIVE_DIR}/liblwjgl.dylib 与 ${NATIVE_DIR}/openal.dylib"
for name in "${jar_names[@]}"; do
  echo "-- ${name}"
  lipo -info "${work}/out/${name}"
  otool -D "${work}/out/${name}"
done
