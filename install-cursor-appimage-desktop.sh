#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/apps/cursor"
APPIMAGE_NAME="cursor.AppImage"
APPIMAGE_PATH="$INSTALL_DIR/$APPIMAGE_NAME"
EXTRACT_DIR="$INSTALL_DIR/squashfs-root"

LOCAL_BIN="$HOME/.local/bin"
BASHRC="$HOME/.bashrc"

DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
DESKTOP_FILE="$DESKTOP_DIR/cursor.desktop"
ICON_NAME="cursor"
ICON_PATH="$ICON_DIR/$ICON_NAME.png"

JSON_URL="https://raw.githubusercontent.com/oslook/cursor-ai-downloads/main/version-history.json"

log() {
  printf "\n==> %s\n" "$1"
}

append_if_missing() {
  local file="$1"
  local marker="$2"
  local content="$3"

  touch "$file"
  if ! grep -Fq "$marker" "$file"; then
    printf "\n%s\n" "$content" >> "$file"
  fi
}

get_latest_cursor_meta() {
  python3 - <<'PY'
import json, urllib.request, sys

url = "https://raw.githubusercontent.com/oslook/cursor-ai-downloads/main/version-history.json"
with urllib.request.urlopen(url) as r:
    data = json.load(r)

versions = data.get("versions")
if not isinstance(versions, list) or not versions:
    print("ERROR: version-history.json 中未找到 versions 列表", file=sys.stderr)
    sys.exit(1)

def parse_ver(v):
    out = []
    for x in str(v).split("."):
        try:
            out.append(int(x))
        except ValueError:
            out.append(0)
    return tuple(out)

best = None
best_tuple = None

for item in versions:
    if not isinstance(item, dict):
        continue
    ver = item.get("version")
    platforms = item.get("platforms", {})
    arm_url = platforms.get("linux-arm64")
    if ver and arm_url:
        vt = parse_ver(ver)
        if best is None or vt > best_tuple:
            best = {"version": ver, "url": arm_url}
            best_tuple = vt

if not best:
    print("ERROR: 未找到 linux-arm64 的可用版本", file=sys.stderr)
    sys.exit(1)

print(best["version"])
print(best["url"])
PY
}

log "创建目录"
mkdir -p "$INSTALL_DIR" "$LOCAL_BIN" "$DESKTOP_DIR" "$ICON_DIR"

log "获取最新 Cursor linux-arm64 下载链接"
mapfile -t CURSOR_META < <(get_latest_cursor_meta)
CURSOR_VERSION="${CURSOR_META[0]}"
CURSOR_URL="${CURSOR_META[1]}"

echo "Latest version: $CURSOR_VERSION"
echo "Download URL: $CURSOR_URL"

log "下载 Cursor AppImage"
wget -O "$APPIMAGE_PATH" "$CURSOR_URL"

log "赋予执行权限"
chmod +x "$APPIMAGE_PATH"

log "清理旧解包目录"
rm -rf "$EXTRACT_DIR"

log "解包 AppImage"
cd "$INSTALL_DIR"
"$APPIMAGE_PATH" --appimage-extract >/dev/null

log "确认启动文件存在"
if [ ! -x "$EXTRACT_DIR/AppRun" ]; then
  echo "错误：未找到 $EXTRACT_DIR/AppRun"
  exit 1
fi

log "创建默认启动命令：cursor"
cat > "$LOCAL_BIN/cursor" <<'EOF'
#!/usr/bin/env bash
set -e
APP="$HOME/apps/cursor/squashfs-root/AppRun"
if [ ! -x "$APP" ]; then
  echo "Cursor 未安装或启动文件不存在：$APP"
  exit 1
fi
export DISPLAY="${DISPLAY:-:0}"
exec "$APP" "$@"
EOF
chmod +x "$LOCAL_BIN/cursor"

log "创建保守启动命令：cursor-safe"
cat > "$LOCAL_BIN/cursor-safe" <<'EOF'
#!/usr/bin/env bash
set -e
APP="$HOME/apps/cursor/squashfs-root/AppRun"
if [ ! -x "$APP" ]; then
  echo "Cursor 未安装或启动文件不存在：$APP"
  exit 1
fi
export DISPLAY="${DISPLAY:-:0}"
exec "$APP" --disable-gpu --disable-gpu-compositing "$@"
EOF
chmod +x "$LOCAL_BIN/cursor-safe"

log "创建重启命令：rcursor"
cat > "$LOCAL_BIN/rcursor" <<'EOF'
#!/usr/bin/env bash
set -e
pkill -f "$HOME/apps/cursor/squashfs-root/AppRun" 2>/dev/null || true
sleep 1
nohup "$HOME/.local/bin/cursor" >/tmp/cursor.log 2>&1 &
EOF
chmod +x "$LOCAL_BIN/rcursor"

log "查找并安装图标"
FOUND_ICON=""
for candidate in \
  "$EXTRACT_DIR/usr/share/icons/hicolor/512x512/apps/cursor.png" \
  "$EXTRACT_DIR/usr/share/icons/hicolor/256x256/apps/cursor.png" \
  "$EXTRACT_DIR/usr/share/icons/hicolor/128x128/apps/cursor.png" \
  "$EXTRACT_DIR/usr/share/pixmaps/cursor.png" \
  "$EXTRACT_DIR/cursor.png" \
  "$EXTRACT_DIR/.DirIcon"
do
  if [ -f "$candidate" ]; then
    FOUND_ICON="$candidate"
    break
  fi
done

if [ -n "$FOUND_ICON" ]; then
  cp "$FOUND_ICON" "$ICON_PATH"
  echo "图标已安装到: $ICON_PATH"
else
  echo "警告：未找到 Cursor 图标，菜单项会先使用系统默认图标"
fi

log "创建桌面菜单启动器"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Cursor
GenericName=AI Code Editor
Comment=Cursor AI Editor
Exec=$HOME/.local/bin/cursor %F
TryExec=$HOME/.local/bin/cursor
Terminal=false
Categories=Development;IDE;Utility;TextEditor;
StartupNotify=true
StartupWMClass=Cursor
Icon=$ICON_NAME
MimeType=text/plain;inode/directory;
Keywords=cursor;editor;code;ide;ai;
EOF
chmod 644 "$DESKTOP_FILE"

log "确保 ~/.local/bin 在 PATH 中"
append_if_missing "$BASHRC" 'export PATH="$HOME/.local/bin:$PATH"' 'export PATH="$HOME/.local/bin:$PATH"'

log "刷新桌面菜单缓存"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi

log "安装完成"
echo
echo "可用命令："
echo "  cursor         默认启动 Cursor"
echo "  cursor-safe    关闭 GPU 方式启动 Cursor"
echo "  rcursor        重启 Cursor"
echo
echo "桌面菜单文件：$DESKTOP_FILE"
echo "图标文件：$ICON_PATH"
echo "日志文件：/tmp/cursor.log"
echo
echo "让 PATH 立即生效："
echo "  source ~/.bashrc"
echo
echo "如果菜单里还没立刻出现 Cursor，可注销并重新登录桌面会话一次。"
