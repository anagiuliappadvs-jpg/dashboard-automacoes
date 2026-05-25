// Render do dashboard publico: le todos data/*.json e gera index.html consolidado
// Roda no GitHub Actions (no Node 20+) ou local pra debug

import { readFileSync, readdirSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = join(__dirname, '..');
const dataDir = join(repoRoot, 'data');
const outFile = join(repoRoot, 'index.html');

function htmlEscape(s) {
  if (s == null) return '';
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function fmtDt(iso) {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d.getTime()) || d.getFullYear() < 2000) return '-';
  const pad = n => String(n).padStart(2, '0');
  return `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fmtDtFull(iso) {
  if (!iso) return { data: '-', hora: '-' };
  const d = new Date(iso);
  if (isNaN(d.getTime())) return { data: '-', hora: '-' };
  const pad = n => String(n).padStart(2, '0');
  return {
    data: `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${d.getFullYear()}`,
    hora: `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`,
    date: d,
  };
}

function fmtDur(s) {
  if (s == null) return '';
  if (s < 60) return `${s}s`;
  return `${Math.round(s/60*10)/10} min`;
}

function statusBadge(auto) {
  const ultimo = auto.historico && auto.historico[0];
  if (auto.tipo === 'Manual') return '<span class="badge man">Manual</span>';
  if (auto.tipo === 'Agendada') {
    const code = auto.ultimoResultadoCodigo;
    let deveriaTerRodado = false, ultimaJanela = null, rodouNaUltimaJanela = false;
    if (auto.proximaExecucao) {
      const prox = new Date(auto.proximaExecucao);
      if (prox.getFullYear() > 2000) {
        ultimaJanela = new Date(prox.getTime() - (auto.diasIntervalo || 1) * 86400000);
        if (new Date() > new Date(ultimaJanela.getTime() + 15*60000)) deveriaTerRodado = true;
      }
    }
    if (auto.ultimaExecucaoWindows && ultimaJanela) {
      const ult = new Date(auto.ultimaExecucaoWindows);
      if (ult.getFullYear() > 2000 && ult > new Date(ultimaJanela.getTime() - 2*3600000)) rodouNaUltimaJanela = true;
    }
    if (code === 0 && (!deveriaTerRodado || rodouNaUltimaJanela)) return '<span class="badge ok">OK</span>';
    if (code === 0 && deveriaTerRodado && !rodouNaUltimaJanela) return '<span class="badge warn">Atrasada</span>';
    if (code === 267011) return '<span class="badge err">Nao executou</span>';
    if (code === 267009 || code === 0x41301) return '<span class="badge warn">Rodando agora</span>';
    if (code != null && code !== 0) return '<span class="badge err">Falha</span>';
    if (ultimo) {
      const cls = ultimo.status === 'OK' ? 'ok' : (ultimo.status === 'ERRO' ? 'err' : 'warn');
      return `<span class="badge ${cls}">${ultimo.status}</span>`;
    }
    return '<span class="badge mut">Sem dados</span>';
  }
  if (ultimo) {
    const cls = ultimo.status === 'OK' ? 'ok' : (ultimo.status === 'ERRO' ? 'err' : 'warn');
    return `<span class="badge ${cls}">${ultimo.status}</span>`;
  }
  return '<span class="badge mut">Nunca rodou</span>';
}

function linksOfExec(exec) {
  if (!exec || !exec.urls || exec.urls.length === 0) return '<span style="color:var(--mut);font-size:11px">&mdash;</span>';
  return exec.urls.map(u => {
    const label = { doc: 'Doc', sheet: 'Sheet', drive: 'Drive', trello: 'Trello' }[u.tipo] || 'Link';
    return `<a href="${htmlEscape(u.url)}" target="_blank" rel="noopener" style="display:inline-block;background:rgba(168,137,92,.15);color:var(--accent-dark);padding:3px 9px;border-radius:3px;margin-right:4px;text-decoration:none;font-size:11px;border:1px solid rgba(168,137,92,.3);font-family:-apple-system,Helvetica,sans-serif;font-weight:600">${label}</a>`;
  }).join('');
}

function bigLinksOfExec(exec) {
  if (!exec || !exec.urls || exec.urls.length === 0) return '';
  const tags = exec.urls.map(u => {
    const label = { doc: '[Doc]', sheet: '[Planilha]', drive: '[Drive]', trello: '[Trello]' }[u.tipo] || '[Link]';
    return `<a href="${htmlEscape(u.url)}" target="_blank" rel="noopener" style="display:inline-block;background:var(--accent);color:#FFFEF8;padding:7px 14px;border-radius:3px;margin-right:8px;margin-bottom:6px;text-decoration:none;font-size:12px;font-weight:600;font-family:-apple-system,Helvetica,sans-serif;letter-spacing:0.5px;text-transform:uppercase">${label} Abrir</a>`;
  }).join('');
  return `<div style="margin-top:10px"><div style="color:var(--accent-dark);font-size:10px;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px;font-family:-apple-system,Helvetica,sans-serif;font-weight:600">Arquivos da &uacute;ltima execu&ccedil;&atilde;o</div>${tags}</div>`;
}

function renderAutomacao(a) {
  const hist = a.historico || [];
  const ultimo = hist[0];
  const cellsCore = [
    `<div class="cell"><div class="l">Agendamento</div><div class="v">${htmlEscape(a.agendamento)}</div></div>`,
    `<div class="cell"><div class="l">Proxima execucao</div><div class="v">${fmtDt(a.proximaExecucao)}</div></div>`,
    `<div class="cell"><div class="l">Ultima execucao</div><div class="v">${ultimo ? fmtDt(ultimo.start) : '-'}</div></div>`,
  ];
  if (a.tipo === 'Agendada') {
    cellsCore.push(`<div class="cell"><div class="l">Resultado</div><div class="v">${htmlEscape(a.ultimoResultadoTexto || '-')}</div></div>`);
    if (a.runsPerdidos > 0) {
      cellsCore.push(`<div class="cell"><div class="l">Execucoes perdidas</div><div class="v" style="color:var(--warn)">${a.runsPerdidos}</div></div>`);
    }
  }

  let histHtml = '';
  if (hist.length > 0) {
    const rows = hist.map(h => {
      const f = fmtDtFull(h.start);
      const cls = h.status === 'OK' ? 'ok' : (h.status === 'ERRO' ? 'err' : 'warn');
      return `<tr><td>${f.data}</td><td>${f.hora}</td><td>${fmtDur(h.duracaoSeg)}</td><td><span class="badge ${cls}">${h.status}</span></td><td>${linksOfExec(h)}</td></tr>`;
    }).join('');
    histHtml = `<details><summary>Historico completo (${hist.length} execucao(oes))</summary>
<table><thead><tr><th>Data</th><th>Hora</th><th>Duracao</th><th>Status</th><th>Arquivos</th></tr></thead><tbody>${rows}</tbody></table></details>`;
  } else {
    histHtml = '<div class="empty">Sem historico de execucoes ainda.</div>';
  }

  return `<div class="auto">
<h2>${htmlEscape(a.nome)} ${statusBadge(a)}</h2>
${a.descricao ? `<div class="desc">${htmlEscape(a.descricao)}</div>` : ''}
<div class="grid">${cellsCore.join('')}</div>
${bigLinksOfExec(ultimo)}
${histHtml}
</div>`;
}

function renderPessoa(snap) {
  const automacoes = (snap.automacoes || []).sort((a,b) => a.nome.localeCompare(b.nome));
  const total = automacoes.length;
  const hoje = new Date(); hoje.setHours(0,0,0,0);

  let okHoje = 0, falhasHoje = 0;
  for (const a of automacoes) {
    const rodHoje = (a.historico || []).filter(h => {
      const d = new Date(h.start); d.setHours(0,0,0,0);
      return d.getTime() === hoje.getTime();
    });
    if (rodHoje.some(h => h.status === 'ERRO')) falhasHoje++;
    else if (rodHoje.some(h => h.status === 'OK')) okHoje++;
  }

  return `<section class="pessoa">
<h2 class="pessoa-title">${htmlEscape(snap.pessoa)} <span class="os-badge">${htmlEscape(snap.sistemaOperacional || '?')}</span></h2>
<div class="subt-mini">Snapshot: ${fmtDt(snap.geradoEm)} &middot; ${total} automacao(oes) &middot; ${okHoje} OK hoje &middot; ${falhasHoje} falha(s) hoje</div>
${automacoes.map(renderAutomacao).join('\n')}
</section>`;
}

// ---------- Main ----------
if (!existsSync(dataDir)) {
  console.log('Sem pasta data/. Criando exemplo vazio.');
  mkdirSync(dataDir, { recursive: true });
}

const files = readdirSync(dataDir).filter(f => f.endsWith('.json')).sort();
console.log(`Snapshots encontrados: ${files.length} (${files.join(', ')})`);

const snapshots = [];
for (const f of files) {
  try {
    const raw = readFileSync(join(dataDir, f), 'utf8').replace(/^﻿/, '');
    const j = JSON.parse(raw);
    snapshots.push(j);
  } catch (e) {
    console.error(`Erro lendo ${f}:`, e.message);
  }
}
snapshots.sort((a,b) => (a.pessoa || '').localeCompare(b.pessoa || ''));

const totalGlobal = snapshots.reduce((acc, s) => acc + (s.automacoes || []).length, 0);
const agora = new Date();
const agoraStr = `${String(agora.getDate()).padStart(2,'0')}/${String(agora.getMonth()+1).padStart(2,'0')}/${agora.getFullYear()} ${String(agora.getHours()).padStart(2,'0')}:${String(agora.getMinutes()).padStart(2,'0')}`;

const css = `
:root{
  --bg:#F0EAE0;
  --bg-texture:radial-gradient(ellipse at top,#F5EFE5 0%,#EBE3D3 100%);
  --card:#FAF6EE;
  --card2:#F2EBDD;
  --ok:#6B8E4E;
  --err:#A04545;
  --warn:#B8821F;
  --mut:#7A6F5F;
  --txt:#2A2520;
  --accent:#A8895C;
  --accent-dark:#8B6F3E;
  --accent-light:#C5A776;
  --border:#D4C8B5;
  --border-strong:#B8A988;
}
*{box-sizing:border-box}
body{
  margin:0;
  font-family:'Georgia','Times New Roman',serif;
  background:var(--bg);
  background-image:var(--bg-texture);
  background-attachment:fixed;
  color:var(--txt);
  padding:32px 24px;
  line-height:1.6;
  max-width:1200px;
  margin-left:auto;
  margin-right:auto;
}
.header{display:flex;align-items:center;gap:20px;margin-bottom:8px;padding-bottom:20px;border-bottom:2px solid var(--accent)}
.header .logo{flex-shrink:0}
.header .brand{display:flex;flex-direction:column;gap:2px}
.header .brand-name{font-family:'Georgia',serif;font-size:26px;font-weight:700;letter-spacing:1.5px;color:var(--txt);line-height:1.1}
.header .brand-sub{font-family:'Georgia',serif;font-size:13px;font-weight:400;color:var(--accent-dark);letter-spacing:2px;text-transform:uppercase}
h1{margin:24px 0 4px 0;font-size:28px;font-family:'Georgia',serif;font-weight:400;color:var(--txt);letter-spacing:0.5px}
.subt{color:var(--mut);font-size:13px;margin-bottom:24px;font-family:-apple-system,Helvetica,sans-serif;font-style:italic}
.pessoa{margin:36px 0 24px;padding:12px 0;border-top:1px solid var(--border)}
.pessoa-title{margin:16px 0 4px 0;font-size:22px;display:flex;align-items:center;gap:14px;font-family:'Georgia',serif;font-weight:600;color:var(--txt)}
.os-badge{background:var(--accent);color:#FFFEF8;padding:3px 12px;border-radius:2px;font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:1px;font-family:-apple-system,Helvetica,sans-serif}
.subt-mini{color:var(--mut);font-size:12px;margin-bottom:16px;font-family:-apple-system,Helvetica,sans-serif;font-style:italic}
.auto{background:var(--card);border-radius:6px;padding:22px;margin-bottom:14px;border:1px solid var(--border);border-left:4px solid var(--accent);box-shadow:0 1px 3px rgba(168,137,92,.08)}
.auto h2{margin:0 0 8px 0;font-size:19px;display:flex;align-items:center;gap:10px;font-family:'Georgia',serif;font-weight:600;color:var(--txt)}
.badge{display:inline-block;padding:3px 11px;border-radius:2px;font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:1px;font-family:-apple-system,Helvetica,sans-serif}
.badge.ok{background:rgba(107,142,78,.15);color:var(--ok);border:1px solid rgba(107,142,78,.3)}
.badge.err{background:rgba(160,69,69,.15);color:var(--err);border:1px solid rgba(160,69,69,.3)}
.badge.warn{background:rgba(184,130,31,.15);color:var(--warn);border:1px solid rgba(184,130,31,.3)}
.badge.man{background:rgba(168,137,92,.15);color:var(--accent-dark);border:1px solid rgba(168,137,92,.3)}
.badge.mut{background:rgba(122,111,95,.12);color:var(--mut);border:1px solid rgba(122,111,95,.25)}
.desc{color:var(--mut);font-size:13px;margin:4px 0 14px 0;font-family:-apple-system,Helvetica,sans-serif;line-height:1.5}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;margin-bottom:14px}
.cell{background:var(--card2);padding:11px 14px;border-radius:4px;border:1px solid var(--border)}
.cell .l{color:var(--accent-dark);font-size:10px;text-transform:uppercase;letter-spacing:1px;margin-bottom:3px;font-family:-apple-system,Helvetica,sans-serif;font-weight:600}
.cell .v{font-size:14px;font-weight:500;color:var(--txt);font-family:-apple-system,Helvetica,sans-serif}
details{margin-top:8px}
summary{cursor:pointer;color:var(--accent-dark);font-size:12px;user-select:none;padding:8px 0;font-family:-apple-system,Helvetica,sans-serif;font-weight:600;text-transform:uppercase;letter-spacing:0.8px}
summary:hover{color:var(--accent)}
table{width:100%;border-collapse:collapse;margin-top:8px;font-size:13px;font-family:-apple-system,Helvetica,sans-serif}
th{text-align:left;color:var(--accent-dark);font-weight:600;padding:9px 8px;border-bottom:2px solid var(--accent);font-size:10px;text-transform:uppercase;letter-spacing:1px}
td{padding:9px 8px;border-bottom:1px solid var(--border);vertical-align:top;color:var(--txt)}
tr:last-child td{border-bottom:none}
.empty{color:var(--mut);font-style:italic;padding:8px 0;font-family:-apple-system,Helvetica,sans-serif}
.foot{color:var(--mut);font-size:11px;text-align:center;margin-top:36px;padding-top:18px;border-top:1px solid var(--border);font-family:-apple-system,Helvetica,sans-serif;font-style:italic;letter-spacing:0.5px}
a{color:var(--accent-dark)}
a:hover{color:var(--accent)}
`;

const banner = `<div style="background:rgba(168,137,92,.10);border:1px solid var(--accent);border-left:4px solid var(--accent);border-radius:4px;padding:12px 16px;margin-bottom:28px;color:var(--accent-dark);font-size:13px;font-family:-apple-system,Helvetica,sans-serif;font-style:italic">Esta &eacute; a vers&atilde;o p&uacute;blica do dashboard. Detalhes sens&iacute;veis (nomes de clientes etc.) ficam apenas na vers&atilde;o local de cada PC.</div>`;

const logoSvg = `<svg viewBox="0 0 100 100" width="68" height="68" xmlns="http://www.w3.org/2000/svg" aria-label="Paccola e Pelegrini">
  <defs>
    <linearGradient id="goldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#C5A776"/>
      <stop offset="50%" stop-color="#A8895C"/>
      <stop offset="100%" stop-color="#8B6F3E"/>
    </linearGradient>
  </defs>
  <g transform="rotate(45 50 50)">
    <rect x="14" y="14" width="72" height="72" fill="none" stroke="url(#goldGrad)" stroke-width="3.5"/>
    <rect x="26" y="26" width="48" height="48" fill="none" stroke="url(#goldGrad)" stroke-width="2"/>
  </g>
  <text x="50" y="58" text-anchor="middle" font-family="Georgia,serif" font-size="19" font-weight="700" fill="url(#goldGrad)" letter-spacing="-1">P&amp;P</text>
</svg>`;

const header = `<div class="header">
  <div class="logo">${logoSvg}</div>
  <div class="brand">
    <div class="brand-name">PACCOLA &amp; PELEGRINI</div>
    <div class="brand-sub">Advogados Associados</div>
  </div>
</div>`;

const html = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Paccola &amp; Pelegrini &middot; Dashboard de Automa&ccedil;&otilde;es</title>
<style>${css}</style></head><body>
${header}
<h1>Dashboard de Automa&ccedil;&otilde;es</h1>
<div class="subt">Atualizado em ${agoraStr} &middot; ${snapshots.length} PC(s) &middot; ${totalGlobal} automa&ccedil;&atilde;o(&otilde;es) ativa(s)</div>
${banner}
${snapshots.length === 0 ? '<div class="empty">Nenhum snapshot publicado ainda.</div>' : snapshots.map(renderPessoa).join('\n')}
<div class="foot">Cada PC publica seu pr&oacute;prio snapshot automaticamente &middot; Re-renderizado pelo GitHub Actions a cada push</div>
</body></html>`;

writeFileSync(outFile, html, 'utf8');
console.log(`Renderizado em: ${outFile}`);
console.log(`Tamanho: ${html.length} bytes`);
