#!/usr/bin/env bash
set -euo pipefail

PAGE_URL="https://linux.weixin.qq.com/en"
WORK_DIR="/tmp/wechat-linux-installer"
mkdir -p "$WORK_DIR"

log() {
  printf "\n==> %s\n" "$*"
}

warn() {
  printf "\n[WARN] %s\n" "$*" >&2
}

die() {
  printf "\n[ERROR] %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

detect_arch() {
  local raw
  raw="$(uname -m)"

  case "$raw" in
    aarch64|arm64)
      echo "arm64"
      ;;
    x86_64|amd64)
      echo "x86_64"
      ;;
    loongarch64)
      echo "loongarch64"
      ;;
    *)
      die "暂不支持的系统架构: $raw"
      ;;
  esac
}

fetch_html() {
  curl -fsSL "$PAGE_URL"
}

extract_url_candidates() {
  grep -Eoi 'https?://[^"'\'' <>]+|/[^"'\'' <>]+' || true
}

pick_best_url() {
  local html="$1"
  local arch="$2"

  local urls
  urls="$(printf '%s\n' "$html" | extract_url_candidates)"

  # 1) 优先匹配 deb + 精确架构
  local url
  url="$(
    printf '%s\n' "$urls" \
    | grep -Ei '\.deb([?#].*)?$' \
    | grep -Ei 'wechat' \
    | grep -Ei "$arch|aarch64|arm64|x86_64|amd64" \
    | grep -Ei "$arch" \
    | head -n 1
  )"

  # 2) 如果没匹配到，放宽成 deb + 任意常见架构标记
  if [ -z "$url" ]; then
    url="$(
      printf '%s\n' "$urls" \
      | grep -Ei '\.deb([?#].*)?$' \
      | grep -Ei 'wechat' \
      | grep -Ei 'aarch64|arm64|x86_64|amd64|loongarch64' \
      | head -n 1
    )"
  fi

  # 3) 再不行，尝试任何 deb
  if [ -z "$url" ]; then
    url="$(
      printf '%s\n' "$urls" \
      | grep -Ei '\.deb([?#].*)?$' \
      | grep -Ei 'wechat' \
      | head -n 1
    )"
  fi

  [ -n "$url" ] || die "没能从官网页面解析出 .deb 下载链接"

  if [[ "$url" =~ ^/ ]]; then
    url="https://linux.weixin.qq.com${url}"
  fi

  printf '%s\n' "$url"
}

download_pkg() {
  local url="$1"
  local file
  file="$(basename "${url%%\?*}")"

  [ -n "$file" ] || file="WeChatLinux.deb"

  local out="$WORK_DIR/$file"
  curl -fL "$url" -o "$out"
  printf '%s\n' "$out"
}

install_deb() {
  local pkg="$1"

  log "安装依赖工具"
  sudo apt-get update -y
  sudo apt-get install -y curl ca-certificates grep sed coreutils

  log "安装微信"
  # 用 apt 安装本地 deb，可以自动处理依赖
  sudo apt-get install -y "$pkg"
}

print_after_install() {
  cat <<'EOF'

安装完成。

你现在可以尝试以下方式启动微信：

1. 图形界面里直接搜索 WeChat / 微信
2. 终端里尝试：
   wechat
3. 如果上面不行，查找可执行文件：
   command -v wechat || ls /usr/bin | grep -i wechat

如果你是在 Android Terminal 的 Linux GUI 环境里使用：
- 需要确保图形界面已经正常启动
- 如果中文显示异常，通常是中文字体缺失导致
- 如果启动时报 sandbox / dbus / GPU 警告，不一定影响实际运行

EOF
}

main() {
  need_cmd curl
  need_cmd grep
  need_cmd sed
  need_cmd uname

  local arch
  arch="$(detect_arch)"
  log "检测到系统架构: $arch"

  local html
  log "读取官网页面: $PAGE_URL"
  html="$(fetch_html)" || die "无法访问微信 Linux 官网"

  local url
  url="$(pick_best_url "$html" "$arch")"
  log "解析到下载地址: $url"

  local pkg
  log "下载最新安装包"
  pkg="$(download_pkg "$url")"
  log "已下载到: $pkg"

  install_deb "$pkg"
  print_after_install
}

main "$@"
