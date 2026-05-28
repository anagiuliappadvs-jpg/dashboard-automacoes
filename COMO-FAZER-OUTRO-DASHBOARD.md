# Como construir outro dashboard como este

Este documento descreve o caminho que usamos pra montar o **Dashboard de Automações**
(https://anagiuliappadvs-jpg.github.io/dashboard-automacoes/) e serve como ponto de partida
pra quem quer montar um dashboard parecido pra outro assunto.

Pode ser entregue ao Claude Code da outra pessoa (ou outra IA equivalente) como instrução
inicial — está dividido em (1) prompt pronto pra colar e (2) referência técnica.

---

## 1. Prompt pronto pra colar no Claude Code

> **Atenção:** edite os trechos `[ENTRE COLCHETES]` antes de enviar — eles descrevem
> o assunto específico do dashboard novo.

```
Quero montar um dashboard online compartilhável que mostre [O QUE VOCÊ QUER MOSTRAR —
ex: "o status de cada processo em andamento", "os contratos do mês", "o pipeline
de vendas", etc.].

Já tenho uma referência de arquitetura que funcionou bem pra outro caso, quero usar
o mesmo padrão:

- Dashboard hospedado em GitHub Pages (URL pública pra compartilhar, sem login)
- Cada PC contribuinte (Windows ou Mac) tem um "coletor" local que roda de hora em
  hora e publica um arquivo JSON com seus dados num repositório GitHub
- Uma GitHub Action dispara on push e regenera o HTML do dashboard a partir dos
  JSONs — assim não precisa ninguém rodar nada manualmente
- O HTML mostra os dados agrupados por pessoa/PC, com versão online sanitizada
  (sem dados sensíveis) e versão local detalhada na área de trabalho

Os dados específicos que quero coletar/mostrar:
- [LISTAR — ex: "data, número do processo, próxima audiência, parte contrária,
  status do andamento"]
- [LISTAR também as fontes desses dados — ex: "uma planilha do Google Sheets",
  "PDFs salvos numa pasta do Drive", "API X"]

Restrições importantes:
- Repositório precisa ser público pra GitHub Pages funcionar no plano Free
- Por isso, NUNCA expor [DADOS SENSÍVEIS — ex: "CPF de clientes", "valores
  exatos de contratos", "nomes completos de partes"] na versão online — sanitizar
  no momento do render
- A usuária que vai operar isso é [TÉCNICA? NÃO-TÉCNICA?] — preferir [scripts
  que rodam sozinhos / interfaces simples / pouco passo manual]

Roteiro que eu quero seguir:
1. Primeiro, monta a infraestrutura básica do repo (estrutura de pastas, GitHub
   Action de render, script Node que gera o HTML a partir dos JSONs)
2. Depois, escreve o coletor de dados pro [SO PRIMÁRIO — Windows ou Mac] que
   produz o JSON e faz push
3. Cria scripts de setup one-shot (PowerShell/Bash) pra outras pessoas instalarem
   no PC delas com um único comando
4. Habilita GitHub Pages
5. Testa publicação e validação online

Comece pelo passo 1. Antes de codar, me confirme:
- A estrutura JSON que vai armazenar cada snapshot
- O layout visual do HTML (mostra prototipo simples primeiro)
- O nome do repositório que vou criar
```

---

## 2. Referência técnica do nosso dashboard

### Estrutura do repositório

```
dashboard-automacoes/
├── data/                       # Snapshots JSON (um por PC contribuinte)
│   ├── ana-giulia-paccola.json
│   └── emilia-pelegrini.json
├── render/
│   └── render.mjs              # Lê data/*.json e gera index.html (roda na Action)
├── .github/workflows/
│   └── render.yml              # On push em data/, roda render.mjs e commita o HTML
├── coletor-windows/
│   ├── setup.ps1               # Setup one-shot pra outros PCs Windows
│   └── README.md
├── coletor-mac/
│   ├── setup.sh                # Setup one-shot pra Macs
│   ├── generate.mjs            # Coletor do Mac (lê config manual)
│   ├── automacoes-locais.example.json
│   └── README.md
├── generate.ps1                # Coletor do Windows (autodiscovery via Task Scheduler)
├── pc-config.json              # Identidade do PC + aliases + linksFixos
└── index.html                  # Gerado pela Action - não editar manualmente
```

### Fluxo de dados (importante entender)

```
Cada PC roda hourly via scheduler local
       ↓ (gera/atualiza data/<pcid>.json)
git pull --rebase --autostash + git push
       ↓
GitHub Action "Render dashboard" dispara (paths: data/**.json)
       ↓
node render/render.mjs lê todos os JSONs e gera index.html
       ↓
Action commita index.html
       ↓
GitHub Pages republica
       ↓
URL pública atualiza (cache do Pages ~1-2 min)
```

### Decisões de arquitetura que vale repetir

1. **Cada PC só edita seu próprio JSON** — sem race condition. Action serializa
   com `concurrency: render`.

2. **`git pull --rebase --autostash` antes do push** no coletor — previne conflitos
   quando a Action vai commitando `index.html` em paralelo.

3. **pcId precisa ser único e validado no setup** — sem isso, dois PCs sobrescrevem
   o snapshot um do outro. O setup precisa listar pcIds existentes e impedir colisão.

4. **Versão online sanitizada vs local completa** — o HTML público omite dados
   sensíveis (no nosso caso, nomes de clientes). Sanitização acontece no render,
   não no coletor (o JSON pode conter tudo, e quem tem acesso ao repo vê tudo —
   isso é OK porque o repo é público mas obscurecido).

5. **Coletor Windows tem autodiscovery** (via `Get-ScheduledTask`), Mac não tem
   equivalente confiável — Mac usa um JSON de config editado pela pessoa.

6. **Aliases configurados em `pc-config.json` campo "nomes"** — separa "nome técnico"
   (o que o sistema vê) do "nome bonito" (o que aparece no dashboard).

7. **Links fixos por automação em `pc-config.json` campo "linksFixos"** — útil
   pra apontar pras planilhas/Docs relacionados sem extrair de logs.

### Gotchas conhecidos

- **PowerShell + JSON com BOM**: `Out-File -Encoding UTF8` no PS 5.1 adiciona BOM.
  Use `[System.IO.File]::WriteAllText` com `UTF8Encoding($false)`. No Node, sempre
  fazer `.replace(/^﻿/, '')` antes de `JSON.parse`.

- **GitHub Pages em repo privado**: só com plano pago. No Free, repo público é
  obrigatório → exige sanitização da versão online.

- **PowerShell escalar vs array**: `$var.Count` em array de 1 item retorna `$null`.
  Sempre force com `@($var).Count`.

- **gh CLI auth**: requer browser interativo na primeira vez. Não dá pra fazer
  inteiramente headless num script one-shot — precisa pausar e pedir Enter.

- **Action commit + coletor push em paralelo**: conflito em `index.html` é comum.
  O coletor só pode editar `data/<pcid>.json`, nunca tocar `index.html`. Quando
  conflita por engano, `git checkout --theirs index.html` (a Action é fonte da
  verdade).

- **Cache do GitHub Pages**: leva 1-2 min depois do commit. Ctrl+F5 no navegador
  pra forçar.

- **Sem GitHub Actions secret/token especial**: o `GITHUB_TOKEN` padrão já tem
  permissão de commitar (declare `permissions: contents: write` no workflow).

### URLs e referências

- Repo: https://github.com/anagiuliappadvs-jpg/dashboard-automacoes
- Dashboard público: https://anagiuliappadvs-jpg.github.io/dashboard-automacoes/
- Conta GitHub: `anagiuliappadvs-jpg`

### Custo

Tudo grátis:
- GitHub Free (repo público + Pages + Actions com limite generoso)
- Cada PC roda local (sem servidor)
- Não precisa Vercel, AWS, Cloudflare, etc.

---

## 3. Sequência cronológica do que fizemos (caso seja útil seguir o mesmo ritmo)

1. Criamos um script local PowerShell que lia o Task Scheduler do Windows e
   produzia um HTML na área de trabalho — uso 100% local
2. Adicionamos detecção de links nas execuções (regex em logs.txt)
3. Refatoramos pra arquitetura "JSON por PC + Action que renderiza" quando surgiu
   a necessidade de multi-PC
4. Publicamos no GitHub Pages com sanitização da versão pública
5. Criamos scripts de setup one-shot pra outros PCs (Windows e Mac)
6. Adicionamos suporte a aliases de nome (`nomes` no pc-config.json) e links
   fixos por automação (`linksFixos`)

Foi iterativo — não começamos com a arquitetura final. Pode valer começar simples
e ir expandindo conforme necessário.
