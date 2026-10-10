# Claude remoto

Permite que Cris encargue tareas a **tu** Claude: trabaja en tu ordenador, con tu cuenta y solo en la carpeta que tú elijas.

## Instalación en Windows (5 minutos)

1. Abre **PowerShell**: tecla Windows, escribe «PowerShell» y pulsa Intro. No hace falta abrirlo como administrador.
2. Copia esta línea, pégala (clic derecho) y pulsa Intro:

```powershell
irm https://raw.githubusercontent.com/cristianquiles/claude-remoto/main/windows/instalar.ps1 | iex
```

3. Sigue las preguntas. Te hará falta:
   - el **código de conexión** que te ha enviado Cris (empieza por `CR1.`)
   - tu cuenta de **Claude Pro o Max** (se abre el navegador para autorizar) o una clave de API de Anthropic

Al terminar se hace una comprobación automática, con una tarea de prueba real. Si ves **Todo listo**, avisa a Cris.

## Cómo funciona

```
 Claude de Cris ──encarga──▶  buzón (Cloudflare)  ◀──recoge── agente en tu PC ──▶ tu Claude Code
                ◀─resultado─                      ──entrega─▶
```

- En tu PC corre un pequeño **agente** en segundo plano: se inicia solo al encender el equipo.
- El agente **pregunta** al buzón si hay tareas. Nadie se conecta a tu ordenador ni se abre ningún puerto.
- Cris **no tiene acceso a tu equipo**: solo puede dejar tareas en el buzón. Cada tarea la ejecuta tu Claude Code en modo restringido, sin ejecutar comandos y sin salir de la carpeta de trabajo.
- Las tareas y sus resultados se borran del buzón a los 7 días.

## Tú tienes el control

En PowerShell:

```powershell
& "$env:USERPROFILE\.claude-remoto\acceso.ps1" pausar      # rechaza las tareas de Cris
& "$env:USERPROFILE\.claude-remoto\acceso.ps1" reanudar    # las vuelve a aceptar
& "$env:USERPROFILE\.claude-remoto\acceso.ps1" registro    # qué te ha pedido Cris y cuándo
& "$env:USERPROFILE\.claude-remoto\comprobar.ps1"          # comprueba que todo funciona
```

- **Carpeta y permisos:** en `%USERPROFILE%\.claude-remoto\config.json` decides en qué carpeta trabaja Claude y qué herramientas puede usar. Por defecto puede leer y editar archivos de esa carpeta y buscar en internet. No puede ejecutar comandos, ni usar tus ajustes o conectores de Claude, ni tocar nada fuera de la carpeta.
- **Gasto:** las tareas consumen de tu cuenta de Claude, igual que si las escribieras tú.
- **Para recibir tareas**, el ordenador tiene que estar encendido, con la sesión iniciada y sin suspender.

## Desinstalar

```powershell
& "$env:USERPROFILE\.claude-remoto\desinstalar.ps1"
```

Detiene el agente y borra la credencial. Tu carpeta de trabajo y Claude Code no se tocan.

## Problemas frecuentes

| Mensaje | Qué hacer |
|---|---|
| «El código no funciona o ha caducado» | Pide a Cris un código nuevo |
| «Claude no respondió bien a la prueba» | Vuelve a ejecutar el instalador y, en el paso 3, responde «n» para guardar una credencial nueva |
| «El agente no está en marcha» | Ejecuta `Start-ScheduledTask 'Claude remoto'` o reinicia el ordenador |
| Aviso de suspensión | Configuración → Sistema → Inicio/apagado y batería → «Cuando esté enchufado, suspender después de: Nunca» |

---

¿Eres Cris? Mira [operador/README.md](operador/README.md).
