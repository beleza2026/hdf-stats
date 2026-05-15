@echo off
setlocal
cd /d "%~dp0"
if not exist dart_defines.json (
  echo Falta dart_defines.json. Copia dart_defines.example.json y pega tu token.
  exit /b 1
)
flutter run --dart-define-from-file=dart_defines.json %*
