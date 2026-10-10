# Claude remoto: agente que recoge las tareas del buzón y las ejecuta con Claude Code.
# Lo arranca la tarea programada "Claude remoto" al iniciar sesión. Una sola instancia a la vez.
#   agente.ps1           bucle normal
#   agente.ps1 -UnaVez   atiende como mucho una tarea y sale (para pruebas)
param([switch]$UnaVez)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Base = if ($env:CLAUDE_REMOTO_BASE) { $env:CLAUDE_REMOTO_BASE } else { Join-Path $env:USERPROFILE '.claude-remoto' }
$Version = '1'
$TimeoutTareaMin = 120

function Registrar([string]$tipo, [string]$texto) {
    $t = $texto -replace '[\r\n\t]+', ' '
    if ($t.Length -gt 500) { $t = $t.Substring(0, 500) }
    $linea = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`t" + $tipo + "`t" + $t + "`r`n"
    [IO.File]::AppendAllText((Join-Path $Base 'registro.log'), $linea, $Utf8)
}

function Leer-Config {
    $c = [IO.File]::ReadAllText((Join-Path $Base 'config.json'), $Utf8) | ConvertFrom-Json
    $c | Add-Member -NotePropertyName Token -NotePropertyValue ([IO.File]::ReadAllText((Join-Path $Base 'token'), $Utf8).Trim()) -Force
    return $c
}

function Buscar-Claude {
    $candidatos = @((Join-Path $HOME '.local/bin/claude'))
    if ($env:USERPROFILE) { $candidatos = @((Join-Path $env:USERPROFILE '.local\bin\claude.exe')) + $candidatos }
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { $candidatos = @($cmd.Source) + $candidatos }
    foreach ($c in $candidatos) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Cargar-Credencial {
    $f = Join-Path $Base 'credencial'
    if (Test-Path $f) {
        $cred = [IO.File]::ReadAllText($f, $Utf8).Trim()
        if ($cred.StartsWith('sk-ant-api')) { $env:ANTHROPIC_API_KEY = $cred } else { $env:CLAUDE_CODE_OAUTH_TOKEN = $cred }
    }
}

function Comillas([string]$s) { '"' + ($s -replace '"', '\"') + '"' }

function Ejecutar-Claude($cfg, [string]$modo, [string]$prompt) {
    $claude = Buscar-Claude
    if (-not $claude) { return @{ ok = $false; texto = 'Claude Code no está instalado en este equipo.' } }
    if (-not (Test-Path $cfg.CarpetaTrabajo)) { return @{ ok = $false; texto = "No existe la carpeta de trabajo $($cfg.CarpetaTrabajo)." } }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('claude-remoto-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $fin = Join-Path $tmp 'entrada.txt'; $fout = Join-Path $tmp 'salida.txt'; $ferr = Join-Path $tmp 'errores.txt'
    [IO.File]::WriteAllText($fin, $prompt, $Utf8)

    # --restricted: ignora los ajustes y MCP del usuario, quita las herramientas que ejecutan código
    # salvo las nombradas en --tools y limita los archivos a la carpeta de trabajo.
    $herramientas = (($cfg.HerramientasPermitidas -split ',') | ForEach-Object { ($_ -replace '\(.*$', '').Trim() } | Where-Object { $_ } | Select-Object -Unique) -join ','
    $argumentos = @('-p', '--restricted', '--strict-mcp-config')
    if ($modo -eq 'continuar') { $argumentos += '--continue' }
    $argumentos += @('--tools', (Comillas $herramientas), '--allowedTools', (Comillas $cfg.HerramientasPermitidas), '--permission-mode', (Comillas $cfg.ModoPermisos))
    try {
        $p = Start-Process -FilePath $claude -ArgumentList ($argumentos -join ' ') -WorkingDirectory $cfg.CarpetaTrabajo `
            -RedirectStandardInput $fin -RedirectStandardOutput $fout -RedirectStandardError $ferr `
            -NoNewWindow -PassThru
        if (-not $p.WaitForExit($TimeoutTareaMin * 60 * 1000)) {
            try { $p.Kill() } catch {}
            return @{ ok = $false; texto = "La tarea superó el límite de $TimeoutTareaMin minutos y se ha detenido." }
        }
        $p.WaitForExit()
        $salida = if (Test-Path $fout) { [IO.File]::ReadAllText($fout, $Utf8) } else { '' }
        $errores = if (Test-Path $ferr) { [IO.File]::ReadAllText($ferr, $Utf8) } else { '' }
        if ($p.ExitCode -eq 0) { return @{ ok = $true; texto = $salida.TrimEnd() } }
        return @{ ok = $false; texto = ("Claude terminó con código $($p.ExitCode).`n" + $salida + "`n" + $errores).Trim() }
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

function Enviar-Resultado($cfg, [string]$id, [bool]$ok, [string]$texto) {
    $estado = 'error'; if ($ok) { $estado = 'hecha' }
    $cuerpo = @{ id = $id; estado = $estado; resultado = $texto } | ConvertTo-Json -Compress
    for ($i = 0; $i -lt 5; $i++) {
        try {
            Invoke-RestMethod -Method Post -Uri "$($cfg.Url)/agente/resultado" -Headers @{ Authorization = "Bearer $($cfg.Token)" } `
                -ContentType 'application/json; charset=utf-8' -Body $Utf8.GetBytes($cuerpo) -TimeoutSec 30 | Out-Null
            return
        } catch { Start-Sleep -Seconds (5 * ($i + 1)) }
    }
    Registrar 'error' "No se pudo enviar el resultado de la tarea $id"
}

# Una sola instancia
$mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeRemotoAgente')
if (-not $mutex.WaitOne(0)) { exit 0 }

try {
    Registrar 'inicio' "Agente iniciado (versión $Version)"
    $versionClaude = ''
    $c = Buscar-Claude
    if ($c) { try { $versionClaude = ($null | & $c --version 2>$null | Out-String).Trim() } catch {} }

    while ($true) {
        try { $cfg = Leer-Config } catch { Start-Sleep -Seconds 30; continue }
        Cargar-Credencial
        $pausado = Test-Path (Join-Path $Base 'PAUSADO')
        $estado = 'activo'; if ($pausado) { $estado = 'pausado' }
        $info = @{ agente = $Version; claude = $versionClaude; carpeta = $cfg.CarpetaTrabajo; permisos = "$($cfg.ModoPermisos) · $($cfg.HerramientasPermitidas)"; equipo = $env:COMPUTERNAME } | ConvertTo-Json -Compress
        $info = [Convert]::ToBase64String($Utf8.GetBytes($info))   # las cabeceras HTTP solo admiten ASCII
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri "$($cfg.Url)/agente/siguiente" -TimeoutSec 45 `
                -Headers @{ Authorization = "Bearer $($cfg.Token)"; 'X-Estado' = $estado; 'X-Info' = $info }
        } catch {
            $codigo = $null
            try { $codigo = [int]$_.Exception.Response.StatusCode } catch {}
            if ($codigo -eq 401) {
                Registrar 'error' 'Token rechazado: el equipo se ha dado de baja. El agente se detiene.'
                try { Disable-ScheduledTask -TaskName 'Claude remoto' -ErrorAction Stop | Out-Null } catch {}
                break
            }
            Start-Sleep -Seconds 15
            if ($UnaVez) { break }
            continue
        }
        if ($r.StatusCode -eq 204) {
            if ($pausado) { Start-Sleep -Seconds 20 }
            if ($UnaVez) { break }
            continue
        }

        $bytes = $r.RawContentStream.ToArray()
        $t = $Utf8.GetString($bytes) | ConvertFrom-Json
        Registrar $t.modo $t.prompt
        if ($t.modo -eq 'comprobar') {
            $informe = & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Base 'comprobar.ps1') -SinPrueba 2>&1 | Out-String
            Enviar-Resultado $cfg $t.id $true $informe.Trim()
        } else {
            $res = Ejecutar-Claude $cfg $t.modo $t.prompt
            Enviar-Resultado $cfg $t.id $res.ok $res.texto
            Registrar 'fin' ("{0} · {1} caracteres" -f $(if ($res.ok) { 'hecha' } else { 'error' }), $res.texto.Length)
        }
        if ($UnaVez) { break }
    }
} finally {
    $mutex.ReleaseMutex()
}
