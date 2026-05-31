#!/bin/bash
# tools/x-win/package-msys2.sh
#
# Package Ardour for Windows using a native MSYS2/MINGW64 build.
# Bundles all required MINGW64 runtime DLLs and creates an NSIS installer.
#
# Prerequisites:
#   - Ardour already built:  build/gtk2_ardour/ardour-*.exe
#   - Running inside MSYS2 MINGW64 shell
#   - Optional: ntldd (mingw-w64-x86_64-ntldd-git) for precise DLL resolution
#   - Optional: makensis (nsis) for installer creation
#
# Environment variables:
#   DESTDIR           – staging directory (default: auto temp dir)
#   OUTDIR            – where to write the final installer/zip (default: _ci_artifacts)
#   MINGW_PREFIX      – MinGW prefix (default: /mingw64)
#   WAFINSTALL_PREFIX – where "waf install" wrote share data (default: _ci_install)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

PREFIX="${MINGW_PREFIX:-/mingw64}"
OUTDIR="${OUTDIR:-_ci_artifacts}"
TMPDIR="${TMPDIR:-/tmp}"

# ---- Locate the built EXE and derive version ----
ARDOUR_EXE=$(ls -t build/gtk2_ardour/ardour-*.exe 2>/dev/null | head -n1 || true)
if [[ -z "$ARDOUR_EXE" ]]; then
    echo "ERROR: No ardour-*.exe found in build/gtk2_ardour/" >&2
    exit 1
fi
ARDOUR_VERSION=$(basename "$ARDOUR_EXE" .exe | sed 's/ardour-//')
MAJOR_VERSION=$(echo "$ARDOUR_VERSION" | cut -d. -f1)

PRODUCT_NAME="Ardour"
PRODUCT_EXE="${PRODUCT_NAME}.exe"
PROGRAM_KEY="Ardour"
LOWERCASE_DIRNAME="ardour${MAJOR_VERSION}"

# ---- Set up staging directory ----
if [[ -z "${DESTDIR:-}" ]]; then
    DESTDIR="$(mktemp -d)/ardour-${ARDOUR_VERSION}-win64"
    CLEANUP_DESTDIR=1
fi
mkdir -p \
    "$DESTDIR/bin" \
    "$DESTDIR/share" \
    "$DESTDIR/lib/${LOWERCASE_DIRNAME}/surfaces" \
    "$DESTDIR/lib/${LOWERCASE_DIRNAME}/backends" \
    "$DESTDIR/lib/${LOWERCASE_DIRNAME}/panners" \
    "$DESTDIR/lib/${LOWERCASE_DIRNAME}/vamp" \
    "$DESTDIR/lib/${LOWERCASE_DIRNAME}/LV2" \
    "$DESTDIR/lib/${LOWERCASE_DIRNAME}/suil" \
    "$DESTDIR/lib/gtk-2.0/engines"

echo "=== Packaging Ardour ${ARDOUR_VERSION} for Windows x64 (MSYS2 native)"
echo "    Staging: ${DESTDIR}"
echo "    MinGW prefix: ${PREFIX}"

# ================================================================
# 1 – Copy Ardour-built DLLs and EXEs
# ================================================================
echo "=== Copying Ardour binaries..."

_cp() { [[ -e "$1" ]] && cp "$1" "$2" || true; }
_cpglob() { ls $1 2>/dev/null | while read f; do cp "$f" "$2"; done; }

_cpglob "build/libs/gtkmm2ext/gtkmm2ext-*.dll"                    "$DESTDIR/bin/"
_cpglob "build/libs/midi++2/midipp-*.dll"                          "$DESTDIR/bin/"
_cpglob "build/libs/evoral/evoral-*.dll"                           "$DESTDIR/bin/"
_cpglob "build/libs/ardour/ardour-*.dll"                           "$DESTDIR/bin/"
_cpglob "build/libs/temporal/temporal-*.dll"                       "$DESTDIR/bin/"
_cpglob "build/libs/aaf/aaf-*.dll"                                 "$DESTDIR/bin/"
_cpglob "build/libs/canvas/canvas-*.dll"                           "$DESTDIR/bin/"
_cpglob "build/libs/widgets/widgets-*.dll"                         "$DESTDIR/bin/"
_cpglob "build/libs/waveview/waveview-*.dll"                       "$DESTDIR/bin/"
_cpglob "build/libs/pbd/pbd-*.dll"                                 "$DESTDIR/bin/"
_cpglob "build/libs/tk/ztk/ztk-*.dll"                             "$DESTDIR/bin/"
_cpglob "build/libs/tk/ydk/ydk-*.dll"                             "$DESTDIR/bin/"
_cpglob "build/libs/tk/ytk/ytk-*.dll"                             "$DESTDIR/bin/"
_cpglob "build/libs/tk/ytkmm/ytkmm-*.dll"                         "$DESTDIR/bin/"
_cpglob "build/libs/tk/ydkmm/ydkmm-*.dll"                         "$DESTDIR/bin/"
_cpglob "build/libs/tk/ztkmm/ztkmm-*.dll"                         "$DESTDIR/bin/"
_cpglob "build/libs/tk/ydk-pixbuf/ydk-pixbuf-*.dll"               "$DESTDIR/bin/"
_cpglob "build/libs/tk/suil/suil-*.dll"                           "$DESTDIR/bin/"
_cpglob "build/libs/ctrl-interface/midi_surface/ardour*.dll"       "$DESTDIR/bin/"
_cpglob "build/libs/ctrl-interface/control_protocol/ardour*.dll"   "$DESTDIR/bin/"
_cpglob "build/libs/ptformat/ptformat-*.dll"                       "$DESTDIR/bin/"
_cpglob "build/libs/audiographer/audiographer-*.dll"               "$DESTDIR/bin/"
_cp     "build/libs/fst/ardour-vst-scanner.exe"                    "$DESTDIR/bin/"
_cp     "build/libs/fst/ardour-vst3-scanner.exe"                   "$DESTDIR/bin/"
ls build/session_utils/*-*.exe  2>/dev/null | while read f; do cp "$f" "$DESTDIR/bin/"; done || true
ls build/luasession/ardour*-lua.exe 2>/dev/null | while read f; do cp "$f" "$DESTDIR/bin/"; done || true
cp "$ARDOUR_EXE" "$DESTDIR/bin/${PRODUCT_EXE}"

# GTK engine
_cp "build/libs/clearlooks-newer/clearlooks.dll" \
    "$DESTDIR/lib/gtk-2.0/engines/libclearlooks.la"

# Loadable plugin collections
find build/libs/surfaces/ -iname "*.dll" -exec cp {} "$DESTDIR/lib/${LOWERCASE_DIRNAME}/surfaces/" \;
find build/libs/backends/ -iname "*.dll" -exec cp {} "$DESTDIR/lib/${LOWERCASE_DIRNAME}/backends/" \;
find build/libs/panners/  -iname "*.dll" -exec cp {} "$DESTDIR/lib/${LOWERCASE_DIRNAME}/panners/"  \;
cp -r build/libs/LV2 "$DESTDIR/lib/${LOWERCASE_DIRNAME}/" 2>/dev/null || true
find build/libs/vamp-plugins/ -iname "*ardourvampplugins*.dll" \
    -exec cp {} "$DESTDIR/lib/${LOWERCASE_DIRNAME}/vamp/libardourvampplugins.dll" \; 2>/dev/null || true
find build/libs/vamp-pyin/ -iname "*ardourvamppyin*.dll" \
    -exec cp {} "$DESTDIR/lib/${LOWERCASE_DIRNAME}/vamp/libardourvamppyin.dll" \; 2>/dev/null || true
if [[ -d build/libs/tk/suil/ ]]; then
    _cp "build/libs/tk/suil/suil_win_in_gtk2.dll" "$DESTDIR/lib/${LOWERCASE_DIRNAME}/suil/"
fi

# ================================================================
# 2 – Collect MINGW64 runtime DLLs
# ================================================================
echo "=== Collecting MSYS2/MINGW64 runtime DLLs..."

if command -v ntldd &>/dev/null; then
    echo "    Using ntldd for precise dependency resolution..."
    ntldd --recursive "$DESTDIR/bin/${PRODUCT_EXE}" 2>/dev/null \
        | grep -iE "mingw64" \
        | awk '{print $3}' \
        | sort -u \
        | while read dll; do
            if [[ -f "$dll" ]]; then
                cp "$dll" "$DESTDIR/bin/"
            fi
        done
fi

# Key MINGW64 DLLs – copied regardless, handles version-name variations
MINGW_PATTERNS=(
    "libcurl*.dll"
    "libssl*.dll"
    "libcrypto*.dll"
    "libglib-2.0-*.dll"
    "libgthread-2.0-*.dll"
    "libgmodule-2.0-*.dll"
    "libgobject-2.0-*.dll"
    "libgio-2.0-*.dll"
    "libgdk_pixbuf-2.0-*.dll"
    "libgdk-win32-2.0-*.dll"
    "libgtk-win32-2.0-*.dll"
    "libatk-1.0-*.dll"
    "libpango-1.0-*.dll"
    "libpangocairo-1.0-*.dll"
    "libpangoft2-1.0-*.dll"
    "libpangowin32-1.0-*.dll"
    "libcairo-2.dll"
    "libcairo-gobject-2.dll"
    "libpixman-1-*.dll"
    "libfontconfig-*.dll"
    "libfreetype-*.dll"
    "libharfbuzz-*.dll"
    "libpng16-*.dll"
    "libsndfile-*.dll"
    "libsamplerate-*.dll"
    "libFLAC*.dll"
    "libogg-*.dll"
    "libvorbis-*.dll"
    "libvorbisenc-*.dll"
    "libvorbisfile-*.dll"
    "librubberband*.dll"
    "liblo-*.dll"
    "libusb-1.0.dll"
    "libfftw3-3.dll"
    "libfftw3f-3.dll"
    "liblilv-0.dll"
    "libfluidsynth-*.dll"
    "libportaudio-2.dll"
    "libxml2-*.dll"
    "libiconv-*.dll"
    "libintl-*.dll"
    "zlib1.dll"
    "libbz2-*.dll"
    "liblzma-*.dll"
    "libpcre2-8-*.dll"
    "libffi-*.dll"
    "libstdc++-6.dll"
    "libgcc_s_seh-1.dll"
    "libwinpthread-1.dll"
    "libzstd.dll"
    "libbrotlicommon.dll"
    "libbrotlidec.dll"
    "libnghttp2-*.dll"
    "libssh2-*.dll"
    "libidn2-*.dll"
    "libunistring-*.dll"
    "libarchive-*.dll"
    "libtag.dll"
    "libtaglib.dll"
    "libaubio-*.dll"
    "libltc-*.dll"
)

for pattern in "${MINGW_PATTERNS[@]}"; do
    for dll in ${PREFIX}/bin/${pattern}; do
        [[ -f "$dll" ]] && cp "$dll" "$DESTDIR/bin/" || true
    done
done

# Remove DLLs that should come from the system or are unwanted
rm -f "$DESTDIR/bin/libjack"*.dll    || true  # prefer system JACK
rm -f "$DESTDIR/bin/dbghelp"*.dll    || true
rm -f "$DESTDIR/bin/dbgcore"*.dll    || true

echo "    Runtime DLL count: $(ls "$DESTDIR/bin/"*.dll 2>/dev/null | wc -l)"

# ================================================================
# 3 – Share / data files (written by waf install)
# ================================================================
echo "=== Copying share data..."
WAFINSTALL_PREFIX="${WAFINSTALL_PREFIX:-$PWD/_ci_install}"

if [[ -d "${WAFINSTALL_PREFIX}/share/${LOWERCASE_DIRNAME}" ]]; then
    cp -r "${WAFINSTALL_PREFIX}/share/${LOWERCASE_DIRNAME}" "$DESTDIR/share/"
fi
if [[ -d "${WAFINSTALL_PREFIX}/share/locale" ]]; then
    cp -r "${WAFINSTALL_PREFIX}/share/locale" "$DESTDIR/share/"
fi
if [[ -d "${WAFINSTALL_PREFIX}/etc/${LOWERCASE_DIRNAME}" ]]; then
    cp -r "${WAFINSTALL_PREFIX}/etc/${LOWERCASE_DIRNAME}/". "$DESTDIR/share/${LOWERCASE_DIRNAME}/"
fi

cp COPYING "$DESTDIR/share/"
_cp "gtk2_ardour/icons/Ardour.ico"    "$DESTDIR/share/"
_cp "gtk2_ardour/icons/ArdourBug.ico" "$DESTDIR/share/"

echo "    Staging size: $(du -sh "$DESTDIR" | cut -f1)"

# ================================================================
# 4 – Build NSIS installer (or fall back to zip)
# ================================================================
mkdir -p "$OUTDIR"

if ! command -v makensis &>/dev/null; then
    echo "=== makensis not found – creating zip instead..."
    ZIP_OUT="$OUTDIR/Ardour-${ARDOUR_VERSION}-windows-x64.zip"
    (cd "$(dirname "$DESTDIR")" && zip -r "$OLDPWD/$ZIP_OUT" "$(basename "$DESTDIR")")
    echo "=== Created: $ZIP_OUT  ($(du -sh "$OLDPWD/$ZIP_OUT" | cut -f1))"
    exit 0
fi

PGF=PROGRAMFILES64
OUTFILE_NAME="Ardour-${ARDOUR_VERSION}-windows-x64-Setup.exe"
OUTFILE="$PWD/$OUTDIR/$OUTFILE_NAME"
NSIS_INCLUDE_DIR_WIN="$(cygpath -w "$SCRIPT_DIR/nsis")"
DESTDIR_WIN="$(cygpath -w "$DESTDIR")"
OUTFILE_WIN="$(cygpath -w "$OUTFILE")"

# Check for icon; use a dummy if missing
if [[ ! -f "$DESTDIR/share/Ardour.ico" ]]; then
    touch "$DESTDIR/share/Ardour.ico" || true
fi

cat > "$DESTDIR/ardour.nsi" << NSIS_EOF
SetCompressor /SOLID lzma
SetCompressorDictSize 32

!addincludedir "${NSIS_INCLUDE_DIR_WIN}"
!include MUI2.nsh
!include FileAssociation.nsh
!include WinVer.nsh

Name "Ardour ${ARDOUR_VERSION}"
OutFile "${OUTFILE_WIN}"
RequestExecutionLevel admin
InstallDir "\$${PGF}\\Ardour${MAJOR_VERSION}"
InstallDirRegKey HKLM "Software\\${PROGRAM_KEY}\\v${MAJOR_VERSION}\\w64" "Install_Dir"
!define MUI_ICON "share\\Ardour.ico"
!define MUI_UNICON "share\\Ardour.ico"

!define MUI_FINISHPAGE_TITLE "Welcome to Ardour"
!define MUI_FINISHPAGE_TEXT "This Windows version of Ardour is provided as-is.\$\\r\$\\nIf you like Ardour, please consider helping out."
!define MUI_FINISHPAGE_LINK "Ardour Manual"
!define MUI_FINISHPAGE_LINK_LOCATION "http://manual.ardour.org/"
!define MUI_FINISHPAGE_NOREBOOTSUPPORT
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_LICENSE "share\\COPYING"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Ardour ${ARDOUR_VERSION} (required)" SecMainProg
  SectionIn RO
  SetOutPath \$INSTDIR
  File /r bin
  File /r lib
  File /r share
  WriteRegStr HKLM "Software\\${PROGRAM_KEY}\\v${MAJOR_VERSION}\\w64" "Install_Dir" "\$INSTDIR"
  WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Ardour${MAJOR_VERSION}-w64" "DisplayName" "Ardour ${ARDOUR_VERSION}"
  WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Ardour${MAJOR_VERSION}-w64" "UninstallString" '"\$INSTDIR\\uninstall.exe"'
  WriteRegDWORD HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Ardour${MAJOR_VERSION}-w64" "NoModify" 1
  WriteRegDWORD HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Ardour${MAJOR_VERSION}-w64" "NoRepair" 1
  WriteUninstaller "\$INSTDIR\\uninstall.exe"
  CreateDirectory "\$SMPROGRAMS\\Ardour${MAJOR_VERSION}"
  CreateShortCut "\$SMPROGRAMS\\Ardour${MAJOR_VERSION}\\Ardour ${ARDOUR_VERSION}.lnk" "\$INSTDIR\\bin\\${PRODUCT_EXE}" "" "\$INSTDIR\\share\\Ardour.ico" 0
  CreateShortCut "\$DESKTOP\\Ardour ${ARDOUR_VERSION}.lnk" "\$INSTDIR\\bin\\${PRODUCT_EXE}" "" "\$INSTDIR\\share\\Ardour.ico" 0
  \${registerExtension} "\$INSTDIR\\bin\\${PRODUCT_EXE}" ".ardour" "Ardour Session"
SectionEnd

Section "Uninstall"
  \${unregisterExtension} ".ardour" "Ardour Session"
  DeleteRegKey HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Ardour${MAJOR_VERSION}-w64"
  DeleteRegKey HKLM "Software\\${PROGRAM_KEY}\\v${MAJOR_VERSION}\\w64"
  RMDir /r "\$INSTDIR\\bin"
  RMDir /r "\$INSTDIR\\lib"
  RMDir /r "\$INSTDIR\\share"
  Delete "\$INSTDIR\\uninstall.exe"
  RMDir "\$INSTDIR"
  Delete "\$SMPROGRAMS\\Ardour${MAJOR_VERSION}\\*.lnk"
  RMDir "\$SMPROGRAMS\\Ardour${MAJOR_VERSION}"
  Delete "\$DESKTOP\\Ardour ${ARDOUR_VERSION}.lnk"
SectionEnd
NSIS_EOF

echo "=== Building NSIS installer..."
(cd "$DESTDIR" && makensis ardour.nsi)
echo "=== Installer created: $OUTFILE"
echo "=== Size: $(du -sh "$OUTFILE" | cut -f1)"
