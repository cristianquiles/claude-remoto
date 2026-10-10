# Claude remoto: instalador para Windows. No necesita permisos de administrador.
# Uso (PowerShell):
#   irm https://raw.githubusercontent.com/cristianquiles/claude-remoto/main/windows/instalar.ps1 | iex

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$Utf8 = New-Object System.Text.UTF8Encoding $false

$Repo  = if ($env:CLAUDE_REMOTO_REPO) { $env:CLAUDE_REMOTO_REPO } else { 'cristianquiles/claude-remoto' }
$Rama  = if ($env:CLAUDE_REMOTO_RAMA) { $env:CLAUDE_REMOTO_RAMA } else { 'main' }
$Base  = if ($env:CLAUDE_REMOTO_BASE) { $env:CLAUDE_REMOTO_BASE } else { Join-Path $env:USERPROFILE '.claude-remoto' }
$Archivos = @('agente.ps1', 'comprobar.ps1', 'acceso.ps1', 'desinstalar.ps1')
$NombreTarea = 'Claude remoto'

function Paso([string]$t)  { Write-Host ''; Write-Host "> $t" -ForegroundColor Cyan }
function Ok([string]$t)    { Write-Host "  [OK] $t" -ForegroundColor Green }
function Info([string]$t)  { Write-Host "  $t" }
function Fallo([string]$t) { Write-Host ''; Write-Host "  [FALLO] $t" -ForegroundColor Red; Write-Host ''; throw 'Instalación interrumpida.' }
function Leer-Oculto([string]$t) {
    $s = Read-Host "  $t" -AsSecureString
    $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}
function Solo-Para-Mi([string]$ruta) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    icacls $ruta /inheritance:r /grant:r "*${sid}:(OI)(CI)F" /grant:r '*S-1-5-18:(OI)(CI)F' | Out-Null
}

Write-Host @'

  +------------------------------------------------+
  |  Claude remoto - instalación                   |
  |  Permite que Cris encargue tareas a tu Claude, |
  |  que trabaja en tu equipo y con tu cuenta.     |
  +------------------------------------------------+

  Necesitarás:
   - el código de conexión que te ha enviado Cris (empieza por CR1.)
   - tu cuenta de Claude Pro o Max, o una clave de API de Anthropic
'@

# ------------------------------------------------------------------ 1
Paso '1/5 Código de conexión'
$codigo = (Leer-Oculto 'Pega el código de conexión (no se verá al escribir)').Trim()
if (-not $codigo.StartsWith('CR1.')) { Fallo 'Ese código no es válido (debe empezar por CR1.).' }
try {
    $b64 = $codigo.Substring(4).Replace('-', '+').Replace('_', '/')
    while ($b64.Length % 4) { $b64 += '=' }
    $partes = $Utf8.GetString([Convert]::FromBase64String($b64)).Split('|')
    $Url = $partes[0].TrimEnd('/'); $Token = $partes[1]
} catch { Fallo 'No se ha podido leer el código. Cópialo entero otra vez.' }
try {
    $hola = Invoke-RestMethod -Uri "$Url/agente/hola" -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 20
} catch { Fallo 'El código no funciona o ha caducado. Pide otro a Cris.' }
Ok "Este equipo se conectará como '$($hola.nombre)'"

# ------------------------------------------------------------------ 2
Paso '2/5 Claude Code'
$env:PATH = (Join-Path $env:USERPROFILE '.local\bin') + ';' + $env:PATH
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Info 'Instalando Claude Code (instalador oficial de Anthropic)...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex'
}
$Claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $Claude) { Fallo 'No se pudo instalar Claude Code.' }
Ok ("Claude Code " + (($null | & $Claude --version 2>$null | Out-String).Trim()))

# ------------------------------------------------------------------ 3
Paso '3/5 Credencial de Claude para las tareas remotas'
New-Item -ItemType Directory -Force -Path $Base | Out-Null
Solo-Para-Mi $Base
$fcred = Join-Path $Base 'credencial'
$mantener = 'n'
if (Test-Path $fcred) { $mantener = Read-Host '  Ya hay una credencial guardada. ¿Mantenerla? (s/n)' }
if ($mantener -ne 's') {
    Write-Host @'
  Las tareas remotas necesitan una credencial propia de Claude:
   A) Tengo Claude Pro o Max  -> se abrirá el navegador para autorizar
                                 y al final verás un código sk-ant-oat...
   B) Tengo una clave de API  -> empieza por sk-ant-api...
'@
    $op = Read-Host '  Elige A o B'
    if ($op -eq '' -or $op -match '^[Aa]') {
        & $Claude setup-token
        Info 'Copia el código que empieza por sk-ant-oat (el de arriba).'
    }
    $cred = (Leer-Oculto 'Pega aquí la credencial (no se verá al escribir)') -replace '\s', ''
    if (-not $cred.StartsWith('sk-ant-')) { Fallo 'Eso no parece una credencial de Claude (debe empezar por sk-ant-).' }
    [IO.File]::WriteAllText($fcred, $cred, $Utf8)
    Remove-Variable cred
}
Ok 'Credencial guardada (solo accesible para tu usuario)'

# ------------------------------------------------------------------ 4
Paso '4/5 Carpeta de trabajo y permisos'
$fcfg = Join-Path $Base 'config.json'
if (Test-Path $fcfg) {
    $cfg = [IO.File]::ReadAllText($fcfg, $Utf8) | ConvertFrom-Json
    $cfg.Url = $Url
} else {
    $defecto = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ClaudeRemoto'
    $carpeta = Read-Host "  Carpeta en la que Claude podrá trabajar [$defecto]"
    if (-not $carpeta) { $carpeta = $defecto }
    $cfg = [pscustomobject]@{
        Url                    = $Url
        CarpetaTrabajo         = $carpeta
        HerramientasPermitidas = 'Read,Glob,Grep,Edit,Write,WebSearch,WebFetch'
        ModoPermisos           = 'acceptEdits'
    }
}
[IO.File]::WriteAllText($fcfg, ($cfg | ConvertTo-Json), $Utf8)
[IO.File]::WriteAllText((Join-Path $Base 'token'), $Token, $Utf8)
New-Item -ItemType Directory -Force -Path $cfg.CarpetaTrabajo | Out-Null
Ok "Carpeta de trabajo: $($cfg.CarpetaTrabajo)"
Ok "Permisos: $($cfg.ModoPermisos) · $($cfg.HerramientasPermitidas)"

$origen = $PSScriptRoot
foreach ($f in $Archivos) {
    $destino = Join-Path $Base $f
    if ($origen -and (Test-Path (Join-Path $origen $f))) { Copy-Item -Force (Join-Path $origen $f) $destino }
    else { Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/$Repo/$Rama/windows/$f" -OutFile $destino }
}
Ok "Programas instalados en $Base"

# ------------------------------------------------------------------ 5
Paso '5/5 Agente en segundo plano'
Stop-ScheduledTask -TaskName $NombreTarea -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*claude-remoto*agente.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$accion = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Base 'agente.ps1'))
$ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$usuario = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Limited
# Al iniciar sesión + cada 5 min como red de seguridad (si ya está en marcha, no arranca otra copia)
$cadaCinco = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
try {
    $alEntrar = New-ScheduledTaskTrigger -AtLogOn -User $usuario
    Register-ScheduledTask -TaskName $NombreTarea -Action $accion -Trigger @($alEntrar, $cadaCinco) -Settings $ajustes -Principal $principal -Force | Out-Null
} catch {
    # Sin permisos de administrador Windows a veces no deja usar el disparador de inicio de sesión
    Register-ScheduledTask -TaskName $NombreTarea -Action $accion -Trigger $cadaCinco -Settings $ajustes -Principal $principal -Force | Out-Null
}
Start-ScheduledTask -TaskName $NombreTarea
Start-Sleep -Seconds 3
Ok 'Agente en marcha (se inicia solo al encender el equipo)'

Paso 'Comprobación final'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Base 'comprobar.ps1')
