# Coletor Mac — adicionar seu Mac ao dashboard

## Pré-requisitos (instalar uma vez)
1. **Git** já vem no macOS (rode `git --version` no Terminal)
2. **GitHub CLI** — `brew install gh` (precisa do Homebrew: https://brew.sh/)
3. **Node.js 20+** — `brew install node` ou baixe em https://nodejs.org/

## Setup (uma vez)
Abra o **Terminal** e cole estes comandos:

```bash
cd ~/Documents
git clone https://github.com/anagiuliappadvs-jpg/dashboard-automacoes.git
cd dashboard-automacoes
gh auth login
```

No `gh auth login`: GitHub.com → HTTPS → Y → Login with a web browser → cole o código no navegador.

## Configurar este Mac
```bash
cat > pc-config.json <<EOF
{
  "pcId": "MEU-NOME-AQUI",
  "pessoa": "Nome Completo Aqui"
}
EOF
```

**Importante:** o `pcId` precisa ser único entre os PCs (ex: `lucas-mac`, `joao-mac`).

## Listar suas automações
O Mac não tem Task Scheduler — você define manualmente quais automações monitorar. Crie o arquivo `coletor-mac/automacoes-locais.json` listando elas (veja `automacoes-locais.example.json` como modelo). Cada item precisa de:
- `nome`: como aparece no dashboard
- `descricao`: o que faz
- `agendamento`: texto humano (ex: "Diariamente às 09:00")
- `logPath`: caminho do arquivo de log (com timestamps `[YYYY-MM-DD HH:MM:SS]` ou `[DD/MM/YYYY HH:MM:SS]`)
- `tipo`: `Agendada` ou `Manual`

Exemplo (`coletor-mac/automacoes-locais.json`):
```json
[
  {
    "nome": "Backup fotos",
    "descricao": "Rclone pro Drive todas as madrugadas",
    "agendamento": "Diariamente as 03:00",
    "logPath": "/Users/lucas/scripts/backup/logs.txt",
    "tipo": "Agendada"
  }
]
```

## Rodar agora
```bash
cd ~/Documents/dashboard-automacoes
node coletor-mac/generate.mjs
```

Saída esperada:
- `Snapshot: .../data/seu-pcid.json`
- `Push: OK`

Em ~30s aparece online: https://anagiuliappadvs-jpg.github.io/dashboard-automacoes/

## Agendar 1x por hora (launchd)
```bash
cat > ~/Library/LaunchAgents/com.dashboard.coletor.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.dashboard.coletor</string>
<key>ProgramArguments</key>
<array>
  <string>/usr/local/bin/node</string>
  <string>$HOME/Documents/dashboard-automacoes/coletor-mac/generate.mjs</string>
</array>
<key>StartInterval</key><integer>3600</integer>
<key>RunAtLoad</key><true/>
</dict></plist>
EOF
launchctl load ~/Library/LaunchAgents/com.dashboard.coletor.plist
```

(Ajuste `/usr/local/bin/node` se `which node` apontar pra outro lugar — comum: `/opt/homebrew/bin/node` em Macs M1/M2.)
