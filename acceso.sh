#!/bin/bash
# Control del acceso remoto por parte del usuario de este Mac.
#   ~/.claude-remoto/acceso.sh pausar     bloquea las tareas remotas
#   ~/.claude-remoto/acceso.sh reanudar   las vuelve a permitir
#   ~/.claude-remoto/acceso.sh registro   muestra las últimas tareas recibidas
#   ~/.claude-remoto/acceso.sh estado
set -uo pipefail
BASE="${CLAUDE_REMOTO_BASE:-$HOME/.claude-remoto}"

case "${1:-estado}" in
  pausar)   touch "$BASE/PAUSADO"; echo "Acceso remoto pausado. Las tareas de Cris serán rechazadas." ;;
  reanudar) rm -f "$BASE/PAUSADO"; echo "Acceso remoto reanudado." ;;
  registro) if [ -f "$BASE/registro.log" ]; then tail -n "${2:-30}" "$BASE/registro.log"; else echo "Aún no se ha recibido ninguna tarea."; fi ;;
  estado)   if [ -f "$BASE/PAUSADO" ]; then echo "Acceso remoto: PAUSADO"; else echo "Acceso remoto: activo"; fi ;;
  *)        echo "Uso: acceso.sh pausar | reanudar | registro [n] | estado"; exit 2 ;;
esac
