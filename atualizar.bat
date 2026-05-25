@echo off
REM Atualiza o Dashboard de Automacoes na area de trabalho
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0generate.ps1"
if %ERRORLEVEL% NEQ 0 (
  echo.
  echo Erro ao gerar dashboard. Codigo: %ERRORLEVEL%
  pause
  exit /b %ERRORLEVEL%
)
REM Abre o dashboard no navegador padrao
start "" "%USERPROFILE%\Desktop\Dashboard Automacoes.html"
