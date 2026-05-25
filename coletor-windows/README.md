# Coletor Windows — adicionar seu PC ao dashboard

Este guia adiciona o seu PC ao dashboard compartilhado.

## Pré-requisitos (instalar uma vez)
1. **Git** — https://git-scm.com/download/win (Next, Next, Next até o fim)
2. **GitHub CLI** — https://cli.github.com/ (Next, Next, Next)
3. **Node.js LTS** — https://nodejs.org/ (necessário se quiser testar render localmente; não obrigatório pro coletor)

## Setup (uma vez)
Abra **PowerShell** e cole estes comandos um por vez:

```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/anagiuliappadvs-jpg/dashboard-automacoes.git
cd dashboard-automacoes
gh auth login
```

No `gh auth login`: GitHub.com → HTTPS → Y → Login with a web browser → cole o código no navegador.

Configure o nome desse PC:

```powershell
@'
{
  "pcId": "MEU-NOME-AQUI",
  "pessoa": "Nome Completo Aqui"
}
'@ | Out-File -FilePath pc-config.json -Encoding utf8
```

**Importante:** o `pcId` precisa ser único entre os PCs e usar só letras minúsculas/hífens (ex: `joao-silva`, `lucas-mac`).

## Agendar refresh automático (1x por hora)
No PowerShell ainda:

```powershell
schtasks /Create /TN "Dashboard Coletor" /SC HOURLY /MO 1 /ST 08:00 /TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:USERPROFILE\Documents\dashboard-automacoes\generate.ps1`"" /F /RL LIMITED
```

## Rodar agora pra testar
```powershell
.\generate.ps1
```

Você deve ver:
- `Snapshot publicado em: ...`
- `Push pro GitHub: OK`

Em ~30s o dashboard online já mostra seu PC: https://anagiuliappadvs-jpg.github.io/dashboard-automacoes/

## Atalho na área de trabalho (opcional)
```powershell
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut("$env:USERPROFILE\Desktop\Atualizar Dashboard.lnk")
$lnk.TargetPath = "powershell.exe"
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$env:USERPROFILE\Documents\dashboard-automacoes\generate.ps1`""
$lnk.WorkingDirectory = "$env:USERPROFILE\Documents\dashboard-automacoes"
$lnk.Save()
```
