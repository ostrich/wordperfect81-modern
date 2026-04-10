#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_PATH="${COREL_ISO:-$ROOT_DIR/corel_linux_1.2.iso}"
COMPAT_DIR="$ROOT_DIR/compat"
ARCHIVE_DIR="$COMPAT_DIR/archives"
BUILD_DIR="$COMPAT_DIR/build"
LIB_DIR="$COMPAT_DIR/lib"
X11_DIR="$COMPAT_DIR/x11"
FONT_DIR="$COMPAT_DIR/fonts"
SHIM_DIR="$ROOT_DIR/shim"
SHIM_OUT_DIR="$COMPAT_DIR/shim"
APP_DIR="$ROOT_DIR/app"
STATE_DIR="$ROOT_DIR/state"
SUPPORT_DIR="$ROOT_DIR/support"

WP_DEB="$ARCHIVE_DIR/wp-full_8.1-12_i386.deb"
LDSO_DEB="$ARCHIVE_DIR/ldso_1.9.10-1.deb"
LIBC5_DEB="$ARCHIVE_DIR/libc5_5.4.46-3.deb"
XLIB_DEB="$ARCHIVE_DIR/xlib6g_3.3.6-2.99.slink.1_i386.deb"
XPM_DEB="$ARCHIVE_DIR/xpm4g_3.4j-0.6.deb"
XFONTS_BASE_DEB="$ARCHIVE_DIR/xfonts-base_3.3.6-0.99_all.deb"
XFONTS_75_DEB="$ARCHIVE_DIR/xfonts-75dpi_3.3.6-0.99_all.deb"
XFONTS_100_DEB="$ARCHIVE_DIR/xfonts-100dpi_3.3.6-0.99_all.deb"

LOADER_CANDIDATES=(
  "/usr/lib32/ld-linux.so.2"
  "/usr/lib/ld-linux.so.2"
  "/lib/ld-linux.so.2"
)

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

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

extract_iso_file() {
  local path_in_iso="$1"
  local out_dir="$2"
  local out_name

  out_name="${path_in_iso##*/}"
  bsdtar -xOf "$ISO_PATH" "$path_in_iso" >"$out_dir/$out_name"
}

extract_deb_data() {
  local deb="$1"
  local dest="$2"

  rm -rf "$dest"
  mkdir -p "$dest/pkg" "$dest/root"
  (
    cd "$dest/pkg"
    ar x "$deb"
  )
  tar -xzf "$dest/pkg/data.tar.gz" -C "$dest/root" || {
    local rc=$?
    if [[ "$rc" -ne 2 ]]; then
      return "$rc"
    fi
  }
}

copy_matches() {
  local src_dir="$1"
  shift
  local pattern

  for pattern in "$@"; do
    find "$src_dir" -maxdepth 1 -name "$pattern" -exec cp -a {} "$LIB_DIR/" \;
  done
}

print_staged_entries() {
  local label="$1"
  local dir="$2"

  printf '\n%s in %s\n' "$label" "$dir"
  find "$dir" -mindepth 1 -maxdepth 1 | sort
}

need_cmd bsdtar
need_cmd ar
need_cmd tar
need_cmd find
need_cmd gcc

if [[ ! -f "$ISO_PATH" ]]; then
  printf 'missing Corel Linux ISO: %s\n' "$ISO_PATH" >&2
  printf 'set COREL_ISO=/path/to/corel_linux_1.2.iso if needed.\n' >&2
  printf 'try https://archive.org/details/corel_linux_1.2\n' >&2
  exit 1
fi

if [[ ! -f "$SUPPORT_DIR/wp.drs" ]]; then
  printf 'missing seeded WordPerfect DRS file: %s\n' "$SUPPORT_DIR/wp.drs" >&2
  exit 1
fi

for support_file in \
  "$SUPPORT_DIR/fonts/misc/fonts.dir" \
  "$SUPPORT_DIR/fonts/75dpi/fonts.dir" \
  "$SUPPORT_DIR/fonts/100dpi/fonts.dir" \
  "$SUPPORT_DIR/fonts/Type1/fonts.dir" \
  "$SUPPORT_DIR/fonts/Type1/fonts.scale" \
  "$SUPPORT_DIR/fonts/Type1/Fontmap"; do
  if [[ ! -f "$support_file" ]]; then
    printf 'missing required support file: %s\n' "$support_file" >&2
    exit 1
  fi
done

LOADER="$(find_loader)" || {
  printf 'could not find a 32-bit glibc loader on this host.\n' >&2
  printf 'expected one of:\n' >&2
  printf '  %s\n' "${LOADER_CANDIDATES[@]}" >&2
  exit 1
}

mkdir -p "$ARCHIVE_DIR"

if [[ ! -f "$WP_DEB" ]]; then
  extract_iso_file "dists/corellinux-1.2/corel/binary-i386/editors/wp-full_8.1-12_i386.deb" "$ARCHIVE_DIR"
fi
if [[ ! -f "$LDSO_DEB" ]]; then
  extract_iso_file "dists/corellinux-1.2/main/binary-i386/base/ldso_1.9.10-1.deb" "$ARCHIVE_DIR"
fi
if [[ ! -f "$LIBC5_DEB" ]]; then
  extract_iso_file "dists/corellinux-1.2/main/binary-i386/oldlibs/libc5_5.4.46-3.deb" "$ARCHIVE_DIR"
fi
if [[ ! -f "$XLIB_DEB" ]]; then
  extract_iso_file "dists/corellinux-1.2/corel/binary-i386/x11/xlib6g_3.3.6-2.99.slink.1_i386.deb" "$ARCHIVE_DIR"
fi
if [[ ! -f "$XPM_DEB" ]]; then
  extract_iso_file "dists/corellinux-1.2/main/binary-i386/x11/xpm4g_3.4j-0.6.deb" "$ARCHIVE_DIR"
fi
if [[ ! -f "$XFONTS_BASE_DEB" ]]; then
  extract_iso_file "dists/corellinux-1.2/corel/binary-i386/x11/xfonts-base_3.3.6-0.99_all.deb" "$ARCHIVE_DIR"
fi
if [[ ! -f "$XFONTS_75_DEB" ]]; then
  extract_iso_file "dists/corellinux-1.2/corel/binary-i386/x11/xfonts-75dpi_3.3.6-0.99_all.deb" "$ARCHIVE_DIR"
fi
if [[ ! -f "$XFONTS_100_DEB" ]]; then
  extract_iso_file "dists/corellinux-1.2/corel/binary-i386/x11/xfonts-100dpi_3.3.6-0.99_all.deb" "$ARCHIVE_DIR"
fi

rm -rf "$BUILD_DIR" "$LIB_DIR" "$X11_DIR" "$FONT_DIR" "$SHIM_OUT_DIR" "$APP_DIR"
mkdir -p "$BUILD_DIR" "$LIB_DIR" "$X11_DIR" "$FONT_DIR" "$SHIM_OUT_DIR" "$APP_DIR" "$STATE_DIR"

extract_deb_data "$WP_DEB" "$BUILD_DIR/wp"
extract_deb_data "$LDSO_DEB" "$BUILD_DIR/ldso"
extract_deb_data "$LIBC5_DEB" "$BUILD_DIR/libc5"
extract_deb_data "$XLIB_DEB" "$BUILD_DIR/xlib6g"
extract_deb_data "$XPM_DEB" "$BUILD_DIR/xpm4g"
extract_deb_data "$XFONTS_BASE_DEB" "$BUILD_DIR/xfonts-base"
extract_deb_data "$XFONTS_75_DEB" "$BUILD_DIR/xfonts-75dpi"
extract_deb_data "$XFONTS_100_DEB" "$BUILD_DIR/xfonts-100dpi"

cp -a "$BUILD_DIR/wp/root/." "$APP_DIR/"

copy_matches "$BUILD_DIR/ldso/root/lib" "ld-linux.so.1*" "libdl.so.1*"
copy_matches "$BUILD_DIR/libc5/root/lib" "libc.so.5*" "libm.so.5*"
copy_matches "$BUILD_DIR/xlib6g/root/usr/X11R6/lib" \
  "libICE.so.6*" \
  "libSM.so.6*" \
  "libX11.so.6*" \
  "libXext.so.6*" \
  "libXmu.so.6*" \
  "libXt.so.6*"
copy_matches "$BUILD_DIR/xpm4g/root/usr/X11R6/lib" "libXpm.so.4*"

mkdir -p "$X11_DIR/usr/X11R6/lib/X11"
cp -a "$BUILD_DIR/xlib6g/root/usr/X11R6/lib/X11/XErrorDB" "$X11_DIR/usr/X11R6/lib/X11/"
cp -a "$BUILD_DIR/xlib6g/root/usr/X11R6/lib/X11/XKeysymDB" "$X11_DIR/usr/X11R6/lib/X11/"
cp -a "$BUILD_DIR/xlib6g/root/usr/X11R6/lib/X11/locale" "$X11_DIR/usr/X11R6/lib/X11/"
mkdir -p "$X11_DIR/usr/X11R6/lib/X11/app-defaults"
mkdir -p "$X11_DIR/usr/X11R6/lib/X11/icons/XWp"
mkdir -p "$X11_DIR/usr/X11R6/lib/X11/bitmaps/XWp"

if [[ -f /usr/share/X11/Xcms.txt ]]; then
  cp -a /usr/share/X11/Xcms.txt "$X11_DIR/usr/X11R6/lib/X11/"
fi

if [[ -f /usr/include/X11/bitmaps/xm_error ]]; then
  mkdir -p "$X11_DIR/usr/X11R6/lib/X11/bitmaps"
  cp -a /usr/include/X11/bitmaps/xm_error "$X11_DIR/usr/X11R6/lib/X11/bitmaps/"
  cp -a /usr/include/X11/bitmaps/xm_error "$X11_DIR/usr/X11R6/lib/X11/bitmaps/XWp/"
  cp -a /usr/include/X11/bitmaps/xm_error "$X11_DIR/usr/X11R6/lib/X11/bitmaps/default_xm_error"
  cp -a /usr/include/X11/bitmaps/xm_error "$X11_DIR/usr/X11R6/lib/X11/bitmaps/XWp/default_xm_error"
fi

if [[ -f /usr/include/X11/bitmaps/xm_information ]]; then
  mkdir -p "$X11_DIR/usr/X11R6/lib/X11/app-defaults/icons/XWp"
  cp -a /usr/include/X11/bitmaps/xm_information "$X11_DIR/usr/X11R6/lib/X11/icons/50_foreground"
  cp -a /usr/include/X11/bitmaps/xm_information "$X11_DIR/usr/X11R6/lib/X11/icons/XWp/50_foreground"
  cp -a /usr/include/X11/bitmaps/xm_information "$X11_DIR/usr/X11R6/lib/X11/app-defaults/icons/50_foreground"
  cp -a /usr/include/X11/bitmaps/xm_information "$X11_DIR/usr/X11R6/lib/X11/app-defaults/icons/XWp/50_foreground"
fi

cat >"$X11_DIR/usr/X11R6/lib/X11/app-defaults/XWp" <<'EOF'
XWp*foreground: black
XWp*background: lightgrey
XWp*XmDrawingArea.foreground: black
XWp*XmList*foreground: black
XWp*XmText*foreground: black
XWp*XmTextField*foreground: black
XWp*XmDrawingArea.background: white
XWp*XmList*background: white
XWp*XmText*background: white
XWp*XmTextField*background: white
XWp*XmScrolledWindow*XmDrawingArea.background: lightgrey
XWp.mainWindowForm.mainWindowMenubar*background: lightgrey
XWp.mainWindowForm.mainWindowMenubar*foreground: black
XWp*MenuBar*background: lightgrey
XWp*MenuBar*foreground: black
XWp*menubar*background: lightgrey
XWp*menubar*foreground: black
XWp*popmenu*background: lightgrey
XWp*popmenu*foreground: black
XWp*XmDialogShell*background: lightgrey
XWp*XmDialogShell*foreground: black
XWp.form.rulerframe.ruler*background: lightgrey
XWp.form.controlbar.menubar.CBHlpButton*background: lightgrey
XWp.form.scrollbar0.background: lightgrey
XWp.form.hscrollbar.background: lightgrey
EOF

cp -a "$BUILD_DIR/xfonts-base/root/usr/X11R6/lib/X11/fonts/misc" "$FONT_DIR/"
cp -a "$BUILD_DIR/xfonts-75dpi/root/usr/X11R6/lib/X11/fonts/75dpi" "$FONT_DIR/"
cp -a "$BUILD_DIR/xfonts-100dpi/root/usr/X11R6/lib/X11/fonts/100dpi" "$FONT_DIR/"
cp -a "$APP_DIR/usr/X11R6/lib/X11/fonts/Type1" "$FONT_DIR/"
cp -a "$SUPPORT_DIR/wp.drs" "$APP_DIR/usr/lib/wp8/shlib10/wp.drs"
cp -a "$SUPPORT_DIR/fonts/misc/fonts.dir" "$FONT_DIR/misc/fonts.dir"
cp -a "$SUPPORT_DIR/fonts/75dpi/fonts.dir" "$FONT_DIR/75dpi/fonts.dir"
cp -a "$SUPPORT_DIR/fonts/100dpi/fonts.dir" "$FONT_DIR/100dpi/fonts.dir"
cp -a "$SUPPORT_DIR/fonts/Type1/fonts.dir" "$FONT_DIR/Type1/fonts.dir"
cp -a "$SUPPORT_DIR/fonts/Type1/fonts.scale" "$FONT_DIR/Type1/fonts.scale"
cp -a "$SUPPORT_DIR/fonts/Type1/Fontmap" "$FONT_DIR/Type1/Fontmap"

# WordPerfect's Type 1 installer path effectively operates out of shlib10.
# Seed the full bundled screen-font set there up front, then stage the richer
# prebuilt wp.drs generated from that same font set.
cp -a "$FONT_DIR/Type1"/wp*.afm "$APP_DIR/usr/lib/wp8/shlib10/"
cp -a "$FONT_DIR/Type1"/wp*.pfb "$APP_DIR/usr/lib/wp8/shlib10/"

gcc -m32 -shared -fPIC \
  -Wl,-soname,libwp_compat_shim.so \
  -o "$SHIM_OUT_DIR/libwp_compat_shim.so" \
  "$SHIM_DIR/wp_compat_shim.c"

print_staged_entries "compat libraries staged" "$LIB_DIR"
print_staged_entries "X11 support data staged" "$X11_DIR"
print_staged_entries "bitmap fonts staged" "$FONT_DIR"
print_staged_entries "wordperfect staged" "$APP_DIR"
printf '\nshim built at %s\n' "$SHIM_OUT_DIR/libwp_compat_shim.so"
printf 'using host loader %s\n' "$LOADER"
