# Setup do coletor do Dashboard de Automacoes - Windows
# Uso: cole no PowerShell:
#   irm https://raw.githubusercontent.com/anagiuliappadvs-jpg/dashboard-automacoes/main/coletor-windows/setup.ps1 | iex

$ErrorActionPreference = 'Stop'
$repoUrl = 'https://github.com/anagiuliappadvs-jpg/dashboard-automacoes.git'
$repoDir = Join-Path $env:USERPROFILE 'Documents\dashboard-automacoes'
$dashboardUrl = 'https://anagiuliappadvs-jpg.github.io/dashboard-automacoes/'

function H1($t) { Write-Host ""; Write-Host "=============================================" -ForegroundColor Cyan; Write-Host "  $t" -ForegroundColor Cyan; Write-Host "=============================================" -ForegroundColor Cyan; Write-Host "" }
function Step($n, $t) { Write-Host ""; Write-Host "[$n] $t" -ForegroundColor Yellow }
function OK($m) { Write-Host "    $m" -ForegroundColor Green }
function Info($m) { Write-Host "    $m" }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }
function Err($m) { Write-Host "    $m" -ForegroundColor Red }

H1 "Dashboard de Automacoes - Setup Windows"

# ---------- 1. Pre-requisitos ----------
Step '1/5' 'Checando pre-requisitos...'

# Verifica winget (disponivel em Win 10/11)
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Err "winget nao encontrado. Atualize o Windows ou instale 'App Installer' da Microsoft Store."
    Err "Apos instalar, rode esse script de novo."
    return
}
OK "winget: OK"

# Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Info "Instalando Git... (pode pedir confirmacao)"
    winget install --id Git.Git -e --source winget --silent --accept-source-agreements --accept-package-agreements
    # Recarrega PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}
OK "git: $((git --version) -replace 'git version ','')"

# GitHub CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Info "Instalando GitHub CLI..."
    winget install --id GitHub.cli -e --source winget --silent --accept-source-agreements --accept-package-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}
OK "gh: $((gh --version)[0])"

Write-Host ""

# ---------- 2. Autenticar GitHub ----------
Step '2/5' 'Autenticando no GitHub...'
$ghAuth = $false
try { gh auth status 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $ghAuth = $true } } catch {}
if ($ghAuth) {
    $userLogin = (gh api user --jq .login)
    OK "Ja autenticada como $userLogin"
} else {
    Info "Vai abrir uma tela pra autenticar."
    Info "Responde: GitHub.com -> HTTPS -> Y -> Login with a web browser"
    Info "(se voce nao tem conta GitHub, clica em Sign up no navegador)"
    Read-Host "    Pressione Enter pra continuar"
    gh auth login
    if ($LASTEXITCODE -ne 0) { Err "Falha na autenticacao."; return }
}

Write-Host ""

# ---------- 3. Clonar repo ----------
Step '3/5' 'Clonando o repositorio...'
if (Test-Path (Join-Path $repoDir '.git')) {
    Info "Repo ja existe em $repoDir - atualizando..."
    Push-Location $repoDir
    git pull --rebase 2>&1 | Out-Host
    Pop-Location
} else {
    $parent = Split-Path -Parent $repoDir
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    git clone $repoUrl $repoDir 2>&1 | Out-Host
}
OK "Repositorio em $repoDir"

Write-Host ""

# ---------- 4. Configurar identidade ----------
Step '4/5' 'Configurando este PC no dashboard...'
$cfgPath = Join-Path $repoDir 'pc-config.json'

# pc-config.json vem do repo (com pcId de quem fez o clone original) — SEMPRE pedimos pcId
$dataDir = Join-Path $repoDir 'data'
$existentes = @()
if (Test-Path $dataDir) {
    $existentes = Get-ChildItem $dataDir -Filter '*.json' | ForEach-Object { $_.BaseName }
}
if ($existentes.Count -gt 0) {
    Info "PCs ja cadastrados: $($existentes -join ', ')"
    Info "(Voce precisa escolher um pcId DIFERENTE desses)"
    Write-Host ""
}

$pessoa = Read-Host "    Qual e o seu nome completo?"
Write-Host ""
Info "Agora um identificador unico desse PC (so letras minusculas e hifens)"
Info "Exemplos: lucas-pc, maria-pelegrini-pc"

while ($true) {
    $pcId = Read-Host "    pcId"
    if ($pcId -notmatch '^[a-z0-9-]+$') {
        Err "Use so letras minusculas, numeros e hifens."
        continue
    }
    if (Test-Path (Join-Path $dataDir "$pcId.json")) {
        Err "'$pcId' ja existe (e de outra pessoa). Escolha outro."
        continue
    }
    break
}

@{ pcId = $pcId; pessoa = $pessoa } | ConvertTo-Json | Out-File -FilePath $cfgPath -Encoding UTF8
OK "pc-config.json criado: $pessoa ($pcId)"
Write-Host ""

# ---------- 5. Testar geracao + agendar ----------
Step '5/5' 'Testando coleta e publicando primeiro snapshot...'
$genPath = Join-Path $repoDir 'generate.ps1'
& $genPath
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
    Err "Algo deu errado na geracao. Veja a saida acima."
    return
}
Write-Host ""

# Agendar via schtasks
$taskName = 'Dashboard Coletor'
$taskExists = $false
try { schtasks /Query /TN $taskName 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { $taskExists = $true } } catch {}

if (-not $taskExists) {
    Info "Agendando refresh automatico (1x por hora)..."
    $tr = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$genPath`""
    schtasks /Create /TN $taskName /SC HOURLY /MO 1 /ST 08:00 /TR $tr /F /RL LIMITED 2>&1 | Out-Null
    OK "Agendado. Roda toda hora automaticamente."
} else {
    OK "Agendamento ja existia."
}

# Atalho na area de trabalho
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Atualizar Dashboard.lnk'
if (-not (Test-Path $lnk)) {
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = 'powershell.exe'
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$genPath`""
    $s.WorkingDirectory = $repoDir
    $s.IconLocation = 'shell32.dll,238'
    $s.Description = 'Atualizar Dashboard de Automacoes'
    $s.Save()
    OK "Atalho criado na area de trabalho: Atualizar Dashboard"
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Setup concluido!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Veja o dashboard online em:"
Write-Host "  $dashboardUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Suas automacoes do Windows Task Scheduler ja foram detectadas e publicadas."
Write-Host "Recarregue a pagina em ~30s pra ver."
Write-Host ""
Write-Host "Pra forcar atualizacao manual: duplo-clique em 'Atualizar Dashboard' na area de trabalho."
Write-Host ""
