#!/bin/bash
# Comprueba que todo está instalado y que Claude responde de verdad.
#   ~/.claude-remoto/comprobar.sh          comprobación completa (hace una tarea de prueba)
#   ~/.claude-remoto/comprobar.sh --rapido sin tarea de prueba
set -uo pipefail

BASE="${CLAUDE_REMOTO_BASE:-$HOME/.claude-remoto}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
RAPIDO=""; [ "${1:-}" = "--rapido" ] && RAPIDO=1

N_OK=0; N_AVISO=0; N_FALLO=0
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; N_OK=$((N_OK+1)); }
aviso() { printf '  \033[33m!\033[0m %s\n' "$*"; N_AVISO=$((N_AVISO+1)); }
mal()   { printf '  \033[31m✗\033[0m %s\n' "$*"; N_FALLO=$((N_FALLO+1)); }

echo
echo "  Claude remoto · comprobación"
echo "  ────────────────────────────"

# macOS
if [ "$(uname)" = "Darwin" ]; then ok "macOS $(sw_vers -productVersion)"; else mal "No es macOS"; fi

# Tailscale
TS="$(command -v tailscale || true)"
DNS=""
if [ -d /Applications/Tailscale.app ]; then
  mal "Está instalada la app de Tailscale: no permite la conexión SSH. Desinstálala y usa la de Homebrew."
fi
if [ -z "$TS" ]; then
  mal "Tailscale no está instalado"
else
  JSON="$("$TS" status --json 2>/dev/null || true)"
  ESTADO="$(printf '%s' "$JSON" | grep -o '"BackendState": *"[A-Za-z]*"' | head -1 | sed 's/.*"\([A-Za-z]*\)"$/\1/')"
  DNS="$(printf '%s' "$JSON" | grep -o '"DNSName": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/; s/\.$//')"
  case "$ESTADO" in
    Running) ok "Tailscale conectado ($DNS · $("$TS" ip -4 2>/dev/null | head -1))" ;;
    "")      mal "El servicio de Tailscale no está en marcha (sudo brew services start tailscale)" ;;
    *)       mal "Tailscale no está conectado (estado: $ESTADO)" ;;
  esac
  if [ "$ESTADO" = "Running" ]; then
    PREFS="$("$TS" debug prefs 2>/dev/null || true)"
    if printf '%s' "$PREFS" | grep -q '"RunSSH": *true'; then
      ok "Conexión SSH de Tailscale activada"
    elif [ -n "$PREFS" ]; then
      mal "Conexión SSH de Tailscale desactivada (sudo tailscale set --ssh)"
    else
      aviso "No se pudo verificar si la conexión SSH está activada"
    fi
  fi
fi

# Claude Code
CLAUDE="$(command -v claude || true)"
if [ -n "$CLAUDE" ]; then ok "Claude Code $("$CLAUDE" --version 2>/dev/null | awk '{print $1}')"; else mal "Claude Code no está instalado"; fi

# Credencial
if [ -s "$BASE/credencial" ]; then
  PERM="$(stat -f '%Lp' "$BASE/credencial")"
  if [ "$PERM" = "600" ]; then ok "Credencial guardada y protegida"; else aviso "La credencial tiene permisos $PERM (debería ser 600)"; fi
else
  mal "No hay credencial de Claude (vuelve a ejecutar el instalador)"
fi

# Configuración y carpeta
if [ -f "$BASE/config" ]; then
  # shellcheck source=/dev/null
  . "$BASE/config"
  if [ -d "${CARPETA_TRABAJO:-/nonexistent}" ]; then ok "Carpeta de trabajo: $CARPETA_TRABAJO"; else mal "No existe la carpeta de trabajo ${CARPETA_TRABAJO:-}"; fi
  ok "Permisos: ${MODO_PERMISOS:-?} · ${HERRAMIENTAS_PERMITIDAS:-?}"
else
  mal "Falta la configuración ($BASE/config)"
fi
[ -x "$BASE/remoto.sh" ] || mal "Falta $BASE/remoto.sh"
[ -f "$BASE/PAUSADO" ] && aviso "El acceso remoto está PAUSADO (~/.claude-remoto/acceso.sh reanudar)"

# Reposo
SLEEP_AC="$(pmset -g custom 2>/dev/null | awk '/AC Power/{f=1} f&&$1=="sleep"{print $2; exit}')"
if [ -n "$SLEEP_AC" ] && [ "$SLEEP_AC" != "0" ]; then
  aviso "Con el cargador puesto el Mac entra en reposo a los $SLEEP_AC min: mientras duerma no recibirá tareas"
fi

# Prueba real, por el mismo camino que usará Cris
if [ -z "$RAPIDO" ] && [ "$N_FALLO" -eq 0 ]; then
  printf '  … Probando una tarea real con Claude (unos segundos)\n'
  SALIDA="$(printf 'Responde únicamente con la palabra LISTO, sin nada más.' | "$BASE/remoto.sh" tarea 2>&1)"
  if printf '%s' "$SALIDA" | grep -q 'LISTO'; then
    ok "Claude ha respondido a una tarea de prueba"
  else
    mal "Claude no respondió bien a la tarea de prueba:"
    printf '%s\n' "$SALIDA" | head -5 | sed 's/^/      /'
  fi
fi

echo
if [ "$N_FALLO" -eq 0 ]; then
  printf '  \033[1;32mTodo listo.\033[0m %s correcto, %s avisos.\n\n' "$N_OK" "$N_AVISO"
  echo "  Envía a Cris esta línea:"
  echo
  printf '    \033[1mcliente alta %s %s@%s\033[0m\n\n' "$(printf '%s' "${DNS%%.*}" | sed 's/^claude-//')" "$(whoami)" "${DNS%%.*}"
  exit 0
else
  printf '  \033[1;31mHay %s problema(s).\033[0m Corrige lo marcado con ✗ o envía esta pantalla a Cris.\n\n' "$N_FALLO"
  exit 1
fi
