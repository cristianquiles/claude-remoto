#!/bin/bash
# Punto de entrada de las tareas remotas. Lo invoca Cris por SSH:
#   remoto.sh ping
#   remoto.sh tarea      < texto de la tarea
#   remoto.sh continuar  < texto (continúa la conversación anterior)
set -uo pipefail

BASE="${CLAUDE_REMOTO_BASE:-$HOME/.claude-remoto}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

[ -f "$BASE/config" ] || { echo "ERROR: falta $BASE/config. Ejecuta de nuevo el instalador." >&2; exit 2; }
# shellcheck source=/dev/null
. "$BASE/config"

CLAUDE="$(command -v claude || true)"
[ -n "$CLAUDE" ] || { echo "ERROR: Claude Code no está instalado." >&2; exit 2; }

if [ -s "$BASE/credencial" ]; then
  CRED="$(cat "$BASE/credencial")"
  case "$CRED" in
    sk-ant-api*) export ANTHROPIC_API_KEY="$CRED" ;;
    *)           export CLAUDE_CODE_OAUTH_TOKEN="$CRED" ;;
  esac
  unset CRED
fi

registro() {
  printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$BASE/registro.log"
}

case "${1:-}" in
  ping)
    echo "equipo:   $(scutil --get ComputerName 2>/dev/null || hostname)"
    echo "usuario:  $(whoami)"
    echo "claude:   $("$CLAUDE" --version 2>/dev/null)"
    echo "carpeta:  $CARPETA_TRABAJO"
    echo "permisos: $MODO_PERMISOS · $HERRAMIENTAS_PERMITIDAS"
    if [ -f "$BASE/PAUSADO" ]; then echo "estado:   PAUSADO"; else echo "estado:   activo"; fi
    ;;
  tarea|continuar)
    if [ -f "$BASE/PAUSADO" ]; then
      echo "El acceso remoto está pausado por el usuario de este equipo." >&2
      exit 3
    fi
    PROMPT="$(cat)"
    [ -n "$PROMPT" ] || { echo "ERROR: tarea vacía." >&2; exit 2; }
    registro "$1" "$(printf '%s' "$PROMPT" | tr '\n\t' '  ' | cut -c1-500)"
    cd "$CARPETA_TRABAJO" || { echo "ERROR: no existe $CARPETA_TRABAJO" >&2; exit 2; }
    EXTRA=()
    [ "$1" = "continuar" ] && EXTRA=(--continue)
    printf '%s' "$PROMPT" | "$CLAUDE" -p ${EXTRA[@]+"${EXTRA[@]}"} \
      --permission-mode "$MODO_PERMISOS" \
      --allowedTools "$HERRAMIENTAS_PERMITIDAS"
    ;;
  *)
    echo "Uso: remoto.sh ping | tarea | continuar   (la tarea se lee por la entrada estándar)" >&2
    exit 2
    ;;
esac
