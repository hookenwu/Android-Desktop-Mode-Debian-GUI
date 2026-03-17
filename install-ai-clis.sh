#!/usr/bin/env bash
set -euo pipefail

log(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
warn(){ printf "\n\033[33m[warn]\033[0m %s\n" "$*"; }
die(){ printf "\n\033[31m[err]\033[0m %s\n" "$*"; exit 1; }

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

ensure_local_bin_path() {
  local mark_begin="# >>> local bin path >>>"
  local mark_end="# <<< local bin path <<<"
  local content='export PATH="$HOME/.local/bin:$PATH"'

  touch "$HOME/.bashrc"

  if grep -qF "$mark_begin" "$HOME/.bashrc" 2>/dev/null; then
    awk -v b="$mark_begin" -v e="$mark_end" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      !skip {print}
    ' "$HOME/.bashrc" > "$HOME/.bashrc.tmp" && mv "$HOME/.bashrc.tmp" "$HOME/.bashrc"
  fi

  {
    echo "$mark_begin"
    echo "$content"
    echo "$mark_end"
  } >> "$HOME/.bashrc"
}

main() {
  load_nvm
  hash -r

  command -v npm >/dev/null 2>&1 || die "未检测到 npm。请先执行基础安装脚本并重新打开终端。"

  log "[install] Gemini CLI"
  npm install -g @google/gemini-cli

  log "[install] Claude Code"
  ensure_local_bin_path
  curl -fsSL https://claude.ai/install.sh | bash

  echo
  echo "======== 安装完成 ========"
  command -v gemini >/dev/null 2>&1 && echo "gemini: $(gemini --version 2>/dev/null || echo installed)"
  command -v claude >/dev/null 2>&1 && echo "claude: installed"
  echo
  echo "建议执行："
  echo "  source ~/.bashrc"
  echo "或者重新打开一个终端"
}

main "$@"
