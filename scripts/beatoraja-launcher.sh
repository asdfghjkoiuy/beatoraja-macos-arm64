#!/bin/bash
# beatoraja 0.8.9。工作目录是包内游戏根。JavaFX 与 JRE 都只用包内相对路径。
set -euo pipefail

fail() {
  local msg="$1"
  printf '%s\n' "错误：${msg}" >&2
  /usr/bin/osascript - "$msg" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
    display alert "beatoraja 无法启动" message (item 1 of argv)
end run
APPLESCRIPT
  exit 1
}

CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${CONTENTS}/Resources/beatoraja"
JAVAFX="${CONTENTS}/Resources/javafx"
cd "${ROOT}"

# 用 od 读 Mach-O 头。通过之后才允许执行。
is_arm64_macho_exe() {
  local path="$1"
  local filehead magic nfat_hex nfat
  local i rec_off rec cputype_hex offset_hex offset
  case "${path}" in
    /*) ;;
    *) return 1 ;;
  esac
  [[ "${path}" == *$'\n'* ]] && return 1
  [ -f "${path}" ] && [ -x "${path}" ] || return 1

  _be_od_hex() {
    local off="$1"
    local nbytes="$2"
    local raw
    raw="$(/usr/bin/od -An -v -t x1 -N "${nbytes}" -j "${off}" -- "${path}" 2>/dev/null | /usr/bin/tr -d '[:space:]' | /usr/bin/tr '[:upper:]' '[:lower:]')" || return 1
    [ "${#raw}" -eq $((nbytes * 2)) ] || return 1
    printf '%s' "${raw}"
  }

  _be_hex_dec() {
    local h="$1"
    [[ "${h}" =~ ^[0-9a-f]+$ ]] || return 1
    [ "${#h}" -le 16 ] || return 1
    printf '%s' "$((16#${h}))"
  }

  _be_thin_exec() {
    local off="$1"
    local hdr
    hdr="$(_be_od_hex "${off}" 16)" || return 1
    [ "${hdr:0:8}" = "cffaedfe" ] || return 1
    [ "${hdr:8:8}" = "0c000001" ] || return 1
    [ "${hdr:24:8}" = "02000000" ] || return 1
    return 0
  }

  filehead="$(_be_od_hex 0 8)" || return 1
  magic="${filehead:0:8}"
  nfat_hex="${filehead:8:8}"
  if [ "${magic}" = "cafebabe" ] || [ "${magic}" = "cafebabf" ]; then
    nfat="$(_be_hex_dec "${nfat_hex}")" || return 1
    if [ "${nfat}" -lt 1 ] || [ "${nfat}" -gt 20 ]; then
      return 1
    fi
    i=0
    while [ "${i}" -lt "${nfat}" ]; do
      if [ "${magic}" = "cafebabe" ]; then
        rec_off=$((8 + i * 20))
        rec="$(_be_od_hex "${rec_off}" 20)" || return 1
        cputype_hex="${rec:0:8}"
        offset_hex="${rec:16:8}"
      else
        rec_off=$((8 + i * 32))
        rec="$(_be_od_hex "${rec_off}" 32)" || return 1
        cputype_hex="${rec:0:8}"
        offset_hex="${rec:16:16}"
      fi
      if [ "${cputype_hex}" = "0100000c" ]; then
        offset="$(_be_hex_dec "${offset_hex}")" || return 1
        if _be_thin_exec "${offset}"; then
          return 0
        fi
      fi
      i=$((i + 1))
    done
    return 1
  fi
  _be_thin_exec 0
}

java_ok() {
  local bin="$1"
  if ! is_arm64_macho_exe "${bin}"; then
    return 1
  fi
  local ver
  ver="$("${bin}" -version 2>&1 || true)"
  printf '%s\n' "${ver}" | /usr/bin/grep -Eq 'version "17(\.|")' || return 1
  return 0
}

JAVA=""
consider() {
  local bin="$1"
  if [ -z "${JAVA}" ] && java_ok "${bin}"; then
    JAVA="${bin}"
  fi
}

consider "${CONTENTS}/PlugIns/jre/bin/java"
consider "${CONTENTS}/PlugIns/jre/Contents/Home/bin/java"
consider "${CONTENTS}/Resources/jre/bin/java"
consider "${CONTENTS}/Resources/jre/Contents/Home/bin/java"

if [ -n "${JAVA_HOME:-}" ]; then
  case "${JAVA_HOME}" in
    ""|-*|*$'\n'*) ;;
    /*)
      consider "${JAVA_HOME}/bin/java"
      consider "${JAVA_HOME}/Contents/Home/bin/java"
      ;;
  esac
fi

if [ -z "${JAVA}" ] && [ -x /usr/libexec/java_home ]; then
  jh="$(/usr/libexec/java_home -v 17 -a arm64 2>/dev/null || true)"
  case "${jh}" in
    ""|-*|*$'\n'*) ;;
    /*)
      consider "${jh}/bin/java"
      ;;
  esac
fi

if [ -z "${JAVA}" ]; then
  shopt -s nullglob
  candidates=()
  if [ -n "${HOME:-}" ]; then
    candidates+=("${HOME}/Library/Java/JavaVirtualMachines/"*/Contents/Home/bin/java)
  fi
  candidates+=(
    /Library/Java/JavaVirtualMachines/zulu-17*.jdk/Contents/Home/bin/java
    /Library/Java/JavaVirtualMachines/temurin-17*.jdk/Contents/Home/bin/java
    /Library/Java/JavaVirtualMachines/temurin-17*.jre/Contents/Home/bin/java
    /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java
    /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java
  )
  for c in "${candidates[@]}"; do
    consider "${c}"
    [ -n "${JAVA}" ] && break
  done
fi

[ -n "${JAVA}" ] || fail "找不到 arm64 Java 17。请安装 Temurin 或 Zulu 17（Apple Silicon），或把 JAVA_HOME 指到该 JDK 的 Home 目录。"
[ -f "${JAVAFX}/javafx.controls.jar" ] || fail "包内缺少 JavaFX。"
[ -f "${JAVAFX}/javafx.fxml.jar" ] || fail "包内缺少 JavaFX FXML。"
[ -f "${ROOT}/beatoraja.jar" ] || fail "包内缺少 beatoraja.jar。"
[ -f "${ROOT}/natives/liblwjgl.dylib" ] || fail "包内缺少 natives/liblwjgl.dylib。"
[ -f "${ROOT}/natives/libjportaudio.dylib" ] || fail "包内缺少 natives/libjportaudio.dylib。"

unset JAVA_TOOL_OPTIONS JDK_JAVA_OPTIONS _JAVA_OPTIONS DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH
export _JAVA_OPTIONS="-Dsun.java2d.opengl=true -Dawt.useSystemAAFontSettings=on -Dswing.aatext=true"

exec "${JAVA}" \
  -Xms4g -Xmx8g \
  -Xdock:name=beatoraja \
  --module-path "${JAVAFX}" \
  --add-modules javafx.controls,javafx.fxml \
  -Djava.library.path="${ROOT}/natives" \
  -Dorg.lwjgl.librarypath="${ROOT}/natives" \
  -jar "${ROOT}/beatoraja.jar" "$@"
