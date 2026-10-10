#!/bin/bash
# Despliega (o actualiza) el buzón en tu cuenta de Cloudflare. Se puede repetir sin riesgo.
# Requisito previo, una sola vez:  npx wrangler login
set -euo pipefail
cd "$(dirname "$0")"

W=(npx --yes wrangler@4.149.0)
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/claude-remoto"
LOCAL=wrangler.local.jsonc   # copia con el ID real de la base de datos (no se sube al repo)

mkdir -p "$CONF"; chmod 700 "$CONF"
"${W[@]}" whoami 2>&1 | grep -qi 'logged in' || { echo "Primero inicia sesión: npx wrangler login" >&2; exit 1; }

echo "▶ Base de datos D1"
id_d1() { "${W[@]}" d1 list --json 2>/dev/null | jq -r '.[] | select(.name=="claude-remoto") | .uuid'; }
ID="$(id_d1)"
if [ -z "$ID" ]; then "${W[@]}" d1 create claude-remoto >/dev/null; ID="$(id_d1)"; fi
[ -n "$ID" ] || { echo "No se pudo crear la base de datos" >&2; exit 1; }
sed "s/\"database_id\": \"[^\"]*\"/\"database_id\": \"$ID\"/" wrangler.jsonc > "$LOCAL"
"${W[@]}" d1 execute claude-remoto --remote --file schema.sql -c "$LOCAL" >/dev/null
echo "  $ID"

echo "▶ Worker"
SALIDA="$("${W[@]}" deploy -c "$LOCAL" 2>&1)" || { echo "$SALIDA" >&2; exit 1; }
URL="$(printf '%s' "$SALIDA" | grep -o 'https://[a-zA-Z0-9.-]*workers\.dev' | head -1)"
[ -n "$URL" ] || { echo "$SALIDA" >&2; echo "No encuentro la URL del Worker en la salida" >&2; exit 1; }
printf '%s' "$URL" > "$CONF/url"
echo "  $URL"

echo "▶ Token de administrador"
if [ ! -s "$CONF/admin_token" ]; then
  ( umask 077; openssl rand -base64 48 | tr -d '\n/+=' > "$CONF/admin_token" )
fi
chmod 600 "$CONF/admin_token"
"${W[@]}" secret put ADMIN_TOKEN -c "$LOCAL" < "$CONF/admin_token" >/dev/null
echo "  guardado en $CONF/admin_token"

echo "▶ Comprobación"
sleep 5
[ "$(curl -s "$URL/")" = "claude-remoto" ] || { echo "El Worker no responde en $URL" >&2; exit 1; }
CODIGO="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat "$CONF/admin_token")" "$URL/admin/equipos")"
[ "$CODIGO" = 200 ] || { echo "El token de administrador no funciona (HTTP $CODIGO)" >&2; exit 1; }
echo "  OK: buzón operativo. Ya puedes usar: cliente alta <nombre>"
