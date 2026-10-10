# Claude remoto: deshace la instalación. No toca la carpeta de trabajo ni Claude Code.
$Base = if ($env:CLAUDE_REMOTO_BASE) { $env:CLAUDE_REMOTO_BASE } else { Join-Path $env:USERPROFILE '.claude-remoto' }

$r = Read-Host 'Esto desconecta este equipo de Cris y borra la credencial guardada. ¿Continuar? (s/n)'
if ($r -ne 's') { 'Cancelado.'; exit 0 }

Stop-ScheduledTask -TaskName 'Claude remoto' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Claude remoto' -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*claude-remoto*agente.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

try {
    $cfg = Get-Content -Raw -Encoding UTF8 (Join-Path $Base 'config.json') | ConvertFrom-Json
    "Tu carpeta de trabajo ($($cfg.CarpetaTrabajo)) no se ha tocado."
} catch {}
Remove-Item -Recurse -Force $Base -ErrorAction SilentlyContinue
'Listo. Claude Code sigue instalado para tu uso normal.'
