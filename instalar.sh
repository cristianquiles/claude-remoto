#!/bin/bash
# Claude remoto — instalador para el Mac del cliente.
# Uso:  bash <(curl -fsSL https://raw.githubusercontent.com/cristianquiles/claude-remoto/main/instalar.sh)
set -euo pipefail

REPO="${CLAUDE_REMOTO_REPO:-cristianquiles/claude-remoto}"
RAMA="${CLAUDE_REMOTO_RAMA:-main}"
BASE="${CLAUDE_REMOTO_BASE:-$HOME/.claude-remoto}"
ARCHIVOS="remoto.sh comprobar.sh acceso.sh desinstalar.sh"

paso()  { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
fallo() { printf '\n  \033[31m✗ %s\033[0m\n\n' "$*"; exit 1; }
preguntar() { # preguntar VAR "texto" [defecto]
  local _r
  read -r -p "  $2${3:+ [$3]}: " _r </dev/tty || true
  printf -v "$1" '%s' "${_r:-${3:-}}"
}
preguntar_oculto() {
  local _r
  read -r -s -p "  $2: " _r </dev/tty || true
  echo
  printf -v "$1" '%s' "$_r"
}

cat <<'EOF'

  ┌──────────────────────────────────────────────┐
  │  Claude remoto · instalación                 │
  │  Conecta este Mac de forma privada para que  │
  │  Cris pueda encargar tareas a tu Claude.     │
  └──────────────────────────────────────────────┘

  Necesitarás:
   · la contraseña de este Mac (se pide 2-3 veces)
   · la clave de conexión que te ha enviado Cris
   · tu cuenta de Claude (Pro/Max) o una clave de API de Anthropic
EOF

# ---------------------------------------------------------------- 1
paso "1/6 Comprobando el equipo"
[ "$(uname)" = "Darwin" ] || fallo "Este instalador es solo para macOS."
if [ -d /Applications/Tailscale.app ]; then
  fallo "Ya tienes la app de Tailscale instalada. Esta instalación usa la versión de
    Homebrew (la única que permite la conexión SSH de Tailscale) y las dos no pueden
    convivir. Habla con Cris antes de seguir."
fi
ok "macOS $(sw_vers -productVersion)"

# ---------------------------------------------------------------- 2
paso "2/6 Homebrew"
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [ -x "$b" ]; then eval "$("$b" shellenv)"; break; fi
done
if ! command -v brew >/dev/null 2>&1; then
  info "Instalando Homebrew (te pedirá la contraseña del Mac)…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; break; fi
  done
  command -v brew >/dev/null 2>&1 || fallo "No se pudo instalar Homebrew."
fi
ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"

# ---------------------------------------------------------------- 3
paso "3/6 Tailscale (conexión privada y cifrada con Cris)"
brew list tailscale >/dev/null 2>&1 || brew install tailscale
TS="$(brew --prefix)/bin/tailscale"
info "Arrancando el servicio (te pedirá la contraseña del Mac)…"
sudo "$(brew --prefix)/bin/brew" services start tailscale >/dev/null 2>&1 \
  || sudo "$(brew --prefix)/bin/brew" services restart tailscale >/dev/null

estado_ts() { "$TS" status --json 2>/dev/null | grep -o '"BackendState": *"[A-Za-z]*"' | head -1 | sed 's/.*"\([A-Za-z]*\)"$/\1/'; }
for _ in $(seq 1 20); do [ -n "$(estado_ts)" ] && break; sleep 1; done
[ -n "$(estado_ts)" ] || fallo "El servicio de Tailscale no responde. Reinicia el Mac y vuelve a ejecutar el instalador."

if [ "$(estado_ts)" = "Running" ]; then
  ok "Ya estaba conectado"
  sudo "$TS" set --ssh
else
  preguntar NOMBRE "Nombre corto para este equipo (p. ej. tu empresa)" "$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
  NOMBRE="claude-$(printf '%s' "$NOMBRE" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
  preguntar_oculto CLAVE_TS "Pega la clave de conexión que te ha enviado Cris (no se verá al escribir)"
  case "$CLAVE_TS" in tskey-*) ;; *) fallo "Esa clave no parece válida (debe empezar por tskey-)." ;; esac
  sudo "$TS" up --ssh --authkey="$CLAVE_TS" --hostname="$NOMBRE" >/dev/null \
    || fallo "No se pudo conectar. La clave puede haber caducado: pide otra a Cris."
  unset CLAVE_TS
fi
[ "$(estado_ts)" = "Running" ] || fallo "Tailscale no ha quedado conectado."
ok "Conectado como $("$TS" status --json | grep -o '"DNSName": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/' | sed 's/\.$//')"

# ---------------------------------------------------------------- 4
paso "4/6 Claude Code"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v claude >/dev/null 2>&1; then
  info "Instalando Claude Code (instalador oficial de Anthropic)…"
  curl -fsSL https://claude.ai/install.sh | bash
fi
CLAUDE="$(command -v claude || true)"
[ -n "$CLAUDE" ] || fallo "No se pudo instalar Claude Code."
ok "Claude Code $("$CLAUDE" --version 2>/dev/null | awk '{print $1}')"

# ---------------------------------------------------------------- 5
paso "5/6 Credencial de Claude para uso remoto"
mkdir -p "$BASE"; chmod 700 "$BASE"
USAR_ACTUAL=""
if [ -s "$BASE/credencial" ]; then
  preguntar USAR_ACTUAL "Ya hay una credencial guardada. ¿Mantenerla? (s/n)" "s"
fi
if [ "$USAR_ACTUAL" != "s" ]; then
  cat <<'EOF'
  Las tareas remotas necesitan una credencial propia de Claude.
   A) Tengo suscripción Claude Pro o Max  → se abrirá el navegador para autorizar
                                            y al final verás un código sk-ant-oat…
   B) Tengo una clave de API de Anthropic → empieza por sk-ant-api…
EOF
  preguntar OPCION "Elige A o B" "A"
  if [ "$(printf '%s' "$OPCION" | tr '[:lower:]' '[:upper:]')" = "A" ]; then
    "$CLAUDE" setup-token </dev/tty || true
    info "Copia el código que empieza por sk-ant-oat (el de arriba)."
  fi
  preguntar_oculto CRED "Pega aquí la credencial (no se verá al escribir)"
  CRED="$(printf '%s' "$CRED" | tr -d '[:space:]')"
  case "$CRED" in sk-ant-*) ;; *) fallo "Eso no parece una credencial de Claude (debe empezar por sk-ant-)." ;; esac
  ( umask 077; printf '%s' "$CRED" > "$BASE/credencial" )
  unset CRED
fi
chmod 600 "$BASE/credencial"
ok "Credencial guardada en $BASE/credencial (solo legible por tu usuario)"

# ---------------------------------------------------------------- 6
paso "6/6 Carpeta de trabajo y permisos"
if [ ! -f "$BASE/config" ]; then
  preguntar CARPETA "Carpeta en la que Claude podrá trabajar" "$HOME/ClaudeRemoto"
  CARPETA="${CARPETA/#\~/$HOME}"
  cat > "$BASE/config" <<EOF
# Configuración de Claude remoto. Puedes editarla cuando quieras.

# Carpeta en la que trabajan las tareas remotas.
CARPETA_TRABAJO="$CARPETA"

# Herramientas que Claude puede usar sin preguntar. Separadas por comas.
# Para permitir comandos de terminal concretos añade, por ejemplo: Bash(git *)
HERRAMIENTAS_PERMITIDAS="Read,Glob,Grep,Edit,Write,WebSearch,WebFetch"

# acceptEdits = puede crear y editar archivos de la carpeta; lo demás, solo lo permitido arriba.
MODO_PERMISOS="acceptEdits"
EOF
fi
# shellcheck source=/dev/null
. "$BASE/config"
mkdir -p "$CARPETA_TRABAJO"
ok "Carpeta de trabajo: $CARPETA_TRABAJO"

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$ORIGEN" ] && [ -f "$ORIGEN/remoto.sh" ]; then
  for f in $ARCHIVOS; do cp "$ORIGEN/$f" "$BASE/$f"; done
else
  TMP="$(mktemp -d)"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$RAMA.tar.gz" | tar -xz -C "$TMP" --strip-components 1
  for f in $ARCHIVOS; do cp "$TMP/$f" "$BASE/$f"; done
  rm -rf "$TMP"
fi
for f in $ARCHIVOS; do chmod 700 "$BASE/$f"; done
ok "Programas instalados en $BASE"

paso "Comprobación final"
exec "$BASE/comprobar.sh"
