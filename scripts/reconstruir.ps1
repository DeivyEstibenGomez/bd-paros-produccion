# Reconstruye bd_paros desde cero en Windows (PowerShell).
# Uso:  .\scripts\reconstruir.ps1            (usuario postgres)
#       .\scripts\reconstruir.ps1 -Usuario miusuario
# Requiere que psql.exe esté en el PATH (C:\Program Files\PostgreSQL\16\bin).
param([string]$Usuario = "postgres", [string]$Servidor = "localhost")
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$env:PGCLIENTENCODING = "UTF8"
psql -X -h $Servidor -U $Usuario -d postgres -f sql/ejecutar_todo.sql
if ($LASTEXITCODE -ne 0) { throw "Falló la reconstrucción" }
if (Test-Path "privado/identidades.sql") {
    psql -X -q -h $Servidor -U $Usuario -d bd_paros -f privado/identidades.sql
    Write-Host "Identidades cargadas en privado.persona_identidad"
}
