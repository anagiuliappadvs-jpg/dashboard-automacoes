@echo off
REM Atualiza o Dashboard de Automacoes (publica o snapshot pro site)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0generate.ps1"
if %ERRORLEVEL% NEQ 0 (
  echo.
  echo Erro ao gerar dashboard. Codigo: %ERRORLEVEL%
  pause
  exit /b %ERRORLEVEL%
)
REM Abre o site do dashboard no navegador padrao
start "" "https://automacoes.paccolaepelegrini.com.br/"
