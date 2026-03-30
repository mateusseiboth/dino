#!/usr/bin/env bash
set -euo pipefail

# ── Dino Linux Bundle Creator ──
# Creates a zip with all binaries, libs, plugins, data and an install script.

BUILDDIR="${1:-build}"
STAGING="$BUILDDIR/package-staging"
BUNDLE_NAME="dino-linux-bundle"
BUNDLE_DIR="$BUILDDIR/$BUNDLE_NAME"

if [ ! -d "$STAGING/usr/local" ]; then
    echo "ERROR: staging directory not found at $STAGING/usr/local"
    echo "Run 'DESTDIR=$PWD/$BUILDDIR/package-staging meson install -C $BUILDDIR' first."
    exit 1
fi

echo "==> Preparing bundle in $BUNDLE_DIR ..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"/{bin,lib,lib/dino/plugins,share}

# ── Binary ──
cp "$BUILDDIR/main/dino" "$BUNDLE_DIR/bin/"

# Fix RUNPATH so the binary finds libs in ../lib relative to itself.
# The build sets RUNPATH to build-relative paths which won't work in the bundle.
if command -v patchelf &>/dev/null; then
    # --force-rpath sets DT_RPATH (not DT_RUNPATH).
    # DT_RPATH is searched BEFORE LD_LIBRARY_PATH, so even if the target machine
    # has LD_LIBRARY_PATH pointing to an old libdino install, our lib wins.
    patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "$BUNDLE_DIR/bin/dino"
    echo "    [patchelf] Set RPATH (DT_RPATH) to \$ORIGIN/../lib"
else
    echo "    [WARNING] patchelf not found — the portable run-dino.sh will still work"
    echo "              (it sets LD_LIBRARY_PATH), but running bin/dino directly may"
    echo "              pick up system libs. Install patchelf for a self-contained binary."
fi

# ── Libraries ──
for lib in libqlite libxmpp-vala libdino libcrypto-vala; do
    # Copy the real file (e.g. libdino.so.0.0) and create soname + dev symlinks
    real=$(find "$STAGING/usr/local/lib64/" -maxdepth 1 -name "${lib}.so.*.*" -type f 2>/dev/null || true)
    if [ -z "$real" ]; then
        real=$(find "$STAGING/usr/local/lib/" -maxdepth 1 -name "${lib}.so.*.*" -type f 2>/dev/null || true)
    fi
    if [ -n "$real" ]; then
        base=$(basename "$real")
        cp "$real" "$BUNDLE_DIR/lib/$base"
        # soname symlink (e.g. libdino.so.0 -> libdino.so.0.0)
        soname="${base%.*}"
        ln -sf "$base" "$BUNDLE_DIR/lib/$soname"
        # dev symlink (e.g. libdino.so -> libdino.so.0.0)
        devname="${lib}.so"
        ln -sf "$base" "$BUNDLE_DIR/lib/$devname"
    fi
done

# ── Plugins ──
for plugin in "$STAGING"/usr/local/lib64/dino/plugins/*.so "$STAGING"/usr/local/lib/dino/plugins/*.so; do
    [ -f "$plugin" ] && cp "$plugin" "$BUNDLE_DIR/lib/dino/plugins/"
done

# ── Locale / Icons / Desktop / Metainfo ──
if [ -d "$STAGING/usr/local/share/locale" ]; then
    cp -a "$STAGING/usr/local/share/locale" "$BUNDLE_DIR/share/"
fi
if [ -d "$STAGING/usr/local/share/icons" ]; then
    cp -a "$STAGING/usr/local/share/icons" "$BUNDLE_DIR/share/"
fi
if [ -d "$STAGING/usr/local/share/applications" ]; then
    cp -a "$STAGING/usr/local/share/applications" "$BUNDLE_DIR/share/"
fi
if [ -d "$STAGING/usr/local/share/metainfo" ]; then
    cp -a "$STAGING/usr/local/share/metainfo" "$BUNDLE_DIR/share/"
fi

# ── Install script ──
cp "$(dirname "$0")/install.sh" "$BUNDLE_DIR/install.sh"
chmod +x "$BUNDLE_DIR/install.sh"

# ── Launcher (portable run without install) ──
cat > "$BUNDLE_DIR/run-dino.sh" << 'LAUNCHER'
#!/usr/bin/env sh
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export LD_LIBRARY_PATH="$HERE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="$HERE/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
exec "$HERE/bin/dino" "$@"
LAUNCHER
chmod +x "$BUNDLE_DIR/run-dino.sh"

# ── Create zip ──
(cd "$BUILDDIR" && zip -r "$BUNDLE_NAME.zip" "$BUNDLE_NAME")
echo ""
echo "==> Bundle created: $BUILDDIR/$BUNDLE_NAME.zip"
echo "    To install:  unzip $BUNDLE_NAME.zip && cd $BUNDLE_NAME && sudo ./install.sh"
echo "    To run portable: unzip $BUNDLE_NAME.zip && cd $BUNDLE_NAME && ./run-dino.sh"
