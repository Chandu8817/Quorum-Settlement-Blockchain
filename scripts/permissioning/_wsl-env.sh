#!/usr/bin/env bash
# Shared environment shim for permissioning scripts.
# The project lives in WSL but tooling (npm/npx) is only reliably available
# via the nvm-managed Linux Node. Source this at the top of every script.
set -euo pipefail

# Pick a usable Linux Node (nvm install), newest first.
for v in v20.19.3 v24.2.0 v22.13.0; do
  if [ -x "$HOME/.nvm/versions/node/$v/bin/node" ]; then
    export PATH="$HOME/.nvm/versions/node/$v/bin:$PATH"
    break
  fi
done

# Fallback: nvm proper.
if ! command -v npx >/dev/null 2>&1 || npx --version 2>&1 | grep -qi 'invalid url'; then
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use --lts >/dev/null 2>&1 || true
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PROJECT_DIR
cd "$PROJECT_DIR"

echo "[env] node $(node --version) | npm $(npm --version) | cwd $PROJECT_DIR"
