#!/usr/bin/env bash
# Setup do coletor do Dashboard de Automacoes - Mac
# Uso: bash setup.sh
# (ou: curl -sL https://raw.githubusercontent.com/anagiuliappadvs-jpg/dashboard-automacoes/main/coletor-mac/setup.sh | bash)

set -e

REPO_URL="https://github.com/anagiuliappadvs-jpg/dashboard-automacoes.git"
REPO_DIR="$HOME/Documents/dashboard-automacoes"
DASHBOARD_URL="https://anagiuliappadvs-jpg.github.io/dashboard-automacoes/"

# Cores
GRN='\033[0;32m'; YEL='\033[1;33m'; RED='\033[0;31m'; CYA='\033[0;36m'; RST='\033[0m'

echo ""
echo -e "${CYA}=============================================${RST}"
echo -e "${CYA}  Dashboard de Automacoes - Setup Mac${RST}"
echo -e "${CYA}=============================================${RST}"
echo ""

# ---------- 1. Pre-requisitos ----------
echo -e "${YEL}[1/6]${RST} Checando pre-requisitos..."

# git
if ! command -v git >/dev/null 2>&1; then
  echo -e "${RED}Git nao instalado.${RST} Rode no Terminal: ${CYA}xcode-select --install${RST}"
  exit 1
fi
echo "    git: OK"

# brew (opcional, mas usamos pra instalar o resto)
if ! command -v brew >/dev/null 2>&1; then
  echo -e "${YEL}    Homebrew nao detectado.${RST}"
  echo "    Instalando... (vai pedir sua senha do Mac)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Adiciona ao PATH (Apple Silicon)
  if [ -d "/opt/homebrew/bin" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
echo "    brew: OK"

# node
if ! command -v node >/dev/null 2>&1; then
  echo "    Instalando Node.js..."
  brew install node
fi
NODE_VER=$(node --version)
echo "    node: $NODE_VER"

# gh
if ! command -v gh >/dev/null 2>&1; then
  echo "    Instalando GitHub CLI..."
  brew install gh
fi
echo "    gh: OK"
echo ""

# ---------- 2. Autenticar no GitHub ----------
echo -e "${YEL}[2/6]${RST} Autenticando no GitHub..."
if gh auth status >/dev/null 2>&1; then
  echo "    Ja autenticada como $(gh api user --jq .login)"
else
  echo -e "${CYA}    Vai abrir uma tela pra autenticar.${RST}"
  echo "    Responde: GitHub.com -> HTTPS -> Y -> Login with a web browser"
  echo "    (se voce nao tem conta GitHub, clica em Sign up no navegador)"
  echo ""
  read -p "    [Enter pra continuar]"
  gh auth login
fi
echo ""

# ---------- 3. Clonar repo ----------
echo -e "${YEL}[3/6]${RST} Clonando o repositorio..."
if [ -d "$REPO_DIR/.git" ]; then
  echo "    Repo ja existe em $REPO_DIR — atualizando..."
  cd "$REPO_DIR"
  git pull --rebase
else
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
  cd "$REPO_DIR"
fi
echo ""

# ---------- 4. Configurar identidade deste Mac ----------
echo -e "${YEL}[4/6]${RST} Configurando este Mac no dashboard..."
if [ -f "pc-config.json" ] && ! grep -q "MEU-NOME-AQUI" pc-config.json; then
  CURRENT_PCID=$(node -e "console.log(JSON.parse(require('fs').readFileSync('pc-config.json','utf8')).pcId)" 2>/dev/null || echo "?")
  CURRENT_PESSOA=$(node -e "console.log(JSON.parse(require('fs').readFileSync('pc-config.json','utf8')).pessoa)" 2>/dev/null || echo "?")
  echo "    Ja configurado como: $CURRENT_PESSOA (pcId: $CURRENT_PCID)"
  read -p "    Quer mudar? (s/N) " MUDAR
  if [[ "$MUDAR" != "s" && "$MUDAR" != "S" ]]; then
    SKIP_CFG=1
  fi
fi

if [ -z "${SKIP_CFG:-}" ]; then
  echo ""
  read -p "    Qual e o seu nome completo? " PESSOA
  echo ""
  echo "    Agora um identificador unico desse Mac (so letras minusculas e hifens)"
  echo "    Exemplos: lucas-mac, maria-pelegrini-mac"
  read -p "    pcId: " PCID
  cat > pc-config.json <<EOF
{
  "pcId": "$PCID",
  "pessoa": "$PESSOA"
}
EOF
  echo "    pc-config.json criado."
fi
echo ""

# ---------- 5. Lista de automacoes ----------
echo -e "${YEL}[5/6]${RST} Configurando lista de automacoes..."
if [ ! -f "coletor-mac/automacoes-locais.json" ]; then
  cp coletor-mac/automacoes-locais.example.json coletor-mac/automacoes-locais.json
  echo "    Arquivo template criado em coletor-mac/automacoes-locais.json"
  echo ""
  echo -e "${CYA}    IMPORTANTE:${RST} edite esse arquivo agora pra listar suas automacoes."
  echo "    Cada automacao precisa de: nome, descricao, agendamento, logPath, tipo"
  echo ""
  read -p "    Abrir o arquivo no editor padrao? (S/n) " EDIT
  if [[ "$EDIT" != "n" && "$EDIT" != "N" ]]; then
    open -t "coletor-mac/automacoes-locais.json"
    echo ""
    echo "    Edite o arquivo, salve, e volta aqui."
    read -p "    [Enter quando terminar]"
  fi
else
  echo "    Ja existe coletor-mac/automacoes-locais.json — mantendo."
fi
echo ""

# ---------- 6. Rodar 1x e agendar ----------
echo -e "${YEL}[6/6]${RST} Testando geracao do snapshot..."
if node coletor-mac/generate.mjs; then
  echo ""
  echo -e "${GRN}    OK! Snapshot publicado.${RST}"
else
  echo -e "${RED}    Algo deu errado. Verifique a saida acima.${RST}"
  exit 1
fi
echo ""

# Agendar via launchd
PLIST="$HOME/Library/LaunchAgents/com.dashboard.coletor.plist"
NODE_BIN=$(which node)
if [ ! -f "$PLIST" ]; then
  echo "    Agendando refresh automatico (1x por hora) via launchd..."
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.dashboard.coletor</string>
<key>ProgramArguments</key>
<array>
  <string>$NODE_BIN</string>
  <string>$REPO_DIR/coletor-mac/generate.mjs</string>
</array>
<key>WorkingDirectory</key><string>$REPO_DIR</string>
<key>StartInterval</key><integer>3600</integer>
<key>RunAtLoad</key><true/>
<key>StandardOutPath</key><string>$REPO_DIR/coletor-mac/launchd.out.log</string>
<key>StandardErrorPath</key><string>$REPO_DIR/coletor-mac/launchd.err.log</string>
</dict></plist>
EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "    Agendado. Roda toda hora automaticamente."
else
  echo "    Agendamento ja existia."
fi

echo ""
echo -e "${GRN}=============================================${RST}"
echo -e "${GRN}  Setup concluido!${RST}"
echo -e "${GRN}=============================================${RST}"
echo ""
echo "Veja o dashboard online em:"
echo -e "  ${CYA}$DASHBOARD_URL${RST}"
echo ""
echo "Seu snapshot ja esta la (recarregue a pagina em ~30s)."
echo ""
echo "Pra adicionar/mudar automacoes depois, edite:"
echo "  $REPO_DIR/coletor-mac/automacoes-locais.json"
echo "Salve e rode: node $REPO_DIR/coletor-mac/generate.mjs"
echo ""
