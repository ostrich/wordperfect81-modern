#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/app"
COMPAT_DIR="$ROOT_DIR/compat"
COMPAT_LIB_DIR="$COMPAT_DIR/lib"
COMPAT_X11_ROOT="$COMPAT_DIR/x11/usr/X11R6"
FONT_ROOT="$COMPAT_DIR/fonts"
SHIM_LIB="$COMPAT_DIR/shim/libwp_compat_shim.so"
IN_BUBBLE_COMPAT_ROOT="/compat"
IN_BUBBLE_LIB_DIR="$IN_BUBBLE_COMPAT_ROOT/lib"
IN_BUBBLE_SHIM_LIB="$IN_BUBBLE_COMPAT_ROOT/shim/libwp_compat_shim.so"
RUNTIME_ETC_DIR="$COMPAT_DIR/etc"
STATE_HOME="$ROOT_DIR/state"
WP_BIN="/usr/lib/wp8/wpbin/xwp"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
HOST_USER="$(id -un)"
HOST_GROUP="$(id -gn)"
HOSTNAME_VALUE="$(hostname)"

LOADER_CANDIDATES=(
  "/usr/lib32/ld-linux.so.2"
  "/usr/lib/ld-linux.so.2"
  "/lib/ld-linux.so.2"
)

find_loader() {
  local candidate
  for candidate in "${LOADER_CANDIDATES[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

add_font_path() {
  local path="$1"
  if [[ -d "$path" ]] && command -v xset >/dev/null 2>&1; then
    xset q 2>/dev/null | grep -Fq "$path" && return 0
    xset +fp "$path" >/dev/null 2>&1 || true
  fi
}

remove_font_path() {
  local path="$1"
  if [[ -d "$path" ]] && command -v xset >/dev/null 2>&1; then
    xset -fp "$path" >/dev/null 2>&1 || true
  fi
}

cleanup_font_paths() {
  remove_font_path "$FONT_ROOT/misc"
  remove_font_path "$FONT_ROOT/75dpi"
  remove_font_path "$FONT_ROOT/100dpi"
  remove_font_path "$FONT_ROOT/Type1"
  if command -v xset >/dev/null 2>&1; then
    xset fp rehash >/dev/null 2>&1 || true
  fi
}

run_in_bwrap() {
  bwrap \
    "${BWRAP_ARGS[@]}" \
    "$LOADER" \
    --library-path "$IN_BUBBLE_LIB_DIR" \
    --preload "$IN_BUBBLE_SHIM_LIB" \
    "$WP_BIN" \
    "$@"
}

LOADER="$(find_loader)" || {
  printf 'could not find a 32-bit glibc loader on this host.\n' >&2
  exit 1
}

if [[ ! -x "$APP_DIR/usr/lib/wp8/wpbin/xwp" ]]; then
  printf 'missing staged WordPerfect app in %s\n' "$APP_DIR" >&2
  printf 'run ./setup.sh first.\n' >&2
  exit 1
fi

if [[ ! -f "$SHIM_LIB" ]]; then
  printf 'missing WordPerfect compat shim in %s\n' "$SHIM_LIB" >&2
  printf 'run ./setup.sh first.\n' >&2
  exit 1
fi

if [[ ! -d "$COMPAT_LIB_DIR" ]]; then
  printf 'missing compat libraries in %s\n' "$COMPAT_LIB_DIR" >&2
  printf 'run ./setup.sh first.\n' >&2
  exit 1
fi

if [[ ! -d "$COMPAT_X11_ROOT" ]]; then
  printf 'missing compat X11 tree in %s\n' "$COMPAT_X11_ROOT" >&2
  printf 'run ./setup.sh first.\n' >&2
  exit 1
fi

if ! command -v bwrap >/dev/null 2>&1; then
  printf 'missing required command: bwrap\n' >&2
  exit 1
fi

mkdir -p "$STATE_HOME" "$RUNTIME_ETC_DIR"
cd "$ROOT_DIR"

cat >"$RUNTIME_ETC_DIR/nsswitch.conf" <<'EOF'
hosts: files dns
passwd: files
group: files
shadow: files
networks: files
protocols: files
services: files
ethers: files
rpc: files
EOF

cat >"$RUNTIME_ETC_DIR/passwd" <<EOF
root:x:0:0:root:/root:/bin/sh
$HOST_USER:x:$HOST_UID:$HOST_GID:$HOST_USER:$STATE_HOME:/bin/sh
EOF

cat >"$RUNTIME_ETC_DIR/group" <<EOF
root:x:0:
$HOST_GROUP:x:$HOST_GID:
EOF

cat >"$RUNTIME_ETC_DIR/hosts" <<EOF
127.0.0.1 localhost $HOSTNAME_VALUE
::1 localhost
EOF

if command -v xset >/dev/null 2>&1; then
  add_font_path "$FONT_ROOT/misc"
  add_font_path "$FONT_ROOT/75dpi"
  add_font_path "$FONT_ROOT/100dpi"
  add_font_path "$FONT_ROOT/Type1"
  xset fp rehash >/dev/null 2>&1 || true
else
  printf 'warning: xset not found; bundled font paths were not registered.\n' >&2
fi

trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap cleanup_font_paths EXIT

BWRAP_ARGS=(
  --dir /tmp
  --dir /home
  --dir /bin
  --dir /lib
  --dir /compat
  --dir /compat/shim
  --dir /compat/lib
  --dir /etc
  --dir /usr
  --dir /usr/lib
  --dir /usr/bin
  --dir /usr/X11R6
  --ro-bind /bin /bin
  --ro-bind "$LOADER" /lib/ld-linux.so.1
  --ro-bind /etc /etc
  --ro-bind /usr/bin /usr/bin
  --dev-bind /dev /dev
  --proc /proc
  --bind "$STATE_HOME" "$STATE_HOME"
  --ro-bind "$COMPAT_LIB_DIR" "$IN_BUBBLE_LIB_DIR"
  --ro-bind "$(dirname "$SHIM_LIB")" "$IN_BUBBLE_COMPAT_ROOT/shim"
  --bind "$APP_DIR/usr/lib/wp8" /usr/lib/wp8
  --ro-bind "$COMPAT_X11_ROOT" /usr/X11R6
  --ro-bind "$RUNTIME_ETC_DIR/nsswitch.conf" /etc/nsswitch.conf
  --ro-bind "$RUNTIME_ETC_DIR/passwd" /etc/passwd
  --ro-bind "$RUNTIME_ETC_DIR/group" /etc/group
  --ro-bind "$RUNTIME_ETC_DIR/hosts" /etc/hosts
  --setenv HOME "$STATE_HOME"
  --setenv LANG "${LANG_OVERRIDE:-C}"
  --setenv LC_ALL "${LANG_OVERRIDE:-C}"
  --setenv PATH "/usr/lib/wp8/wpbin:/usr/lib/wp8/shbin10:/usr/bin:/bin:/usr/X11R6/bin"
  --setenv XAPPLRESDIR "/usr/X11R6/lib/X11/app-defaults"
  --setenv XKEYSYMDB "/usr/X11R6/lib/X11/XKeysymDB"
  --setenv XLOCALEDIR "/usr/X11R6/lib/X11/locale"
  --setenv XNLSPATH "/usr/X11R6/lib/X11/locale"
  --setenv LD_LIBRARY_PATH "$IN_BUBBLE_LIB_DIR"
  --setenv LD_PRELOAD "$IN_BUBBLE_SHIM_LIB"
)

if [[ -d /usr/lib32 ]]; then
  BWRAP_ARGS+=(--dir /usr/lib32)
  BWRAP_ARGS+=(--ro-bind /usr/lib32 /usr/lib32)
fi

if [[ -d /usr/lib/locale ]]; then
  BWRAP_ARGS+=(--dir /usr/lib/locale)
  BWRAP_ARGS+=(--ro-bind /usr/lib/locale /usr/lib/locale)
fi

if [[ -d /usr/lib/gconv ]]; then
  BWRAP_ARGS+=(--dir /usr/lib/gconv)
  BWRAP_ARGS+=(--ro-bind /usr/lib/gconv /usr/lib/gconv)
fi

if [[ -d /usr/share/locale ]]; then
  BWRAP_ARGS+=(--dir /usr/share)
  BWRAP_ARGS+=(--dir /usr/share/locale)
  BWRAP_ARGS+=(--ro-bind /usr/share/locale /usr/share/locale)
fi

if [[ -n "${DISPLAY:-}" && -d /tmp/.X11-unix ]]; then
  BWRAP_ARGS+=(--ro-bind /tmp/.X11-unix /tmp/.X11-unix)
  BWRAP_ARGS+=(--setenv DISPLAY "$DISPLAY")
fi

if [[ -n "${XAUTHORITY:-}" && -f "${XAUTHORITY:-}" ]]; then
  BWRAP_ARGS+=(--ro-bind "$XAUTHORITY" "$XAUTHORITY")
  BWRAP_ARGS+=(--setenv XAUTHORITY "$XAUTHORITY")
fi

mkdir -p "$STATE_HOME/.wprc" "$STATE_HOME/.wpcorp"
run_in_bwrap "$@"
