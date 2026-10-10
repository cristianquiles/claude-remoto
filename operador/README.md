# Lado del operador (Cris)

## 1. Desplegar el buzón (una sola vez)

El buzón es un Cloudflare Worker con una base D1. Cabe en el plan gratuito: cada equipo conectado hace unas 4.000 peticiones al día y el límite gratuito es de 100.000.

```bash
npx wrangler login
```

```bash
worker/desplegar.sh
```

El script crea la base `claude-remoto`, aplica el esquema y despliega el Worker. También genera el token de administrador y lo guarda con la URL en `~/.config/claude-remoto/` (`url`, `admin_token`, permisos 600). Para actualizar el Worker, vuelve a ejecutarlo.

## 2. Instalar el comando `cliente`

```bash
mkdir -p ~/.local/bin && ln -sf "$PWD/operador/cliente" ~/.local/bin/cliente
```

Requiere `curl` y `jq`.

## 3. Dar de alta un cliente

```bash
cliente alta zerca
```

Muestra las instrucciones que hay que enviar al cliente: la línea de instalación y el **código de conexión** (`CR1.…`). Envía el código por un canal distinto al de la línea de instalación.

## 4. Uso

```bash
cliente lista                            # equipos, en línea o no, pausados
cliente zerca ping                       # estado, versión de Claude, carpeta y permisos
cliente zerca comprobar                  # comprobación completa en su equipo
cliente zerca "Revisa brief.md y prepara 3 copys para Meta en copys.md"
cliente zerca -c "Hazlos más cortos"     # continúa la misma conversación
cat brief.md | cliente zerca             # la tarea por la entrada estándar
cliente resultado <id>                   # si cortaste la espera
cliente baja zerca                       # revoca el acceso; su agente se detiene solo
```

Desde tu Claude Code basta con pedir «manda esto al Claude de Zerca»: ejecutará `cliente zerca "…"` y te traerá la respuesta.

| Código de salida | Significado |
|---|---|
| 0 | Hecha |
| 1 | Error (en la tarea o en el buzón) |
| 3 | El cliente ha **pausado** el acceso |

## Qué puede hacer el Claude del cliente

Cada tarea se ejecuta con `claude -p --restricted --strict-mcp-config`:

- Solo las herramientas de `HerramientasPermitidas` en su `config.json`. Por defecto: `Read,Glob,Grep,Edit,Write,WebSearch,WebFetch`.
- Ignora sus ajustes, permisos guardados y conectores MCP.
- Solo trabaja dentro de su carpeta de trabajo.
- Límite de 2 horas por tarea.

Si un cliente quiere que su Claude ejecute comandos concretos, puede añadir, por ejemplo, `PowerShell` o `Bash(git *)` a esa lista. Es decisión suya.

## Seguridad

- **Token de administrador:** solo vive en tu Mac y como secreto del Worker. Si se filtra, bórralo de `~/.config/claude-remoto/admin_token` y vuelve a ejecutar `desplegar.sh`.
- **Tokens de equipo:** se guardan solo como hash SHA-256 en D1. Un token filtrado únicamente permite recoger tareas de ese equipo; se revoca con `cliente baja`.
- **Datos en tránsito:** el buzón guarda las tareas y los resultados como mucho 7 días; un cron diario los borra.
