#!/usr/bin/env bash
set -euo pipefail

log(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
warn(){ printf "\n\033[33m[warn]\033[0m %s\n" "$*"; }
die(){ printf "\n\033[31m[err]\033[0m %s\n" "$*"; exit 1; }

# ====== 可改配置 ======
# 可选写法：
#   NODE_VERSION="lts/*"
#   NODE_VERSION="22"
#   NODE_VERSION="v22.14.0"
NODE_VERSION="lts/*"

SSH_KEY="${HOME}/.ssh/id_ed25519"

ARCH_RAW=""
ARCH_DEB=""
NVM_VERSION=""
GIT_NAME=""
GIT_EMAIL=""
SSH_COMMENT=""

load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
  fi

  if [ -s "$NVM_DIR/bash_completion" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/bash_completion"
  fi
}

rewrite_file_block() {
  local target_file="$1"
  local mark_begin="$2"
  local mark_end="$3"
  local content="$4"

  touch "$target_file"

  if grep -qF "$mark_begin" "$target_file" 2>/dev/null; then
    awk -v b="$mark_begin" -v e="$mark_end" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      !skip {print}
    ' "$target_file" > "$target_file.tmp" && mv "$target_file.tmp" "$target_file"
  fi

  {
    echo "$mark_begin"
    echo "$content"
    echo "$mark_end"
  } >> "$target_file"
}

rewrite_bashrc_block() {
  rewrite_file_block "$HOME/.bashrc" "$1" "$2" "$3"
}

detect_architecture() {
  log "[check] 检测系统架构"

  ARCH_RAW="$(uname -m)"

  if command -v dpkg >/dev/null 2>&1; then
    ARCH_DEB="$(dpkg --print-architecture)"
  else
    case "$ARCH_RAW" in
      x86_64) ARCH_DEB="amd64" ;;
      aarch64|arm64) ARCH_DEB="arm64" ;;
      armv7l) ARCH_DEB="armhf" ;;
      i386|i686) ARCH_DEB="i386" ;;
      *) die "无法识别当前架构：uname -m=$ARCH_RAW" ;;
    esac
  fi

  case "$ARCH_DEB" in
    amd64|arm64|armhf|i386)
      ;;
    *)
      die "当前脚本暂未适配此架构：raw=$ARCH_RAW, deb=$ARCH_DEB"
      ;;
  esac

  echo "架构原始值: $ARCH_RAW"
  echo "Debian/Ubuntu 架构名: $ARCH_DEB"
}

ensure_nvm_block() {
  log "[install] 写入 nvm 初始化到 ~/.bashrc"

  local mark_begin="# >>> nvm >>>"
  local mark_end="# <<< nvm <<<"
  local content
  content=$(
    cat <<'BLOCK'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
BLOCK
  )

  rewrite_bashrc_block "$mark_begin" "$mark_end" "$content"
}

resolve_nvm_version() {
  log "[check] 自动获取最新 nvm 版本"

  local latest_tag=""

  if command -v git >/dev/null 2>&1; then
    latest_tag="$(git ls-remote --tags --refs https://github.com/nvm-sh/nvm.git 2>/dev/null \
      | awk -F/ '{print $3}' \
      | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
      | sort -V \
      | tail -n 1 || true)"
  fi

  if [ -z "$latest_tag" ]; then
    latest_tag="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null \
      | jq -r '.tag_name // empty' || true)"
  fi

  if [ -z "$latest_tag" ]; then
    die "无法自动获取最新 nvm 版本，请检查网络或 GitHub 访问能力"
  fi

  NVM_VERSION="$latest_tag"
  echo "最新 nvm 版本: $NVM_VERSION"
}

install_base_packages() {
  log "[install] 安装最基础依赖"

  sudo apt-get update -y
  sudo apt-get install -y \
    git curl wget jq \
    fonts-noto-cjk fonts-noto-color-emoji \
    openssh-client
}

install_nvm_only() {
  export NVM_DIR="$HOME/.nvm"

  if [ -d "$NVM_DIR" ] && [ ! -s "$NVM_DIR/nvm.sh" ]; then
    warn "检测到残缺的 $NVM_DIR，先删除后重装"
    rm -rf "$NVM_DIR"
  fi

  [ -n "$NVM_VERSION" ] || die "NVM_VERSION 为空，未先完成版本解析"

  local attempt
  for attempt in 1 2 3; do
    log "[install] 安装 nvm ${NVM_VERSION}（尝试 $attempt/3）"
    if curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash; then
      load_nvm
      if command -v nvm >/dev/null 2>&1; then
        return 0
      fi
    fi
    warn "nvm 安装失败，第 $attempt 次重试前等待 3 秒..."
    sleep 3
  done

  die "nvm 安装失败，请检查网络后重试"
}

install_node() {
  log "[install] 安装 Node.js（通过 nvm）"

  export NVM_DIR="$HOME/.nvm"
  load_nvm

  if ! command -v nvm >/dev/null 2>&1; then
    install_nvm_only
  fi

  load_nvm
  command -v nvm >/dev/null 2>&1 || die "nvm 仍不可用，停止安装"

  local install_target="$NODE_VERSION"
  local alias_target="$NODE_VERSION"

  case "$NODE_VERSION" in
    --lts)
      install_target="--lts"
      alias_target="lts/*"
      ;;
    lts|lts/*)
      install_target="--lts"
      alias_target="lts/*"
      ;;
  esac

  nvm install "$install_target"
  nvm alias default "$alias_target"
  nvm use default >/dev/null 2>&1 || nvm use "$alias_target" >/dev/null 2>&1 || true
  hash -r

  log "[install] Node ready:"
  node -v || true
  npm -v || true
}

ensure_ssh_dir() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
}

prompt_git_identity() {
  log "[input] 请输入 Git 身份信息"

  local default_name=""
  local default_email=""

  default_name="$(git config --global user.name 2>/dev/null || true)"
  default_email="$(git config --global user.email 2>/dev/null || true)"

  while :; do
    if [ -n "$default_name" ]; then
      read -r -p "Git user.name [当前: ${default_name}]: " GIT_NAME
      GIT_NAME="${GIT_NAME:-$default_name}"
    else
      read -r -p "Git user.name: " GIT_NAME
    fi
    [ -n "$GIT_NAME" ] && break
    warn "Git user.name 不能为空"
  done

  while :; do
    if [ -n "$default_email" ]; then
      read -r -p "Git user.email [当前: ${default_email}]: " GIT_EMAIL
      GIT_EMAIL="${GIT_EMAIL:-$default_email}"
    else
      read -r -p "Git user.email: " GIT_EMAIL
    fi

    if printf '%s' "$GIT_EMAIL" | grep -Eq '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'; then
      break
    fi
    warn "请输入有效的邮箱地址"
  done

  SSH_COMMENT="$GIT_EMAIL"
}

setup_ssh_key() {
  log "[install] 配置 SSH 密钥"
  ensure_ssh_dir

  if [ -f "$SSH_KEY" ]; then
    warn "SSH 私钥已存在，跳过生成：$SSH_KEY"
  else
    [ -n "$SSH_COMMENT" ] || die "SSH_COMMENT 为空，请先输入 Git 邮箱"
    ssh-keygen -t ed25519 -C "$SSH_COMMENT" -f "$SSH_KEY" -N ""
    log "[install] SSH 密钥已生成：$SSH_KEY"
  fi

  chmod 600 "$SSH_KEY" 2>/dev/null || true
  chmod 644 "$SSH_KEY.pub" 2>/dev/null || true

  if ! grep -qsE '^[[:space:]]*Host[[:space:]]+\*$' "$HOME/.ssh/config" 2>/dev/null; then
    cat >> "$HOME/.ssh/config" <<'BLOCK'
Host *
  AddKeysToAgent yes
  ServerAliveInterval 60
  ServerAliveCountMax 120
BLOCK
  fi
  chmod 600 "$HOME/.ssh/config"
}

setup_git_config() {
  log "[install] 配置 Git"

  prompt_git_identity

  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global core.autocrlf input

  if [ -f "$SSH_KEY" ]; then
    git config --global core.sshCommand "ssh -i $SSH_KEY"
  fi
}

print_post_setup_info() {
  echo
  echo "======== SSH / Git 信息 ========"
  echo "架构(raw):     ${ARCH_RAW:-unknown}"
  echo "架构(deb):     ${ARCH_DEB:-unknown}"
  echo "nvm version:   ${NVM_VERSION:-unknown}"
  echo "Git user.name : $(git config --global user.name || true)"
  echo "Git user.email: $(git config --global user.email || true)"
  echo
  if [ -f "$SSH_KEY.pub" ]; then
    echo "SSH 公钥如下，添加到 GitHub / GitLab："
    echo "----------------------------------------"
    cat "$SSH_KEY.pub"
    echo
    echo "指纹："
    ssh-keygen -lf "$SSH_KEY.pub" || true
    echo "----------------------------------------"
  fi
}

check_result() {
  echo
  echo "======== 安装完成 ========"
  command -v git >/dev/null 2>&1 && echo "git:  $(git --version)"
  command -v curl >/dev/null 2>&1 && echo "curl: $(curl --version | head -n 1)"
  command -v wget >/dev/null 2>&1 && echo "wget: $(wget --version | head -n 1)"
  command -v jq >/dev/null 2>&1 && echo "jq:   $(jq --version)"
  command -v ssh >/dev/null 2>&1 && echo "ssh:  $(ssh -V 2>&1)"
  command -v node >/dev/null 2>&1 && echo "node: $(node -v)"
  command -v npm >/dev/null 2>&1 && echo "npm:  $(npm -v)"
  echo
  echo "建议执行："
  echo "  source ~/.bashrc"
  echo "或者直接重新打开一个终端"
}

main() {
  detect_architecture
  install_base_packages
  resolve_nvm_version
  ensure_nvm_block
  install_node
  setup_git_config
  setup_ssh_key
  print_post_setup_info
  check_result
}

main "$@"
