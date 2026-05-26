#!/usr/bin/env node
// Coletor Mac — le pc-config.json + automacoes-locais.json, parseia logs e publica snapshot
// Uso: node generate.mjs

import { readFileSync, readdirSync, writeFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '..');

const pcCfgPath = join(repoRoot, 'pc-config.json');
const autoCfgPath = join(repoRoot, 'coletor-mac', 'automacoes-locais.json');
const dataDir = join(repoRoot, 'data');

if (!existsSync(pcCfgPath)) {
  console.error('Falta pc-config.json em', pcCfgPath);
  process.exit(1);
}
const pcCfg = JSON.parse(readFileSync(pcCfgPath, 'utf8'));

if (!existsSync(autoCfgPath)) {
  console.error('Falta', autoCfgPath, '\nCopie de automacoes-locais.example.json e edite.');
  process.exit(1);
}
const automacoesCfg = JSON.parse(readFileSync(autoCfgPath, 'utf8'));

// Parseia log file no mesmo formato do coletor Windows
function parseLogTimestamp(line) {
  let m = line.match(/\[(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2}):(\d{2})/);
  if (m) return new Date(+m[1], +m[2]-1, +m[3], +m[4], +m[5], +m[6]);
  m = line.match(/\[(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})/);
  if (m) return new Date(+m[3], +m[2]-1, +m[1], +m[4], +m[5], +m[6]);
  m = line.match(/(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})/);
  if (m) return new Date(+m[3], +m[2]-1, +m[1], +m[4], +m[5], +m[6]);
  return null;
}

function parseLogFile(path) {
  if (!path || !existsSync(path)) return [];
  const lines = readFileSync(path, 'utf8').split(/\r?\n/);
  const execs = [];
  let curStart = null, curEnd = null, curLines = [];
  const maxGapMin = 30;
  for (const linha of lines) {
    if (!linha.trim()) { curLines.push(linha); continue; }
    const ts = parseLogTimestamp(linha);
    if (ts) {
      if (!curStart) { curStart = ts; curEnd = ts; curLines.push(linha); }
      else if ((ts - curEnd) / 60000 > maxGapMin) {
        execs.push({ start: curStart, end: curEnd, lines: curLines.slice() });
        curStart = ts; curEnd = ts; curLines = [linha];
      } else { curEnd = ts; curLines.push(linha); }
    } else if (curStart) curLines.push(linha);
  }
  if (curStart) execs.push({ start: curStart, end: curEnd, lines: curLines.slice() });

  return execs.map(e => {
    const texto = e.lines.join('\n');
    const lower = texto.toLowerCase();
    const ok = /exit=0|tudo ok|=== fim ===|==== fim ====|doc criado|card criado/.test(lower);
    const erro = /exit=1|\berro\b|\berror\b|failed|falhou|alerta|unauthorized|\b401\b|\b403\b|\b500\b/.test(lower);
    let status = 'Indeterminado';
    if (erro && !ok) status = 'ERRO';
    else if (ok && !erro) status = 'OK';
    else if (ok && erro) {
      const lastSubst = e.lines.filter(l => l.trim()).slice(-1)[0] || '';
      status = /fim|exit=0|\bok\b|criado/i.test(lastSubst) ? 'OK' : 'ERRO';
    }
    // Coleta URLs em ordem cronológica e mantém só a MAIS RECENTE de cada tipo.
    // Motivo: uploads pra Drive/Sheets/etc apagam a versão anterior, então URLs
    // intermediárias do mesmo tipo apontam pra arquivos que não existem mais.
    // Múltiplas execuções fundidas num mesmo bloco (gap < 30min) iriam acumular
    // URLs fantasma sem essa dedup.
    const ultimaPorTipo = {};
    for (const l of e.lines) {
      const ms = l.matchAll(/https?:\/\/[^\s\)\"']+/g);
      for (const m of ms) {
        const u = m[0].replace(/[.,;:]+$/, '');
        let tipo = 'link';
        if (/docs\.google\.com\/document/.test(u)) tipo = 'doc';
        else if (/docs\.google\.com\/spreadsheets/.test(u)) tipo = 'sheet';
        else if (/drive\.google\.com/.test(u)) tipo = 'drive';
        else if (/trello\.com/.test(u)) tipo = 'trello';
        ultimaPorTipo[tipo] = { url: u, tipo };  // sobrescreve — fica a última
      }
    }
    const urls = Object.values(ultimaPorTipo);
    return {
      // Mesma convenção do coletor Windows: timestamp em LOCAL time, sem 'Z',
      // pra render.mjs exibir como veio (sem conversão BRT→UTC).
      start: fmtLocalIso(e.start),
      end: fmtLocalIso(e.end),
      status,
      duracaoSeg: Math.round((e.end - e.start) / 1000),
      urls,
    };
  }).sort((a, b) => b.start.localeCompare(a.start));
}

function fmtLocalIso(d) {
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

const automacoes = automacoesCfg.map(a => {
  const historico = parseLogFile(a.logPath);
  return {
    nome: a.nome,
    descricao: a.descricao || '',
    agendamento: a.agendamento || '-',
    proximaExecucao: a.proximaExecucao || null,
    ultimaExecucaoWindows: null,
    ultimoResultadoCodigo: null,
    ultimoResultadoTexto: a.tipo === 'Manual' ? 'Manual' : (historico[0]?.status || 'Sem dados'),
    runsPerdidos: 0,
    diasIntervalo: a.diasIntervalo || 1,
    tipo: a.tipo || 'Agendada',
    historico,
  };
});

const snapshot = {
  pcId: pcCfg.pcId,
  pessoa: pcCfg.pessoa,
  sistemaOperacional: 'macOS',
  geradoEm: fmtLocalIso(new Date()),
  automacoes,
};

if (!existsSync(dataDir)) mkdirSync(dataDir, { recursive: true });
const out = join(dataDir, `${pcCfg.pcId}.json`);
writeFileSync(out, JSON.stringify(snapshot, null, 2), 'utf8');
console.log('Snapshot:', out);

// Git push
try {
  process.chdir(repoRoot);
  execSync('git fetch origin', { stdio: 'pipe' });
  execSync('git pull --rebase --autostash origin main', { stdio: 'pipe' });
  const status = execSync(`git status --porcelain data/${pcCfg.pcId}.json`).toString().trim();
  if (status) {
    execSync(`git add data/${pcCfg.pcId}.json`);
    const now = new Date().toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
    execSync(`git commit -m "Snapshot ${pcCfg.pcId} - ${now}"`);
    execSync('git push', { stdio: 'pipe' });
    console.log('Push: OK');
  } else {
    console.log('Sem mudanças');
  }
} catch (e) {
  console.error('Erro git:', e.message);
  process.exit(1);
}
