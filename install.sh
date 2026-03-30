#!/usr/bin/env bash
set -euo pipefail

# ── Dino Installer for Linux ──
# Installs our custom build to /opt/dino/ (isolated from RPM).
# Overwrites /usr/bin/dino (and any RPM binary) with a wrapper that points there.
# This avoids ANY conflict with system libs — no ldconfig/SELinux issues.
#
# Usage:
#   sudo ./install.sh              # install
#   sudo ./install.sh --uninstall  # uninstall (restores RPM binary backup)

OPT_DIR="/opt/dino"
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) UNINSTALL=true; shift ;;
        -h|--help)
            echo "Usage: sudo ./install.sh [--uninstall]"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# ── Detect system binary location (RPM/DEB or default) ──
SYS_BIN="/usr/bin/dino"
SYS_PLUGINDIR=""
SYS_SHARE_ROOT=""
SYS_DBUS_DIR=""

_detect_pkg() {
    local files="$1"
    local bin
    bin="$(echo "$files" | grep '/bin/dino$' | head -1)"
    [ -n "$bin" ] && SYS_BIN="$bin"
    SYS_PLUGINDIR="$(echo "$files" | grep 'dino/plugins/.*\.so$' | head -1 | sed 's|/[^/]*\.so$||')"
    SYS_SHARE_ROOT="$(echo "$files" | grep '/share/applications/im\.dino.*desktop$' | head -1 | sed 's|/applications/im\.dino.*||')"
    SYS_DBUS_DIR="$(echo "$files" | grep '/dbus-1/services/' | head -1 | sed 's|/[^/]*$||')"
}

if command -v rpm &>/dev/null && rpm -q dino &>/dev/null 2>&1; then
    echo "==> RPM detected: $(rpm -q dino)"
    _detect_pkg "$(rpm -ql dino 2>/dev/null)"
elif command -v dpkg &>/dev/null && dpkg -s dino &>/dev/null 2>&1; then
    echo "==> DEB detected."
    _detect_pkg "$(dpkg -L dino 2>/dev/null)"
fi

# ── Uninstall ──
if $UNINSTALL; then
    echo "==> Uninstalling..."
    # Restore backed-up system binary if available
    if [ -f "${SYS_BIN}.orig" ]; then
        echo "    Restoring $SYS_BIN from backup..."
        cp "${SYS_BIN}.orig" "$SYS_BIN"
        chmod 755 "$SYS_BIN"
    else
        echo "    No backup found at ${SYS_BIN}.orig"
        echo "    You may need to run: sudo dnf reinstall dino"
        rm -f "$SYS_BIN"
    fi
    rm -rf "$OPT_DIR"
    echo "==> Done. Backup restored at $SYS_BIN"
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "WARNING: Not running as root — installation may fail."
    echo "         Re-run with: sudo ./install.sh"
fi

# ── Ensure patchelf is available ──
if ! command -v patchelf &>/dev/null; then
    echo "==> patchelf not found — installing..."
    if   command -v dnf     &>/dev/null; then dnf install -y patchelf
    elif command -v apt-get &>/dev/null; then apt-get install -y patchelf
    elif command -v zypper  &>/dev/null; then zypper install -y patchelf
    elif command -v pacman  &>/dev/null; then pacman -S --noconfirm patchelf
    else
        echo "ERROR: patchelf not found and no supported package manager available."
        exit 1
    fi
fi

# ══════════════════════════════════════════════════════════════
# 1) Install everything to /opt/dino/ (our isolated dir)
# ══════════════════════════════════════════════════════════════

echo ""
echo "==> Installing to $OPT_DIR ..."

rm -rf "$OPT_DIR"
mkdir -p "$OPT_DIR/bin" "$OPT_DIR/lib" "$OPT_DIR/lib/plugins"

# Binary — patchelf RPATH to our isolated lib dir.
# --force-rpath sets DT_RPATH, which is searched BEFORE LD_LIBRARY_PATH.
# This prevents old installs that set LD_LIBRARY_PATH from interfering.
install -m755 "$HERE/bin/dino" "$OPT_DIR/bin/dino"
patchelf --force-rpath --set-rpath "$OPT_DIR/lib" "$OPT_DIR/bin/dino"
echo "    binary  → $OPT_DIR/bin/dino  (DT_RPATH=$OPT_DIR/lib)"

# Runtime libs (only our 4 libs, no touching system dirs)
for f in "$HERE"/lib/lib*.so.*.*; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    install -m755 "$f" "$OPT_DIR/lib/$base"
    soname="${base%.*}"
    devname="$(echo "$base" | sed 's/\.so\..*/\.so/')"
    ln -sf "$base" "$OPT_DIR/lib/$soname"
    ln -sf "$base" "$OPT_DIR/lib/$devname"
    echo "    lib     → $OPT_DIR/lib/$base"
done

# Plugins
for f in "$HERE"/lib/dino/plugins/*.so; do
    [ -f "$f" ] || continue
    install -m755 "$f" "$OPT_DIR/lib/plugins/$(basename "$f")"
done
echo "    plugins → $OPT_DIR/lib/plugins/"

# ══════════════════════════════════════════════════════════════
# 2) Clean up any previous installs that may have left stale
#    libs or wrappers in /usr/local (they confuse the loader)
# ══════════════════════════════════════════════════════════════

echo ""
echo "==> Cleaning up previous installs in /usr/local ..."
for old_lib in /usr/local/lib/libdino.so* /usr/local/lib64/libdino.so* \
               /usr/local/lib/libqlite.so* /usr/local/lib64/libqlite.so* \
               /usr/local/lib/libxmpp-vala.so* /usr/local/lib64/libxmpp-vala.so* \
               /usr/local/lib/libcrypto-vala.so* /usr/local/lib64/libcrypto-vala.so*; do
    [ -e "$old_lib" ] && rm -f "$old_lib" && echo "    removed $old_lib" || true
done
rm -f /etc/ld.so.conf.d/dino-local.conf /etc/ld.so.conf.d/dino.conf
ldconfig

# ══════════════════════════════════════════════════════════════
# 3) Overwrite the system binary with a wrapper shell script
#    The wrapper sets LD_LIBRARY_PATH to our isolated lib dir
#    so the OS always loads OUR libdino, not the RPM's.
# ══════════════════════════════════════════════════════════════

echo ""
echo "==> Installing wrapper at $SYS_BIN ..."

# Backup the original ELF binary (once only)
if [ -f "$SYS_BIN" ] && ! grep -q "opt/dino" "$SYS_BIN" 2>/dev/null; then
    cp "$SYS_BIN" "${SYS_BIN}.orig"
    echo "    backup  → ${SYS_BIN}.orig"
fi

# Write the wrapper — single-quoted heredoc so no expansion issues
OPT_BIN="$OPT_DIR/bin/dino"
OPT_LIB="$OPT_DIR/lib"
cat > "$SYS_BIN" << EOF
#!/usr/bin/env sh
export LD_LIBRARY_PATH="$OPT_LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$OPT_BIN" "\$@"
EOF
chmod 755 "$SYS_BIN"
echo "    wrapper → $SYS_BIN → exec $OPT_BIN"

# Also overwrite /usr/local/bin/dino if it exists (left by previous installs)
if [ -d /usr/local/bin ] && [ "$SYS_BIN" != "/usr/local/bin/dino" ]; then
    cat > /usr/local/bin/dino << EOF
#!/usr/bin/env sh
export LD_LIBRARY_PATH="$OPT_LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$OPT_BIN" "\$@"
EOF
    chmod 755 /usr/local/bin/dino
    echo "    wrapper → /usr/local/bin/dino → exec $OPT_BIN"
fi

# ══════════════════════════════════════════════════════════════
# 3) Overwrite system plugins (RPM plugin dir) with our plugins
# ══════════════════════════════════════════════════════════════

if [ -n "$SYS_PLUGINDIR" ] && [ -d "$SYS_PLUGINDIR" ]; then
    echo ""
    echo "==> Overwriting system plugins at $SYS_PLUGINDIR/ ..."
    for f in "$HERE"/lib/dino/plugins/*.so; do
        [ -f "$f" ] || continue
        install -m755 "$f" "$SYS_PLUGINDIR/$(basename "$f")"
        echo "    plugin  → $SYS_PLUGINDIR/$(basename "$f")"
    done
fi

# ══════════════════════════════════════════════════════════════
# 4) Overwrite system share/desktop/dbus files
# ══════════════════════════════════════════════════════════════

_install_share() {
    local share_root="$1"
    if [ -d "$HERE/share/locale" ]; then
        mkdir -p "$share_root/locale"
        cp -a "$HERE/share/locale/." "$share_root/locale/"
    fi
    if [ -d "$HERE/share/icons" ]; then
        mkdir -p "$share_root/icons"
        cp -a "$HERE/share/icons/." "$share_root/icons/"
    fi
    if [ -d "$HERE/share/applications" ]; then
        mkdir -p "$share_root/applications"
        sed "s|^Exec=.*|Exec=$SYS_BIN %U|" \
            "$HERE/share/applications/im.dino.Dino.desktop" \
            > "$share_root/applications/im.dino.Dino.desktop"
        chmod 644 "$share_root/applications/im.dino.Dino.desktop"
    fi
    if [ -d "$HERE/share/metainfo" ]; then
        mkdir -p "$share_root/metainfo"
        install -m644 "$HERE/share/metainfo/im.dino.Dino.appdata.xml" \
            "$share_root/metainfo/im.dino.Dino.appdata.xml"
    fi
}

if [ -n "$SYS_SHARE_ROOT" ] && [ -d "$SYS_SHARE_ROOT" ]; then
    echo ""
    echo "==> Overwriting system share files at $SYS_SHARE_ROOT/ ..."
    _install_share "$SYS_SHARE_ROOT"
fi
# Also install to /usr/local/share as fallback
_install_share "/usr/local/share"

if [ -n "$SYS_DBUS_DIR" ] && [ -d "$SYS_DBUS_DIR" ]; then
    echo "==> DBus service → $SYS_DBUS_DIR/im.dino.Dino.service"
    printf '[D-BUS Service]\nName=im.dino.Dino\nExec=%s\n' "$SYS_BIN" \
        > "$SYS_DBUS_DIR/im.dino.Dino.service"
    chmod 644 "$SYS_DBUS_DIR/im.dino.Dino.service"
fi

# ── Update icon/desktop caches ──
if command -v gtk-update-icon-cache &>/dev/null; then
    [ -n "$SYS_SHARE_ROOT" ] && gtk-update-icon-cache -f -t "$SYS_SHARE_ROOT/icons/hicolor" 2>/dev/null || true
    gtk-update-icon-cache -f -t "/usr/local/share/icons/hicolor" 2>/dev/null || true
fi
if command -v update-desktop-database &>/dev/null; then
    [ -n "$SYS_SHARE_ROOT" ] && update-desktop-database "$SYS_SHARE_ROOT/applications" 2>/dev/null || true
    update-desktop-database "/usr/local/share/applications" 2>/dev/null || true
fi

echo ""
echo "==> Done!"
echo "    Run:       dino"
echo "    Binary:    $OPT_DIR/bin/dino  (RPATH=$OPT_DIR/lib)"
echo "    Wrapper:   $SYS_BIN"
echo "    Libs:      $OPT_DIR/lib/"
echo "    Plugins:   $OPT_DIR/lib/plugins/"
echo ""
echo "    To uninstall: sudo ./install.sh --uninstall"
