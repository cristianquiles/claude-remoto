# Claude remoto: control del acceso por parte del usuario de este equipo.
#   acceso.ps1 pausar      las tareas de Cris se rechazan
#   acceso.ps1 reanudar    se vuelven a aceptar
#   acceso.ps1 registro    últimas tareas recibidas
#   acceso.ps1 estado
param([string]$Accion = 'estado', [int]$Lineas = 30)

$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$Base = if ($env:CLAUDE_REMOTO_BASE) { $env:CLAUDE_REMOTO_BASE } else { Join-Path $env:USERPROFILE '.claude-remoto' }
$Pausa = Join-Path $Base 'PAUSADO'
$Log = Join-Path $Base 'registro.log'

switch ($Accion) {
    'pausar'   { New-Item -ItemType File -Force -Path $Pausa | Out-Null; 'Acceso remoto pausado. Las tareas de Cris serán rechazadas (tarda unos segundos en aplicarse).' }
    'reanudar' { Remove-Item -Force -ErrorAction SilentlyContinue $Pausa; 'Acceso remoto reanudado.' }
    'registro' { if (Test-Path $Log) { Get-Content -Encoding UTF8 -Tail $Lineas $Log } else { 'Aún no se ha recibido ninguna tarea.' } }
    'estado'   { if (Test-Path $Pausa) { 'Acceso remoto: PAUSADO' } else { 'Acceso remoto: activo' } }
    default    { 'Uso: acceso.ps1 pausar | reanudar | registro | estado'; exit 2 }
}
