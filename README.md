# Claude remoto

Conecta tu Mac de forma privada para que Cris pueda encargar tareas a **tu** Claude: trabaja en tu equipo, con tu cuenta y solo en la carpeta que tú elijas.

## Instalación (5 minutos)

1. Abre la app **Terminal** (Cmd + Espacio, escribe «Terminal», Intro).
2. Copia esta línea, pégala y pulsa Intro:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cristianquiles/claude-remoto/main/instalar.sh)
```

3. Sigue las preguntas. Te hará falta:
   - la **contraseña de tu Mac** (te la pedirá 2 o 3 veces; al escribirla no se ve nada, es normal)
   - la **clave de conexión** que te ha enviado Cris (empieza por `tskey-`)
   - tu cuenta de **Claude Pro o Max** (se abre el navegador para autorizar) o una clave de API de Anthropic

Al terminar se hace una comprobación automática, con una tarea de prueba real. Si todo sale bien verás **Todo listo** y una línea que empieza por `cliente alta…`: **envíasela a Cris**.

## Qué se instala

| Pieza | Para qué |
|---|---|
| [Homebrew](https://brew.sh) | Instalador de programas estándar en Mac (si no lo tenías) |
| [Tailscale](https://tailscale.com) | Conexión privada y cifrada entre tu Mac y el de Cris. No abre puertos a internet |
| [Claude Code](https://claude.com/claude-code) | El asistente de Anthropic, instalado con su instalador oficial |
| `~/.claude-remoto/` | La configuración, tu credencial (solo legible por tu usuario) y el registro de tareas |

## Tú tienes el control

```bash
~/.claude-remoto/acceso.sh pausar      # bloquea las tareas remotas
~/.claude-remoto/acceso.sh reanudar    # las vuelve a permitir
~/.claude-remoto/acceso.sh registro    # qué te ha pedido Cris y cuándo
~/.claude-remoto/comprobar.sh          # vuelve a comprobar que todo funciona
```

- **Carpeta y permisos:** en `~/.claude-remoto/config` decides en qué carpeta trabaja Claude y qué herramientas puede usar. Por defecto puede leer y editar archivos de esa carpeta y buscar en internet. **No** puede ejecutar comandos de terminal salvo que tú los añadas.
- **Gasto:** las tareas consumen de tu cuenta de Claude, igual que si las escribieras tú.
- **Para que reciba tareas** el Mac tiene que estar encendido y sin dormir.

> **Transparencia:** la conexión de Tailscale da a Cris acceso a una terminal con tu usuario. La carpeta, los permisos, la pausa y el registro controlan lo que hace Claude, pero técnicamente no impiden ese acceso. Si quieres una separación total, crea en Ajustes del Sistema un usuario de macOS solo para esto («Claude Remoto») y ejecuta el instalador desde esa cuenta.

## Desinstalar

```bash
~/.claude-remoto/desinstalar.sh
```

Desconecta el Mac, borra la credencial y (si quieres) Tailscale. No toca tu carpeta de trabajo ni tu Claude Code.

## Problemas frecuentes

| Mensaje | Qué hacer |
|---|---|
| «Ya tienes la app de Tailscale instalada» | Avisa a Cris: hay que decidir si se desinstala la app |
| «La clave puede haber caducado» | Pide a Cris una clave nueva (duran 1 día) |
| «Claude no respondió bien a la tarea de prueba» | Vuelve a ejecutar el instalador y, en el paso 5, responde «n» para guardar una credencial nueva |
| Aviso de reposo | Ajustes del Sistema → Batería → Opciones → «Evitar reposo automático con el adaptador de corriente» |
