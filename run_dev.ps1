# Ejecutá la app con Sportmonks sin repetir el token en cada comando.
# 1) Copiá dart_defines.example.json -> dart_defines.json
# 2) Pegá tu token en dart_defines.json (ese archivo no se sube a git)
# 3) Desde la raíz del proyecto: .\run_dev.ps1
#    Opcional: .\run_dev.ps1 --release   o   .\run_dev.ps1 -d windows

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path "dart_defines.json")) {
    Write-Host "Falta dart_defines.json en la raíz del proyecto." -ForegroundColor Yellow
    Write-Host "Copiá dart_defines.example.json a dart_defines.json y pegá tu SPORTMONKS_API_TOKEN." -ForegroundColor Yellow
    exit 1
}

flutter run --dart-define-from-file=dart_defines.json @args
