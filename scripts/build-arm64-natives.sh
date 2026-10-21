#!/bin/bash
# 从 upstreams/libgdx（gdx-parent-1.9.9）编译 arm64 的 libgdx / OIS，
# 并取出 FreeType 1.12.1 与 LWJGL 2.9.3-rc1 的 arm64 切片。
# 产物在 build/arm64-natives/，该目录被 .gitignore 排除。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GDX="${ROOT}/upstreams/libgdx"
GDX_JNI="${GDX}/gdx/jni"
CTRL_JNI="${GDX}/extensions/gdx-controllers/gdx-controllers-desktop/jni"
OUT="${ROOT}/build/arm64-natives"
OBJ="${ROOT}/build/obj"
CACHE="${ROOT}/build/maven-cache"
LIBGDX_COMMIT="404ad6893f58fe880b91416df1a3af15eb3c6ed8"

FT_URL="https://repo1.maven.org/maven2/com/badlogicgames/gdx/gdx-freetype-platform/1.12.1/gdx-freetype-platform-1.12.1-natives-desktop.jar"
FT_NAME="gdx-freetype-platform-1.12.1-natives-desktop.jar"
FT_SHA256="d60e59376d505a993ec8ba20a30477af06902b1e2927ff2e375effdbf425d941"

LW_URL="https://repo1.maven.org/maven2/org/glavo/hmcl/lwjgl2-natives/2.9.3-rc1-osx-arm64/lwjgl2-natives-2.9.3-rc1-osx-arm64.jar"
LW_NAME="lwjgl2-natives-2.9.3-rc1-osx-arm64.jar"
LW_SHA256="17c9e680c0f2bc403b32cea340b4c32ff08e4e2d192e58ba1be6ca8aff705ba2"

die() {
  echo "错误：$*" >&2
  exit 1
}

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令 $1"
}

is_arm64_jdk17() {
  local home="$1"
  local archs ver
  [ -n "${home}" ] || return 1
  [ -f "${home}/include/jni.h" ] || return 1
  [ -f "${home}/include/darwin/jni_md.h" ] || return 1
  [ -x "${home}/bin/java" ] || return 1
  archs="$(lipo -archs "${home}/bin/java" 2>/dev/null || true)"
  case " ${archs} " in
    *" arm64 "*) ;;
    *) return 1 ;;
  esac
  ver="$("${home}/bin/java" -version 2>&1 || true)"
  printf '%s\n' "${ver}" | grep -Eq 'version "17(\.|")' || return 1
  return 0
}

find_jdk17() {
  local jh c
  if is_arm64_jdk17 "${JAVA_HOME:-}"; then
    printf '%s\n' "${JAVA_HOME}"
    return 0
  fi
  if [ -x /usr/libexec/java_home ]; then
    jh="$(/usr/libexec/java_home -v 17 -a arm64 2>/dev/null || true)"
    if is_arm64_jdk17 "${jh}"; then
      printf '%s\n' "${jh}"
      return 0
    fi
  fi
  shopt -s nullglob
  local candidates=()
  if [ -n "${HOME:-}" ]; then
    candidates+=("${HOME}/Library/Java/JavaVirtualMachines/"*/Contents/Home)
  fi
  candidates+=(
    /Library/Java/JavaVirtualMachines/zulu-17*.jdk/Contents/Home
    /Library/Java/JavaVirtualMachines/temurin-17*.jdk/Contents/Home
    /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
    /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
  )
  for c in "${candidates[@]}"; do
    if is_arm64_jdk17 "${c}"; then
      printf '%s\n' "${c}"
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

fetch_jar() {
  local url="$1" name="$2" sha="$3"
  local dest="${CACHE}/${name}" actual
  mkdir -p "${CACHE}"
  if [ -f "${dest}" ]; then
    actual="$(shasum -a 256 "${dest}" | awk '{print $1}')"
    if [ "${actual}" != "${sha}" ]; then
      echo "缓存 ${name} 的 SHA256 不符，重新下载"
      rm -f "${dest}"
    fi
  fi
  if [ ! -f "${dest}" ]; then
    echo "下载 ${url}"
    curl -fL --retry 5 --retry-all-errors --retry-delay 2 -o "${dest}.partial" "${url}"
    mv "${dest}.partial" "${dest}"
  else
    echo "使用缓存 ${name}"
  fi
  actual="$(shasum -a 256 "${dest}" | awk '{print $1}')"
  [ "${actual}" = "${sha}" ] || die "SHA256 不符：${name}"
}

compile_one() {
  local lang="$1" src="$2" obj="$3"
  shift 3
  echo "${lang} ${src#"${ROOT}/"}"
  if [ "${lang}" = "CC" ]; then
    clang "$@" -o "${obj}" "${src}"
  elif [ "${lang}" = "OBJCXX" ]; then
    clang++ -x objective-c++ -std=c++14 "$@" -o "${obj}" "${src}"
  else
    clang++ -std=c++14 "$@" -o "${obj}" "${src}"
  fi
}

require_arm64() {
  local path="$1"
  local archs
  archs="$(lipo -archs "${path}")"
  [ "${archs}" = "arm64" ] || die "$(basename "${path}") 不是 arm64 薄二进制（${archs}）"
}

require_id() {
  local path="$1" expect="$2"
  local got
  got="$(otool -D "${path}" | awk 'NR==2 {print $1}')"
  [ "${got}" = "${expect}" ] || die "$(basename "${path}") 的 install name 是 ${got}，期望 ${expect}"
}

java_symbols() {
  nm -gUj "$1" | grep '_Java_' | sort -u
}

check_symbols() {
  local lib="$1" expected_file="$2"
  local have missing extra
  have="$(mktemp)"
  java_symbols "${lib}" > "${have}"
  missing="$(comm -23 "${expected_file}" "${have}" || true)"
  extra="$(comm -13 "${expected_file}" "${have}" || true)"
  rm -f "${have}"
  if [ -n "${missing}" ] || [ -n "${extra}" ]; then
    echo "JNI 符号与 libGDX 1.9.9 不一致：$(basename "${lib}")" >&2
    if [ -n "${missing}" ]; then
      echo "缺少：" >&2
      printf '%s\n' "${missing}" >&2
    fi
    if [ -n "${extra}" ]; then
      echo "多出：" >&2
      printf '%s\n' "${extra}" >&2
    fi
    exit 1
  fi
}

reject_home_path() {
  local path="$1"
  if [ -n "${HOME:-}" ] && strings -a "${path}" | grep -F -q "${HOME}"; then
    die "$(basename "${path}") 含有当前用户的家目录路径"
  fi
}

for tool in clang clang++ curl unzip lipo install_name_tool codesign shasum nm otool strings; do
  need_tool "${tool}"
done

[ -d "${GDX_JNI}" ] || die "缺少 ${GDX_JNI}。请先执行 git submodule update --init --depth 1"
[ -d "${CTRL_JNI}" ] || die "缺少 ${CTRL_JNI}。请先执行 git submodule update --init --depth 1"
if [ -e "${GDX}/.git" ]; then
  actual="$(git -C "${GDX}" rev-parse HEAD)"
  [ "${actual}" = "${LIBGDX_COMMIT}" ] || die "upstreams/libgdx 应为 ${LIBGDX_COMMIT}，实际是 ${actual}"
fi

JDK="$(find_jdk17)" || die "找不到带 JNI 头文件的 arm64 JDK 17"
echo "JDK ${JDK}"

rm -rf "${OUT}" "${OBJ}"
mkdir -p "${OUT}" "${OBJ}/libgdx" "${OBJ}/controllers"

GDX_CFLAGS=(
  -c -O2 -arch arm64 -DFIXED_POINT -fPIC -mmacosx-version-min=11.0
  -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable
  -ffile-prefix-map="${ROOT}=."
  -ffile-prefix-map="${JDK}=/jdk"
  -fdebug-prefix-map="${ROOT}=."
  -fdebug-prefix-map="${JDK}=/jdk"
)
GDX_INC=(
  -I"${GDX_JNI}" -I"${GDX_JNI}/gdx2d" -I"${GDX_JNI}/etc1"
  -I"${JDK}/include" -I"${JDK}/include/darwin"
)

for src in memcpy_wrap.c gdx2d/gdx2d.c; do
  compile_one CC "${GDX_JNI}/${src}" "${OBJ}/libgdx/$(echo "${src}" | tr '/' '_').o" \
    "${GDX_CFLAGS[@]}" "${GDX_INC[@]}"
done
for src in \
  com.badlogic.gdx.graphics.glutils.ETC1.cpp \
  etc1/etc1_utils.cpp \
  com.badlogic.gdx.math.Matrix4.cpp \
  com.badlogic.gdx.graphics.g2d.Gdx2DPixmap.cpp \
  gdx2d/jpgd_c.cpp \
  gdx2d/jpgd.cpp \
  com.badlogic.gdx.utils.BufferUtils.cpp
do
  compile_one CXX "${GDX_JNI}/${src}" "${OBJ}/libgdx/$(echo "${src}" | tr '/' '_').o" \
    "${GDX_CFLAGS[@]}" "${GDX_INC[@]}"
done

echo "LINK libgdx.dylib"
clang++ -shared -arch arm64 -mmacosx-version-min=11.0 \
  -Wl,-install_name,@rpath/libgdx.dylib \
  -o "${OUT}/libgdx.dylib" "${OBJ}/libgdx/"*.o
install_name_tool -id "@rpath/libgdx.dylib" "${OUT}/libgdx.dylib"

CTRL_CFLAGS=(
  -c -O2 -arch arm64 -fPIC -mmacosx-version-min=11.0
  -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable
  -Wno-deprecated-non-prototype -Wno-objc-method-access
  -ffile-prefix-map="${ROOT}=."
  -ffile-prefix-map="${JDK}=/jdk"
  -fdebug-prefix-map="${ROOT}=."
  -fdebug-prefix-map="${JDK}=/jdk"
)
CTRL_INC=(
  -I"${CTRL_JNI}" -I"${CTRL_JNI}/ois-v1-4svn/includes"
  -I"${JDK}/include" -I"${JDK}/include/darwin"
)
# .mm、OISInputManager.cpp，以及引入 #import 头的 MacHIDManager.cpp / MacJoyStick.cpp
# 按 Objective-C++ 编译。其余 .cpp 按 C++14。
OBJCXX_FILES=(
  ois-v1-4svn/src/OISInputManager.cpp
  ois-v1-4svn/src/mac/MacHIDManager.cpp
  ois-v1-4svn/src/mac/MacJoyStick.cpp
)
shopt -s nullglob
for src in "${CTRL_JNI}/ois-v1-4svn/src/mac/"*.mm; do
  OBJCXX_FILES+=("${src#"${CTRL_JNI}/"}")
done
shopt -u nullglob

compile_one CC "${CTRL_JNI}/memcpy_wrap.c" "${OBJ}/controllers/memcpy_wrap.o" \
  "${CTRL_CFLAGS[@]}" "${CTRL_INC[@]}"
for src in \
  com.badlogic.gdx.controllers.desktop.ois.Ois.cpp \
  com.badlogic.gdx.controllers.desktop.ois.OisJoystick.cpp \
  ois-v1-4svn/src/OISEffect.cpp \
  ois-v1-4svn/src/OISException.cpp \
  ois-v1-4svn/src/OISForceFeedback.cpp \
  ois-v1-4svn/src/OISJoyStick.cpp \
  ois-v1-4svn/src/OISKeyboard.cpp \
  ois-v1-4svn/src/OISObject.cpp
do
  compile_one CXX "${CTRL_JNI}/${src}" "${OBJ}/controllers/$(echo "${src}" | tr '/' '_').o" \
    "${CTRL_CFLAGS[@]}" "${CTRL_INC[@]}"
done
for src in "${OBJCXX_FILES[@]}"; do
  compile_one OBJCXX "${CTRL_JNI}/${src}" "${OBJ}/controllers/$(echo "${src}" | tr '/' '_').o" \
    "${CTRL_CFLAGS[@]}" "${CTRL_INC[@]}"
done

echo "LINK libgdx-controllers-desktop.dylib"
clang++ -shared -arch arm64 -mmacosx-version-min=11.0 \
  -Wl,-install_name,@rpath/libgdx-controllers-desktop.dylib \
  -framework CoreServices -framework Carbon -framework IOKit -framework Cocoa \
  -o "${OUT}/libgdx-controllers-desktop.dylib" "${OBJ}/controllers/"*.o
install_name_tool -id "@rpath/libgdx-controllers-desktop.dylib" \
  "${OUT}/libgdx-controllers-desktop.dylib"

fetch_jar "${FT_URL}" "${FT_NAME}" "${FT_SHA256}"
fetch_jar "${LW_URL}" "${LW_NAME}" "${LW_SHA256}"

ft_extract="${ROOT}/build/maven-extract/freetype"
lw_extract="${ROOT}/build/maven-extract/lwjgl"
rm -rf "${ft_extract}" "${lw_extract}"
mkdir -p "${ft_extract}" "${lw_extract}"
unzip -qq -o "${CACHE}/${FT_NAME}" libgdx-freetypearm64.dylib -d "${ft_extract}"
cp "${ft_extract}/libgdx-freetypearm64.dylib" "${OUT}/libgdx-freetype.dylib"
install_name_tool -id "@rpath/libgdx-freetype.dylib" "${OUT}/libgdx-freetype.dylib"
unzip -qq -o "${CACHE}/${LW_NAME}" liblwjgl.dylib openal.dylib -d "${lw_extract}"
cp "${lw_extract}/liblwjgl.dylib" "${lw_extract}/openal.dylib" "${OUT}/"

ensure_thin_arm64() {
  local path="$1" info
  info="$(lipo -info "${path}")"
  case "${info}" in
    *"Non-fat file"*) ;;
    *"fat file"*)
      lipo -thin arm64 "${path}" -output "${path}.thin"
      mv "${path}.thin" "${path}"
      ;;
  esac
}

for lib in \
  libgdx.dylib \
  libgdx-controllers-desktop.dylib \
  libgdx-freetype.dylib \
  liblwjgl.dylib \
  openal.dylib
do
  ensure_thin_arm64 "${OUT}/${lib}"
  codesign --force --sign - "${OUT}/${lib}"
  require_arm64 "${OUT}/${lib}"
done

require_id "${OUT}/libgdx.dylib" "@rpath/libgdx.dylib"
require_id "${OUT}/libgdx-freetype.dylib" "@rpath/libgdx-freetype.dylib"
require_id "${OUT}/libgdx-controllers-desktop.dylib" "@rpath/libgdx-controllers-desktop.dylib"
reject_home_path "${OUT}/libgdx.dylib"
reject_home_path "${OUT}/libgdx-controllers-desktop.dylib"

sym_gdx="$(mktemp)"
sym_ctrl="$(mktemp)"
trap 'rm -f "${sym_gdx}" "${sym_ctrl}"' EXIT
cat > "${sym_gdx}" << 'EOF'
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_clear
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_drawCircle
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_drawLine
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_drawPixmap
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_drawRect
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_fillCircle
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_fillRect
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_fillTriangle
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_free
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_getFailureReason
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_getPixel
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_load
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_newPixmap
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_setBlend
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_setPixel
_Java_com_badlogic_gdx_graphics_g2d_Gdx2DPixmap_setScale
_Java_com_badlogic_gdx_graphics_glutils_ETC1_decodeImage
_Java_com_badlogic_gdx_graphics_glutils_ETC1_encodeImage
_Java_com_badlogic_gdx_graphics_glutils_ETC1_encodeImagePKM
_Java_com_badlogic_gdx_graphics_glutils_ETC1_formatHeader
_Java_com_badlogic_gdx_graphics_glutils_ETC1_getCompressedDataSize
_Java_com_badlogic_gdx_graphics_glutils_ETC1_getHeightPKM
_Java_com_badlogic_gdx_graphics_glutils_ETC1_getWidthPKM
_Java_com_badlogic_gdx_graphics_glutils_ETC1_isValidPKM
_Java_com_badlogic_gdx_math_Matrix4_det
_Java_com_badlogic_gdx_math_Matrix4_inv
_Java_com_badlogic_gdx_math_Matrix4_mul
_Java_com_badlogic_gdx_math_Matrix4_mulVec___3F_3F
_Java_com_badlogic_gdx_math_Matrix4_mulVec___3F_3FIII
_Java_com_badlogic_gdx_math_Matrix4_prj___3F_3F
_Java_com_badlogic_gdx_math_Matrix4_prj___3F_3FIII
_Java_com_badlogic_gdx_math_Matrix4_rot___3F_3F
_Java_com_badlogic_gdx_math_Matrix4_rot___3F_3FIII
_Java_com_badlogic_gdx_utils_BufferUtils_clear
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni__Ljava_nio_Buffer_2ILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni___3BILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni___3CILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni___3DILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni___3FILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni___3FLjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni___3IILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni___3JILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_copyJni___3SILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_find__Ljava_nio_Buffer_2IILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_find__Ljava_nio_Buffer_2IILjava_nio_Buffer_2IIF
_Java_com_badlogic_gdx_utils_BufferUtils_find__Ljava_nio_Buffer_2II_3FII
_Java_com_badlogic_gdx_utils_BufferUtils_find__Ljava_nio_Buffer_2II_3FIIF
_Java_com_badlogic_gdx_utils_BufferUtils_find___3FIILjava_nio_Buffer_2II
_Java_com_badlogic_gdx_utils_BufferUtils_find___3FIILjava_nio_Buffer_2IIF
_Java_com_badlogic_gdx_utils_BufferUtils_find___3FII_3FII
_Java_com_badlogic_gdx_utils_BufferUtils_find___3FII_3FIIF
_Java_com_badlogic_gdx_utils_BufferUtils_freeMemory
_Java_com_badlogic_gdx_utils_BufferUtils_getBufferAddress
_Java_com_badlogic_gdx_utils_BufferUtils_newDisposableByteBuffer
_Java_com_badlogic_gdx_utils_BufferUtils_transformV2M3Jni__Ljava_nio_Buffer_2II_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV2M3Jni___3FII_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV2M4Jni__Ljava_nio_Buffer_2II_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV2M4Jni___3FII_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV3M3Jni__Ljava_nio_Buffer_2II_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV3M3Jni___3FII_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV3M4Jni__Ljava_nio_Buffer_2II_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV3M4Jni___3FII_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV4M4Jni__Ljava_nio_Buffer_2II_3FI
_Java_com_badlogic_gdx_utils_BufferUtils_transformV4M4Jni___3FII_3FI
EOF
cat > "${sym_ctrl}" << 'EOF'
_Java_com_badlogic_gdx_controllers_desktop_ois_OisJoystick_getAxesCount
_Java_com_badlogic_gdx_controllers_desktop_ois_OisJoystick_getButtonCount
_Java_com_badlogic_gdx_controllers_desktop_ois_OisJoystick_getPovCount
_Java_com_badlogic_gdx_controllers_desktop_ois_OisJoystick_getSliderCount
_Java_com_badlogic_gdx_controllers_desktop_ois_OisJoystick_initialize
_Java_com_badlogic_gdx_controllers_desktop_ois_OisJoystick_update
_Java_com_badlogic_gdx_controllers_desktop_ois_Ois_createInputManager
_Java_com_badlogic_gdx_controllers_desktop_ois_Ois_createJoystick
_Java_com_badlogic_gdx_controllers_desktop_ois_Ois_getInputSystemName
_Java_com_badlogic_gdx_controllers_desktop_ois_Ois_getJoystickNames
_Java_com_badlogic_gdx_controllers_desktop_ois_Ois_getVersionName
_Java_com_badlogic_gdx_controllers_desktop_ois_Ois_getVersionNumber
EOF
check_symbols "${OUT}/libgdx.dylib" "${sym_gdx}"
check_symbols "${OUT}/libgdx-controllers-desktop.dylib" "${sym_ctrl}"
ft_syms="$(mktemp)"
lw_syms="$(mktemp)"
al_syms="$(mktemp)"
java_symbols "${OUT}/libgdx-freetype.dylib" > "${ft_syms}"
java_symbols "${OUT}/liblwjgl.dylib" > "${lw_syms}"
nm -gUj "${OUT}/openal.dylib" > "${al_syms}"
grep -q '_Java_com_badlogic_gdx_graphics_g2d_freetype_' "${ft_syms}" \
  || die "libgdx-freetype.dylib 缺少 FreeType JNI 符号"
grep -q '_Java_org_lwjgl_' "${lw_syms}" \
  || die "liblwjgl.dylib 缺少 LWJGL JNI 符号"
grep -q 'alGenSources' "${al_syms}" \
  || die "openal.dylib 缺少 OpenAL 入口"
rm -f "${ft_syms}" "${lw_syms}" "${al_syms}"

echo "已输出："
ls -la "${OUT}"
for lib in "${OUT}"/*.dylib; do
  echo "-- $(basename "${lib}")"
  lipo -info "${lib}"
  otool -D "${lib}"
done
echo "JNI 符号完整"
