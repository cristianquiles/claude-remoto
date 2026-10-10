# Lado del operador (Cris)

Cómo preparar Tailscale, dar de alta un cliente y mandarle tareas.

## 1. Política de acceso del tailnet (una sola vez)

Panel de Tailscale → **Access controls**. Hay que añadir tres cosas:

```jsonc
{
  // Solo los administradores pueden crear equipos con esta etiqueta
  "tagOwners": {
    "tag:cliente": ["autogroup:admin"]
  },

  "grants": [
    // TÚ puedes llegar a los equipos de clientes…
    { "src": ["TU_USUARIO@TU_DOMINIO"], "dst": ["tag:cliente"], "ip": ["*"] }
    // …y NO hay ninguna regla en sentido contrario: un cliente no ve tus equipos ni los de otros clientes
  ],

  "ssh": [
    {
      "action": "accept",
      "src":    ["TU_USUARIO@TU_DOMINIO"],
      "dst":    ["tag:cliente"],
      "users":  ["autogroup:nonroot"]
    }
  ]
}
```

> ⚠️ **Antes de dar de alta al primer cliente, revisa que no quede la regla por defecto `{"src": ["*"], "dst": ["*"]}`** (o `"acls": [{"action":"accept","src":["*"],"dst":["*:*"]}]`). Con ella, el portátil del cliente podría llegar a todos tus equipos. Sustitúyela por reglas explícitas para tus propios equipos.

## 2. Clave de conexión para cada cliente

Panel → **Settings → Keys → Generate auth key**:

- Reusable: **no** · Ephemeral: **no** · Pre-approved: **sí**
- Tags: **tag:cliente**
- Expiration: **1 día**

Envíasela por un canal distinto al del enlace de instalación (por ejemplo, el enlace por correo y la clave por WhatsApp).

Cuando el equipo aparezca en **Machines**, ábrelo y pulsa **Disable key expiry**. Si no, se desconecta a los 180 días.

## 3. Instalar el comando `cliente` en tu Mac

```bash
mkdir -p ~/.local/bin && ln -sf "$PWD/operador/cliente" ~/.local/bin/cliente
```

Tu Mac solo necesita estar en el tailnet (sirve la app normal de Tailscale) y tener `ssh`.

## 4. Uso

```bash
cliente alta zerca ana@claude-zerca      # la línea que te manda el cliente al terminar
cliente zerca ping                       # ¿encendido y activo?
cliente zerca comprobar                  # comprobación completa en su Mac
cliente zerca "Revisa brief.md y prepara 3 copys para Meta en copys.md"
cliente zerca -c "Hazlos más cortos"     # continúa la misma conversación
cat brief.md | cliente zerca             # la tarea por la entrada estándar
cliente lista
```

Los equipos registrados se guardan en `~/.config/claude-remoto/equipos`.

Desde tu Claude Code basta con pedirle «manda esto al Claude de Zerca»: ejecutará `cliente zerca "…"` y te traerá la respuesta.

## Códigos de salida de una tarea

| Código | Significado |
|---|---|
| 0 | Correcto |
| 2 | Error de uso o de instalación en el cliente |
| 3 | El cliente ha **pausado** el acceso |
| 255 | Sin conexión SSH (equipo apagado, dormido o fuera del tailnet) |
