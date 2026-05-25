# Dashboard de Automacoes - Gerador
# Le todas as tarefas agendadas do usuario + logs.txt dos projetos + manual-rotinas.json
# Gera "Dashboard Automacoes.html" na area de trabalho

$ErrorActionPreference = 'Continue'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outFile = Join-Path $env:USERPROFILE 'Desktop\Dashboard Automacoes.html'

# ---------- Padroes a IGNORAR (tarefas do SO/apps) ----------
$ignorarPrefixos = @(
    'Adobe', 'OneDrive', 'RtHDVBg', 'RTKCPL', 'GoogleUpdate',
    'MicrosoftEdge', 'NvNode', 'NvProfile', 'NvTm', 'NvBackend',
    'CCleaner', 'Opera', 'Mozilla', 'Brave',
    'Dashboard Automacoes'
)

function Is-IgnoredTask($name) {
    foreach ($p in $ignorarPrefixos) {
        if ($name -like "$p*") { return $true }
    }
    return $false
}

# ---------- Helpers ----------
function Encode-Html($s) {
    if ($null -eq $s) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$s)
}

function Format-Datetime($dt) {
    if ($null -eq $dt) { return '-' }
    try {
        $d = [DateTime]$dt
        if ($d.Year -lt 2000) { return '-' }
        return $d.ToString('dd/MM/yyyy HH:mm')
    } catch { return '-' }
}

# Tenta extrair timestamp de uma linha de log. Retorna [DateTime] ou $null
function Parse-LogTimestamp($line) {
    # ISO: [2026-05-22 14:59:00]
    if ($line -match '\[(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2}):(\d{2})') {
        try {
            return [DateTime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4], [int]$Matches[5], [int]$Matches[6])
        } catch { return $null }
    }
    # BR: [25/05/2026  8:33:17] ou [25/05/2026 14:31:10]
    if ($line -match '\[(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})') {
        try {
            return [DateTime]::new([int]$Matches[3], [int]$Matches[2], [int]$Matches[1], [int]$Matches[4], [int]$Matches[5], [int]$Matches[6])
        } catch { return $null }
    }
    # BR sem colchete: "20/05/2026 14:31:10"
    if ($line -match '(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})') {
        try {
            return [DateTime]::new([int]$Matches[3], [int]$Matches[2], [int]$Matches[1], [int]$Matches[4], [int]$Matches[5], [int]$Matches[6])
        } catch { return $null }
    }
    return $null
}

# Le logs.txt e retorna array de execucoes (cada uma com Start, End, Status, Mensagem)
function Parse-LogFile($path) {
    if (-not (Test-Path $path)) { return @() }
    $linhas = Get-Content -Path $path -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $linhas) { return @() }

    $execs = New-Object System.Collections.ArrayList
    $curStart = $null
    $curEnd = $null
    $curLines = New-Object System.Collections.ArrayList
    $maxGapMin = 30   # gap > 30min = nova execucao

    foreach ($linha in $linhas) {
        if ([string]::IsNullOrWhiteSpace($linha)) {
            # ignora linha vazia mas mantem o bloco
            [void]$curLines.Add($linha)
            continue
        }
        $ts = Parse-LogTimestamp $linha
        if ($ts) {
            if ($curStart -eq $null) {
                $curStart = $ts; $curEnd = $ts
                [void]$curLines.Add($linha)
            } elseif (($ts - $curEnd).TotalMinutes -gt $maxGapMin) {
                # fecha bloco anterior
                $bloco = @{
                    Start = $curStart
                    End = $curEnd
                    Linhas = @($curLines.ToArray())
                }
                [void]$execs.Add($bloco)
                $curStart = $ts; $curEnd = $ts
                $curLines = New-Object System.Collections.ArrayList
                [void]$curLines.Add($linha)
            } else {
                $curEnd = $ts
                [void]$curLines.Add($linha)
            }
        } else {
            # linha sem timestamp - parte do bloco atual
            if ($curStart -ne $null) { [void]$curLines.Add($linha) }
        }
    }
    if ($curStart -ne $null) {
        $bloco = @{
            Start = $curStart
            End = $curEnd
            Linhas = @($curLines.ToArray())
        }
        [void]$execs.Add($bloco)
    }

    # Classifica cada bloco: Status (OK / ERRO / Indeterminado) + Mensagem
    $resultado = New-Object System.Collections.ArrayList
    foreach ($e in $execs) {
        $textoCompleto = ($e.Linhas -join "`n")
        $status = 'Indeterminado'
        $msg = ''

        # Procura sinais de sucesso/falha (case-insensitive)
        $lower = $textoCompleto.ToLower()
        $erro = $false
        $ok = $false

        if ($lower -match 'exit=0' -or $lower -match 'tudo ok' -or $lower -match '=== fim ===' -or $lower -match '==== fim ====' -or $lower -match 'doc criado' -or $lower -match 'card criado') {
            $ok = $true
        }
        if ($lower -match 'exit=1' -or $lower -match 'erro\b' -or $lower -match 'error\b' -or $lower -match 'failed' -or $lower -match 'falhou' -or $lower -match 'alerta' -or $lower -match 'unauthorized' -or $lower -match '401\b' -or $lower -match '403\b' -or $lower -match '500\b') {
            $erro = $true
        }

        if ($erro -and -not $ok) { $status = 'ERRO' }
        elseif ($ok -and -not $erro) { $status = 'OK' }
        elseif ($ok -and $erro) {
            # Erros podem ser apenas mencoes em comentarios. Se terminou bem -> OK
            $ultimaLinhaSubstantiva = ($e.Linhas | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
            if ($ultimaLinhaSubstantiva -match 'fim|exit=0|ok\b|criado') { $status = 'OK' } else { $status = 'ERRO' }
        }

        # Mensagem: ultima linha "interessante" (nao-vazia, nao apenas separador)
        $ultimas = $e.Linhas | Where-Object { $_ -match '\S' -and $_ -notmatch '^[=\-]+$' } | Select-Object -Last 5
        $msg = ($ultimas | Select-Object -Last 1)
        if ($msg) { $msg = $msg.Trim() }

        # Se erro, tenta achar a linha com a palavra erro
        if ($status -eq 'ERRO') {
            $linhaErro = $e.Linhas | Where-Object { $_ -match '(?i)(erro|error|falhou|failed|unauthorized|alerta|401|403|500)' } | Select-Object -Last 1
            if ($linhaErro) { $msg = $linhaErro.Trim() }
        }

        $duracao = ($e.End - $e.Start).TotalSeconds
        $bloco = [pscustomobject]@{
            Start = $e.Start
            End = $e.End
            Status = $status
            Mensagem = $msg
            DuracaoSeg = [int]$duracao
        }
        [void]$resultado.Add($bloco)
    }
    # Ordena por data desc
    return @($resultado | Sort-Object Start -Descending)
}

# Descobre o projeto folder a partir da Action da tarefa
function Find-ProjectFolder($task) {
    foreach ($action in $task.Actions) {
        $cmd = $action.Execute
        $args = $action.Arguments
        $wd = $action.WorkingDirectory
        if ($wd -and (Test-Path (Join-Path $wd 'logs.txt'))) { return $wd }
        # Tenta extrair caminho do Execute ou Arguments
        $tudo = "$cmd $args $wd"
        if ($tudo -match '([A-Z]:\\[^"\s]+)') {
            $p = $Matches[1]
            if (Test-Path $p) {
                if ((Get-Item $p) -is [System.IO.DirectoryInfo]) {
                    if (Test-Path (Join-Path $p 'logs.txt')) { return $p }
                } else {
                    $dir = Split-Path -Parent $p
                    if (Test-Path (Join-Path $dir 'logs.txt')) { return $dir }
                }
            }
        }
    }
    return $null
}

# Traduz codigo do LastTaskResult em texto humano
function Translate-Result($code) {
    switch ($code) {
        0 { return 'Sucesso' }
        1 { return 'Erro (script saiu com exit 1)' }
        267009 { return 'Em execucao' }
        267010 { return 'Pronta (ainda nao executou)' }
        267011 { return 'Ainda nao executou' }
        267014 { return 'Cancelada pelo usuario' }
        0x41301 { return 'Em execucao' }
        0x41303 { return 'Nao executou no horario' }
        0xC000013A { return 'Encerrada por logoff/suspensao do PC' }
        default { return "Codigo $code" }
    }
}

# ---------- Coleta de dados ----------
$tarefas = Get-ScheduledTask -TaskPath '\' | Where-Object { -not (Is-IgnoredTask $_.TaskName) }
Write-Host "Encontradas $($tarefas.Count) tarefa(s) do usuario"

$dados = New-Object System.Collections.ArrayList

foreach ($t in $tarefas) {
    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath
    $projFolder = Find-ProjectFolder $t
    $logPath = if ($projFolder) { Join-Path $projFolder 'logs.txt' } else { $null }
    $execs = if ($logPath) { Parse-LogFile $logPath } else { @() }

    # Agendamento humanizado + dias de intervalo
    $sched = ''
    $diasIntervalo = 1
    foreach ($trig in $t.Triggers) {
        $tipo = $trig.CimClass.CimClassName
        $hora = ''
        if ($trig.StartBoundary) {
            try { $hora = ([DateTime]$trig.StartBoundary).ToString('HH:mm') } catch {}
        }
        switch ($tipo) {
            'MSFT_TaskDailyTrigger' { $sched = "Diariamente as $hora"; $diasIntervalo = 1 }
            'MSFT_TaskWeeklyTrigger' {
                $diasIntervalo = 7
                $dias = @()
                $dow = $trig.DaysOfWeek
                if ($dow -band 1) { $dias += 'Dom' }
                if ($dow -band 2) { $dias += 'Seg' }
                if ($dow -band 4) { $dias += 'Ter' }
                if ($dow -band 8) { $dias += 'Qua' }
                if ($dow -band 16) { $dias += 'Qui' }
                if ($dow -band 32) { $dias += 'Sex' }
                if ($dow -band 64) { $dias += 'Sab' }
                $sched = "$($dias -join ', ') as $hora"
            }
            'MSFT_TaskTimeTrigger' { $sched = "Uma vez em $hora" }
            default { $sched = "$tipo as $hora" }
        }
    }

    $row = [pscustomobject]@{
        Nome = $t.TaskName
        Descricao = $t.Description
        Agendamento = $sched
        ProximaExecucao = $info.NextRunTime
        UltimaExecucaoWindows = $info.LastRunTime
        UltimoResultadoCodigo = $info.LastTaskResult
        UltimoResultadoTexto = Translate-Result $info.LastTaskResult
        RunsPerdidos = $info.NumberOfMissedRuns
        Pasta = $projFolder
        Historico = $execs
        Tipo = 'Agendada'
        DiasIntervalo = $diasIntervalo
    }
    [void]$dados.Add($row)
}

# Rotinas manuais (KPI/CRM etc)
$manualPath = Join-Path $scriptDir 'manual-rotinas.json'
if (Test-Path $manualPath) {
    $manuais = Get-Content $manualPath -Encoding UTF8 -Raw | ConvertFrom-Json
    foreach ($m in $manuais) {
        $execs = @()
        if ($m.projeto) {
            $lp = Join-Path $m.projeto 'logs.txt'
            if (Test-Path $lp) { $execs = Parse-LogFile $lp }
        }
        $row = [pscustomobject]@{
            Nome = $m.nome
            Descricao = $m.descricao
            Agendamento = $m.agendamento
            ProximaExecucao = $null
            UltimaExecucaoWindows = $null
            UltimoResultadoCodigo = $null
            UltimoResultadoTexto = 'Manual'
            RunsPerdidos = 0
            Pasta = $m.projeto
            Historico = $execs
            Tipo = 'Manual'
        }
        [void]$dados.Add($row)
    }
}

# ---------- Resumo ----------
$hoje = (Get-Date).Date
$totalAutomacoes = $dados.Count
$okHoje = 0
$falhasHoje = 0
$alertas = New-Object System.Collections.ArrayList
$proximaGlobal = $null
foreach ($d in $dados) {
    $hist = @($d.Historico)
    $rodouHoje = $hist | Where-Object { $_.Start.Date -eq $hoje }
    if ($rodouHoje) {
        if (($rodouHoje | Where-Object { $_.Status -eq 'ERRO' }).Count -gt 0) {
            $falhasHoje++
            $msg = ($rodouHoje | Where-Object { $_.Status -eq 'ERRO' } | Select-Object -First 1).Mensagem
            [void]$alertas.Add([pscustomobject]@{ Nome=$d.Nome; Tipo='Falha hoje'; Detalhe=$msg })
        }
        elseif (($rodouHoje | Where-Object { $_.Status -eq 'OK' }).Count -gt 0) { $okHoje++ }
    }
    if ($d.Tipo -eq 'Agendada') {
        $code = $d.UltimoResultadoCodigo
        if ($code -eq 267011) {
            [void]$alertas.Add([pscustomobject]@{ Nome=$d.Nome; Tipo='Nao executou'; Detalhe='A tarefa nunca rodou pelo Windows (pode estar com problema no agendamento).' })
        }
        elseif ($null -ne $code -and $code -ne 0 -and $code -ne 267009 -and $code -ne 0x41301) {
            [void]$alertas.Add([pscustomobject]@{ Nome=$d.Nome; Tipo='Falha'; Detalhe=(Translate-Result $code) })
        }
    }
    if ($d.ProximaExecucao -and $d.ProximaExecucao.Year -gt 2000) {
        if (-not $proximaGlobal -or $d.ProximaExecucao -lt $proximaGlobal) { $proximaGlobal = $d.ProximaExecucao }
    }
}

# ---------- HTML ----------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!doctype html>')
[void]$sb.AppendLine('<html lang="pt-BR"><head><meta charset="utf-8">')
[void]$sb.AppendLine('<meta name="viewport" content="width=device-width,initial-scale=1">')
[void]$sb.AppendLine('<title>Dashboard de Automacoes</title>')
[void]$sb.AppendLine(@'
<style>
:root{--bg:#0f172a;--card:#1e293b;--card2:#293548;--ok:#22c55e;--err:#ef4444;--warn:#f59e0b;--mut:#94a3b8;--txt:#e2e8f0;--accent:#60a5fa;}
*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--txt);padding:24px;line-height:1.5}
h1{margin:0 0 4px 0;font-size:28px}
.subt{color:var(--mut);font-size:13px;margin-bottom:24px}
.sum{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px;margin-bottom:24px}
.sumcard{background:var(--card);border-radius:12px;padding:16px;border:1px solid #334155}
.sumcard .v{font-size:32px;font-weight:700;margin:0;line-height:1.1}
.sumcard .l{color:var(--mut);font-size:12px;text-transform:uppercase;letter-spacing:.5px}
.sumcard.ok .v{color:var(--ok)} .sumcard.err .v{color:var(--err)} .sumcard.warn .v{color:var(--warn)} .sumcard.acc .v{color:var(--accent)}
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
td.msg{color:var(--mut);max-width:600px;overflow:hidden;text-overflow:ellipsis}
.foot{color:var(--mut);font-size:12px;text-align:center;margin-top:32px;padding-top:16px;border-top:1px solid #334155}
.empty{color:var(--mut);font-style:italic;padding:8px 0}
</style>
'@)
[void]$sb.AppendLine('</head><body>')

[void]$sb.AppendLine('<h1>Dashboard de Automacoes</h1>')
$agora = (Get-Date).ToString('dd/MM/yyyy HH:mm')
[void]$sb.AppendLine("<div class=`"subt`">Ultima atualizacao: $agora</div>")

# Banner de alertas
if ($alertas.Count -gt 0) {
    [void]$sb.AppendLine('<div style="background:rgba(239,68,68,.12);border:1px solid rgba(239,68,68,.4);border-radius:12px;padding:16px 20px;margin-bottom:24px">')
    [void]$sb.AppendLine("<div style=`"font-weight:700;color:var(--err);margin-bottom:8px;font-size:15px`">! Atencao - $($alertas.Count) problema(s) detectado(s)</div>")
    [void]$sb.AppendLine('<ul style="margin:0;padding-left:20px">')
    foreach ($a in $alertas) {
        [void]$sb.AppendLine("<li><strong>$(Encode-Html $a.Nome)</strong> - $(Encode-Html $a.Tipo): $(Encode-Html $a.Detalhe)</li>")
    }
    [void]$sb.AppendLine('</ul></div>')
}

# Resumo
[void]$sb.AppendLine('<div class="sum">')
[void]$sb.AppendLine("<div class=`"sumcard acc`"><p class=`"v`">$totalAutomacoes</p><p class=`"l`">Automacoes monitoradas</p></div>")
[void]$sb.AppendLine("<div class=`"sumcard ok`"><p class=`"v`">$okHoje</p><p class=`"l`">Rodaram OK hoje</p></div>")
[void]$sb.AppendLine("<div class=`"sumcard err`"><p class=`"v`">$falhasHoje</p><p class=`"l`">Falhas hoje</p></div>")
$proxTxt = if ($proximaGlobal) { Format-Datetime $proximaGlobal } else { '-' }
[void]$sb.AppendLine("<div class=`"sumcard warn`"><p class=`"v`" style=`"font-size:18px`">$proxTxt</p><p class=`"l`">Proxima execucao</p></div>")
[void]$sb.AppendLine('</div>')

# Cada automacao
foreach ($d in ($dados | Sort-Object Nome)) {
    $hist = @($d.Historico)
    $ultimo = if ($hist.Count -gt 0) { $hist[0] } else { $null }
    $statusBadge = ''
    if ($d.Tipo -eq 'Manual') {
        $statusBadge = '<span class="badge man">Manual</span>'
    } elseif ($d.Tipo -eq 'Agendada') {
        # Para tarefas agendadas, prioriza o estado do Windows Task Scheduler
        # combinado com o que o log mostra do periodo esperado
        $code = $d.UltimoResultadoCodigo
        $deveriaTerRodado = $false
        $ultimaJanela = $null
        if ($d.ProximaExecucao -and $d.ProximaExecucao.Year -gt 2000) {
            $ultimaJanela = $d.ProximaExecucao.AddDays(-$d.DiasIntervalo)
            if ((Get-Date) -gt $ultimaJanela.AddMinutes(15)) { $deveriaTerRodado = $true }
        }
        $rodouNaUltimaJanela = $false
        if ($d.UltimaExecucaoWindows -and $d.UltimaExecucaoWindows.Year -gt 2000) {
            if ($deveriaTerRodado -and $d.UltimaExecucaoWindows -gt $ultimaJanela.AddHours(-2)) { $rodouNaUltimaJanela = $true }
        }

        if ($code -eq 0 -and (-not $deveriaTerRodado -or $rodouNaUltimaJanela)) {
            $statusBadge = '<span class="badge ok">OK</span>'
        } elseif ($code -eq 0 -and $deveriaTerRodado -and -not $rodouNaUltimaJanela) {
            $statusBadge = '<span class="badge warn">Atrasada</span>'
        } elseif ($code -eq 267011) {
            $statusBadge = '<span class="badge err">Nao executou</span>'
        } elseif ($code -eq 267009 -or $code -eq 0x41301) {
            $statusBadge = '<span class="badge warn">Rodando agora</span>'
        } elseif ($null -ne $code -and $code -ne 0) {
            $statusBadge = '<span class="badge err">Falha</span>'
        } elseif ($ultimo) {
            $cls = switch ($ultimo.Status) { 'OK' { 'ok' } 'ERRO' { 'err' } default { 'warn' } }
            $statusBadge = "<span class=`"badge $cls`">$($ultimo.Status)</span>"
        } else {
            $statusBadge = '<span class="badge mut">Sem dados</span>'
        }
    } elseif ($ultimo) {
        $cls = switch ($ultimo.Status) { 'OK' { 'ok' } 'ERRO' { 'err' } default { 'warn' } }
        $statusBadge = "<span class=`"badge $cls`">$($ultimo.Status)</span>"
    } else {
        $statusBadge = '<span class="badge mut">Nunca rodou</span>'
    }

    [void]$sb.AppendLine('<div class="auto">')
    [void]$sb.AppendLine("<h2>$(Encode-Html $d.Nome) $statusBadge</h2>")
    if ($d.Descricao) {
        [void]$sb.AppendLine("<div class=`"desc`">$(Encode-Html $d.Descricao)</div>")
    }

    [void]$sb.AppendLine('<div class="grid">')
    [void]$sb.AppendLine("<div class=`"cell`"><div class=`"l`">Agendamento</div><div class=`"v`">$(Encode-Html $d.Agendamento)</div></div>")
    [void]$sb.AppendLine("<div class=`"cell`"><div class=`"l`">Proxima execucao</div><div class=`"v`">$(Format-Datetime $d.ProximaExecucao)</div></div>")
    $ultRodada = if ($ultimo) { Format-Datetime $ultimo.Start } else { '-' }
    [void]$sb.AppendLine("<div class=`"cell`"><div class=`"l`">Ultima execucao</div><div class=`"v`">$ultRodada</div></div>")
    $ultMsg = if ($ultimo) { Encode-Html $ultimo.Mensagem } else { '-' }
    [void]$sb.AppendLine("<div class=`"cell`"><div class=`"l`">Detalhe ultima exec.</div><div class=`"v`">$ultMsg</div></div>")
    if ($d.Tipo -eq 'Agendada') {
        $codeTxt = "$(Encode-Html $d.UltimoResultadoTexto) (codigo $($d.UltimoResultadoCodigo))"
        [void]$sb.AppendLine("<div class=`"cell`"><div class=`"l`">Resultado Windows</div><div class=`"v`">$codeTxt</div></div>")
        if ($d.RunsPerdidos -gt 0) {
            [void]$sb.AppendLine("<div class=`"cell`"><div class=`"l`">Execucoes perdidas</div><div class=`"v`" style=`"color:var(--warn)`">$($d.RunsPerdidos)</div></div>")
        }
    }
    if ($d.Pasta) {
        [void]$sb.AppendLine("<div class=`"cell`"><div class=`"l`">Pasta do projeto</div><div class=`"v`" style=`"font-size:11px;font-family:monospace`">$(Encode-Html $d.Pasta)</div></div>")
    }
    [void]$sb.AppendLine('</div>')

    # Historico
    if ($hist.Count -gt 0) {
        [void]$sb.AppendLine("<details><summary>Historico completo ($($hist.Count) execucao(oes))</summary>")
        [void]$sb.AppendLine('<table><thead><tr><th>Data</th><th>Hora</th><th>Duracao</th><th>Status</th><th>Detalhe</th></tr></thead><tbody>')
        foreach ($h in $hist) {
            $dataTxt = $h.Start.ToString('dd/MM/yyyy')
            $horaTxt = $h.Start.ToString('HH:mm:ss')
            $durTxt = if ($h.DuracaoSeg -lt 60) { "$($h.DuracaoSeg)s" } else { "$([math]::Round($h.DuracaoSeg/60,1)) min" }
            $cls = switch ($h.Status) { 'OK' { 'ok' } 'ERRO' { 'err' } default { 'warn' } }
            $msg = Encode-Html $h.Mensagem
            if ($msg.Length -gt 200) { $msg = $msg.Substring(0,200) + '...' }
            [void]$sb.AppendLine("<tr><td>$dataTxt</td><td>$horaTxt</td><td>$durTxt</td><td><span class=`"badge $cls`">$($h.Status)</span></td><td class=`"msg`">$msg</td></tr>")
        }
        [void]$sb.AppendLine('</tbody></table></details>')
    } else {
        [void]$sb.AppendLine('<div class="empty">Sem historico de execucoes ainda.</div>')
    }
    [void]$sb.AppendLine('</div>')
}

[void]$sb.AppendLine("<div class=`"foot`">Atualiza sozinho de hora em hora. Para forcar atualizacao agora: duplo-clique no atalho `"Atualizar Dashboard`" na area de trabalho.</div>")
[void]$sb.AppendLine('</body></html>')

# Salva versao local (area de trabalho) - completa, com nomes de clientes
$htmlCompleto = $sb.ToString()
[System.IO.File]::WriteAllText($outFile, $htmlCompleto, [System.Text.UTF8Encoding]::new($false))
Write-Host "Dashboard gerado: $outFile"

# Gera versao publica sanitizada (sem dados de clientes) pro GitHub Pages
$htmlPublico = $htmlCompleto
# Remove conteudo da coluna "Detalhe" do historico
$htmlPublico = [regex]::Replace($htmlPublico, '<td class="msg">[^<]*</td>', '<td class="msg" style="color:var(--mut)">&mdash;</td>')
# Remove o card "Detalhe ultima exec." inteiro
$htmlPublico = [regex]::Replace($htmlPublico, '<div class="cell"><div class="l">Detalhe ultima exec\.</div>.*?</div></div>', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
# Sanitiza o banner de alertas (remove a parte do detalhe, mantem so o tipo)
$htmlPublico = [regex]::Replace($htmlPublico, '<li><strong>([^<]+)</strong> - ([^:]+):[^<]*</li>', '<li><strong>$1</strong> &mdash; $2</li>')
# Adiciona aviso de versao publica no topo
$htmlPublico = $htmlPublico -replace '<div class="subt">Ultima atualizacao:', '<div class="subt"><span style="background:rgba(96,165,250,.2);padding:2px 8px;border-radius:4px;color:var(--accent);margin-right:8px">VERSAO PUBLICA</span>Ultima atualizacao:'

$repoIndex = Join-Path $scriptDir 'index.html'
[System.IO.File]::WriteAllText($repoIndex, $htmlPublico, [System.Text.UTF8Encoding]::new($false))
Write-Host "index.html (publico) gerado em: $repoIndex"

# Tenta fazer push pro GitHub (silencioso se ainda nao configurado)
Push-Location $scriptDir
try {
    $gitDir = Join-Path $scriptDir '.git'
    if (Test-Path $gitDir) {
        # Verifica se ha mudancas
        $status = git status --porcelain 2>$null
        if ($status) {
            git add -A 2>$null | Out-Null
            $msg = "Dashboard refresh - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
            git commit -m "$msg" 2>$null | Out-Null
            # So tenta push se houver remote configurado
            $hasRemote = git remote 2>$null
            if ($hasRemote) {
                git push 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Push pro GitHub: OK"
                } else {
                    Write-Host "Push falhou (provavel falta de auth - rode: gh auth login)"
                }
            } else {
                Write-Host "Sem remote configurado ainda (rode setup do GitHub)"
            }
        } else {
            Write-Host "Sem mudancas pra publicar"
        }
    }
} catch {
    Write-Host "Erro git: $_"
} finally {
    Pop-Location
}
