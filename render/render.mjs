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
    return `<a href="${htmlEscape(u.url)}" target="_blank" rel="noopener" style="display:inline-block;background:rgba(96,165,250,.15);color:var(--accent);padding:2px 8px;border-radius:4px;margin-right:4px;text-decoration:none;font-size:11px">${label}</a>`;
  }).join('');
}

function bigLinksOfExec(exec) {
  if (!exec || !exec.urls || exec.urls.length === 0) return '';
  const tags = exec.urls.map(u => {
    const label = { doc: '[Doc]', sheet: '[Planilha]', drive: '[Drive]', trello: '[Trello]' }[u.tipo] || '[Link]';
    const cor = { doc: '#60a5fa', sheet: '#22c55e', trello: '#3b82f6' }[u.tipo] || '#94a3b8';
    return `<a href="${htmlEscape(u.url)}" target="_blank" rel="noopener" style="display:inline-block;background:rgba(96,165,250,.15);color:${cor};padding:6px 12px;border-radius:6px;margin-right:8px;margin-bottom:6px;text-decoration:none;font-size:13px;font-weight:500">${label} Abrir</a>`;
  }).join('');
  return `<div style="margin-top:8px"><div style="color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:6px">Arquivos da ultima execucao</div>${tags}</div>`;
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
:root{--bg:#0f172a;--card:#1e293b;--card2:#293548;--ok:#22c55e;--err:#ef4444;--warn:#f59e0b;--mut:#94a3b8;--txt:#e2e8f0;--accent:#60a5fa;}
*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--txt);padding:24px;line-height:1.5}
h1{margin:0 0 4px 0;font-size:28px}
.subt{color:var(--mut);font-size:13px;margin-bottom:24px}
.pessoa{margin:32px 0;padding:8px 0;border-top:2px solid #334155}
.pessoa-title{margin:16px 0 4px 0;font-size:24px;display:flex;align-items:center;gap:12px}
.os-badge{background:rgba(96,165,250,.15);color:var(--accent);padding:2px 10px;border-radius:999px;font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.5px}
.subt-mini{color:var(--mut);font-size:12px;margin-bottom:16px}
.auto{background:var(--card);border-radius:12px;padding:20px;margin-bottom:16px;border:1px solid #334155}
.auto h2{margin:0 0 8px 0;font-size:20px;display:flex;align-items:center;gap:10px}
.badge{display:inline-block;padding:2px 10px;border-radius:999px;font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.5px}
.badge.ok{background:rgba(34,197,94,.15);color:var(--ok)}
.badge.err{background:rgba(239,68,68,.15);color:var(--err)}
.badge.warn{background:rgba(245,158,11,.15);color:var(--warn)}
.badge.man{background:rgba(96,165,250,.15);color:var(--accent)}
.badge.mut{background:rgba(148,163,184,.15);color:var(--mut)}
.desc{color:var(--mut);font-size:14px;margin:4px 0 14px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;margin-bottom:14px}
.cell{background:var(--card2);padding:10px 12px;border-radius:8px}
.cell .l{color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.5px;margin-bottom:2px}
.cell .v{font-size:14px;font-weight:500}
details{margin-top:8px}
summary{cursor:pointer;color:var(--accent);font-size:13px;user-select:none;padding:6px 0}
summary:hover{color:#93c5fd}
table{width:100%;border-collapse:collapse;margin-top:8px;font-size:13px}
th{text-align:left;color:var(--mut);font-weight:500;padding:8px;border-bottom:1px solid #334155;font-size:11px;text-transform:uppercase;letter-spacing:.5px}
td{padding:8px;border-bottom:1px solid #2a3548;vertical-align:top}
tr:last-child td{border-bottom:none}
.empty{color:var(--mut);font-style:italic;padding:8px 0}
.foot{color:var(--mut);font-size:12px;text-align:center;margin-top:32px;padding-top:16px;border-top:1px solid #334155}
`;

const banner = `<div style="background:rgba(96,165,250,.12);border:1px solid rgba(96,165,250,.3);border-radius:8px;padding:10px 14px;margin-bottom:24px;color:var(--accent);font-size:13px">Esta e a versao publica do dashboard. Detalhes sensiveis (nomes de clientes etc) ficam apenas na versao local de cada PC.</div>`;

const html = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dashboard de Automacoes</title>
<style>${css}</style></head><body>
<h1>Dashboard de Automacoes</h1>
<div class="subt">Atualizado em: ${agoraStr} &middot; ${snapshots.length} PC(s) &middot; ${totalGlobal} automacao(oes)</div>
${banner}
${snapshots.length === 0 ? '<div class="empty">Nenhum snapshot publicado ainda.</div>' : snapshots.map(renderPessoa).join('\n')}
<div class="foot">Cada PC publica seu pr&oacute;prio snapshot automaticamente. Atualizado pelo GitHub Actions a cada push.</div>
</body></html>`;

writeFileSync(outFile, html, 'utf8');
console.log(`Renderizado em: ${outFile}`);
console.log(`Tamanho: ${html.length} bytes`);
