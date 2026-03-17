#!/usr/bin/env bash
set -euo pipefail

REPO="shiftkey/desktop"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
INSTALL_DIR="${HOME}/apps/github-desktop"
LOCAL_BIN="${HOME}/.local/bin"
BASHRC="${HOME}/.bashrc"
DEB_PATH=""
TMP_JSON=""

log() {
  printf "\n==> %s\n" "$1"
}

warn() {
  printf "\n[warn] %s\n" "$1"
}

die() {
  printf "\n[err] %s\n" "$1" >&2
  exit 1
}

cleanup() {
  [ -n "${TMP_JSON:-}" ] && [ -f "$TMP_JSON" ] && rm -f "$TMP_JSON"
}
trap cleanup EXIT

append_if_missing() {
  local file="$1"
  local marker="$2"
  local content="$3"

  touch "$file"
  if ! grep -Fq "$marker" "$file"; then
    printf "\n%s\n" "$content" >> "$file"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

detect_arch() {
  local uname_arch
  uname_arch="$(uname -m)"

  case "$uname_arch" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      die "暂不支持的架构：$uname_arch"
      ;;
  esac
}

get_latest_deb_meta() {
  local arch="$1"

  python3 - "$API_URL" "$arch" <<'PY'
import json
import sys
import urllib.request

api_url = sys.argv[1]
arch = sys.argv[2]

req = urllib.request.Request(
    api_url,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "github-desktop-installer"
    }
)

with urllib.request.urlopen(req) as r:
    data = json.load(r)

tag_name = data.get("tag_name")
release_name = data.get("name") or tag_name
assets = data.get("assets", [])

if not tag_name or not isinstance(assets, list) or not assets:
    print("ERROR: 无法从 GitHub API 获取 release 资产", file=sys.stderr)
    sys.exit(1)

candidates = []
for a in assets:
    name = a.get("name", "")
    url = a.get("browser_download_url", "")
    if not name.endswith(".deb"):
        continue

    lname = name.lower()
    # 优先找显式架构包
    if arch in lname:
        candidates.append((2, name, url))
    # 兼容少数未写架构但仍为 deb 的情况
    elif arch == "amd64" and "arm" not in lname:
        candidates.append((1, name, url))

if not candidates:
    print(f"ERROR: latest release 中未找到适用于 {arch} 的 .deb 安装包", file=sys.stderr)
    sys.exit(1)

candidates.sort(key=lambda x: (-x[0], x[1]))
best = candidates[0]

print(tag_name)
print(release_name)
print(best[1])
print(best[2])
PY
}

log "检查依赖"
need_cmd curl
need_cmd python3
need_cmd sudo
need_cmd apt

ARCH="$(detect_arch)"
log "检测系统架构：${ARCH}"

log "创建目录"
mkdir -p "$INSTALL_DIR" "$LOCAL_BIN"

log "获取 ${REPO} 最新 release 信息"
mapfile -t META < <(get_latest_deb_meta "$ARCH")

RELEASE_TAG="${META[0]}"
RELEASE_NAME="${META[1]}"
DEB_NAME="${META[2]}"
DEB_URL="${META[3]}"
DEB_PATH="${INSTALL_DIR}/${DEB_NAME}"

echo "Latest tag : ${RELEASE_TAG}"
echo "Release    : ${RELEASE_NAME}"
echo "Package    : ${DEB_NAME}"
echo "URL        : ${DEB_URL}"

log "下载 .deb 安装包"
curl -L --fail --output "$DEB_PATH" "$DEB_URL"

log "安装 GitHub Desktop"
sudo apt update
sudo apt install -y "$DEB_PATH"

log "创建便捷启动命令：gdesktop"
cat > "${LOCAL_BIN}/gdesktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec github-desktop "$@"
EOF
chmod +x "${LOCAL_BIN}/gdesktop"

log "确保 ~/.local/bin 在 PATH 中"
append_if_missing "$BASHRC" 'export PATH="$HOME/.local/bin:$PATH"' 'export PATH="$HOME/.local/bin:$PATH"'

log "安装完成"
echo
echo "可用命令："
echo "  github-desktop"
echo "  gdesktop"
echo
echo "如果当前 shell 还没生效，请执行："
echo "  source ~/.bashrc"
