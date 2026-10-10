#!/bin/bash
# Deshace la instalación. No toca la carpeta de trabajo ni Claude Code.
set -uo pipefail
BASE="${CLAUDE_REMOTO_BASE:-$HOME/.claude-remoto}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

echo "Esto desconectará este Mac de Cris y borrará la credencial guardada."
read -r -p "¿Continuar? (s/n) [n]: " R </dev/tty || true
[ "${R:-n}" = "s" ] || { echo "Cancelado."; exit 0; }

if command -v tailscale >/dev/null 2>&1; then
  sudo "$(command -v tailscale)" logout 2>/dev/null || true
  sudo "$(command -v brew)" services stop tailscale >/dev/null 2>&1 || true
  read -r -p "¿Desinstalar también Tailscale? (s/n) [s]: " R </dev/tty || true
  [ "${R:-s}" = "s" ] && brew uninstall tailscale >/dev/null 2>&1 && echo "Tailscale desinstalado."
fi

if [ -f "$BASE/config" ]; then
  # shellcheck source=/dev/null
  . "$BASE/config"
  echo "Tu carpeta de trabajo ($CARPETA_TRABAJO) no se ha tocado."
fi
rm -rf "$BASE"
echo "Listo. Claude Code sigue instalado para tu uso normal."
