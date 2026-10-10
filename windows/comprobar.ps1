# Claude remoto: comprueba que todo está instalado y funcionando.
#   comprobar.ps1             comprobación completa (incluye una tarea de prueba con Claude)
#   comprobar.ps1 -SinPrueba  sin tarea de prueba
param([switch]$SinPrueba)

$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$OutputEncoding = $Utf8
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$Base = if ($env:CLAUDE_REMOTO_BASE) { $env:CLAUDE_REMOTO_BASE } else { Join-Path $env:USERPROFILE '.claude-remoto' }
$EsWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'

$script:nOk = 0; $script:nAviso = 0; $script:nFallo = 0
function Ok([string]$t)    { Write-Host "  [OK]    $t" -ForegroundColor Green;  $script:nOk++ }
function Aviso([string]$t) { Write-Host "  [AVISO] $t" -ForegroundColor Yellow; $script:nAviso++ }
function Mal([string]$t)   { Write-Host "  [FALLO] $t" -ForegroundColor Red;    $script:nFallo++ }

Write-Host ''
Write-Host '  Claude remoto - comprobación'
Write-Host '  ----------------------------'

if ($EsWindows) { Ok ("Windows " + [Environment]::OSVersion.Version) }

# Claude Code
$claude = $null
$cands = @((Join-Path $HOME '.local/bin/claude'))
if ($env:USERPROFILE) { $cands = @((Join-Path $env:USERPROFILE '.local\bin\claude.exe')) + $cands }
$cmd = Get-Command claude -ErrorAction SilentlyContinue
if ($cmd) { $cands = @($cmd.Source) + $cands }
foreach ($c in $cands) { if ($c -and (Test-Path $c)) { $claude = $c; break } }
if ($claude) { Ok ("Claude Code " + (($null | & $claude --version 2>$null | Out-String).Trim())) } else { Mal 'Claude Code no está instalado' }

# Credencial
$fcred = Join-Path $Base 'credencial'
if (Test-Path $fcred) {
    Ok 'Credencial de Claude guardada'
    $cred = [IO.File]::ReadAllText($fcred, $Utf8).Trim()
    if ($cred.StartsWith('sk-ant-api')) { $env:ANTHROPIC_API_KEY = $cred } else { $env:CLAUDE_CODE_OAUTH_TOKEN = $cred }
} else { Mal 'No hay credencial de Claude (vuelve a ejecutar el instalador)' }

# Configuración
$cfg = $null
try { $cfg = [IO.File]::ReadAllText((Join-Path $Base 'config.json'), $Utf8) | ConvertFrom-Json } catch { Mal 'Falta o está mal la configuración (config.json)' }
if ($cfg) {
    if (Test-Path $cfg.CarpetaTrabajo) { Ok "Carpeta de trabajo: $($cfg.CarpetaTrabajo)" } else { Mal "No existe la carpeta de trabajo $($cfg.CarpetaTrabajo)" }
    Ok "Permisos: $($cfg.ModoPermisos) · $($cfg.HerramientasPermitidas)"
}

# Conexión con el buzón
$nombre = $null
$ftoken = Join-Path $Base 'token'
if ($cfg -and (Test-Path $ftoken)) {
    $token = [IO.File]::ReadAllText($ftoken, $Utf8).Trim()
    try {
        $r = Invoke-RestMethod -Uri "$($cfg.Url)/agente/hola" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 20
        $nombre = $r.nombre
        Ok "Conectado al buzón como '$nombre'"
    } catch {
        $codigo = $null; try { $codigo = [int]$_.Exception.Response.StatusCode } catch {}
        if ($codigo -eq 401) { Mal 'El código de conexión ya no es válido (pide uno nuevo a Cris)' }
        else { Mal "No se puede contactar con el buzón ($($cfg.Url)): $($_.Exception.Message)" }
    }
} else { Mal 'Falta el código de conexión' }

# Agente en marcha
if ($EsWindows) {
    $tarea = Get-ScheduledTask -TaskName 'Claude remoto' -ErrorAction SilentlyContinue
    if (-not $tarea) { Mal 'No está registrada la tarea programada "Claude remoto"' }
    elseif ($tarea.State -eq 'Running') { Ok 'El agente está en marcha' }
    else { Mal "El agente no está en marcha (estado: $($tarea.State)). Ejecuta: Start-ScheduledTask 'Claude remoto'" }
}
if (Test-Path (Join-Path $Base 'PAUSADO')) { Aviso 'El acceso remoto está PAUSADO (acceso.ps1 reanudar)' }

# Reposo con el cargador
if ($EsWindows) {
    try {
        $q = powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Out-String
        $hex = [regex]::Matches($q, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value }
        if ($hex.Count -ge 2) {
            $ac = [Convert]::ToInt32($hex[$hex.Count - 2], 16)
            if ($ac -gt 0) { Aviso ("Con el cargador puesto el equipo entra en suspensión a los {0} min: mientras duerma no recibirá tareas" -f [int]($ac / 60)) }
        }
    } catch {}
}

# Prueba real con Claude
if (-not $SinPrueba -and $script:nFallo -eq 0) {
    Write-Host '  ...     Probando una tarea real con Claude (unos segundos)'
    try {
        Push-Location $cfg.CarpetaTrabajo
        $salida = ('Responde unicamente con la palabra LISTO, sin nada mas.' | & $claude -p 2>&1 | Out-String)
        Pop-Location
        if ($salida -match 'LISTO') { Ok 'Claude ha respondido a una tarea de prueba' }
        else { Mal ("Claude no respondió bien a la prueba: " + $salida.Trim().Split("`n")[0]) }
    } catch { Mal "Claude no respondió: $($_.Exception.Message)" }
}

Write-Host ''
if ($script:nFallo -eq 0) {
    Write-Host ("  Todo listo. {0} correcto, {1} avisos." -f $script:nOk, $script:nAviso) -ForegroundColor Green
    if ($nombre) { Write-Host "  Este equipo ya puede recibir tareas como '$nombre'. Avisa a Cris." }
    Write-Host ''
    exit 0
} else {
    Write-Host ("  Hay {0} problema(s). Corrige lo marcado como FALLO o envía esta pantalla a Cris." -f $script:nFallo) -ForegroundColor Red
    Write-Host ''
    exit 1
}
