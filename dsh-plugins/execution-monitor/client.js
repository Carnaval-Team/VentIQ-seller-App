/**
 * Execution Monitor — Client (browser) half.
 *
 * Registers two entries that read the Session's live Trajectory through the
 * standard slot props the Harness supplies to session-scoped slots:
 *
 *  - `conversation.view`          → a full-size "Monitor" screen (own tab).
 *  - `conversation.composer.dock` → an always-visible compact status strip.
 *
 * The module is plain JavaScript: React comes from the browser module table,
 * no Harness Client package is imported, every colour is a theme token, and
 * each component renders its own stylesheet element so unmount removes it.
 */

window.__ModuleLoader__.load({
  id: '@local/dsh-execution-monitor',
  factory(require) {
    const React = require('react')
    const h = React.createElement

    /** Dictionary namespace owned by this plugin. */
    const NS = 'executionMonitor'
    /** Required services: the slot registry and the Client locale service. */
    const inject = ['slots', 'locale']

    /**
     * The compact strip above the composer. Off by default because the floating
     * widget already shows the same numbers; flip it to true to bring the strip
     * back without touching anything else.
     */
    const SHOW_COMPOSER_STRIP = false

    //#region dictionaries

    /** Simplified Chinese dictionary (the key-set source of truth). */
    const zh = {
      'view.label': '执行监视器',
      'strip.label': '运行监视',
      'panel.title': '执行监视器',
      'panel.hint': '实时进度、工具调用与失败',
      'status.running': '运行中',
      'status.idle': '空闲',
      'status.failed': '有失败',
      'status.empty': '无活动',
      'kpi.completion': '完成度',
      'kpi.completionHint': '已完成工具调用占全部调用的比例',
      'kpi.tools': '工具调用',
      'kpi.requests': '模型请求',
      'kpi.failures': '失败',
      'kpi.tokens': '令牌',
      'kpi.elapsed': '已用时间',
      'kpi.count': '{done} / {total}',
      'kpi.errorRate': '已完成调用中 {pct}% 失败',
      'kpi.tokensValue': '输入 {input} · 输出 {output}',
      'chart.mix': '结果分布',
      'chart.timeline': '工具时间线',
      'chart.timelineHint': '每个工具调用一根柱子，高度表示耗时',
      'chart.tokens': '每次回复的输出令牌',
      'list.activity': '最近工具调用',
      'list.failures': '失败详情',
      'empty.activity': '暂无工具调用',
      'empty.failures': '暂无失败',
      'empty.session': '此会话尚未开始工作',
      'table.tool': '工具',
      'table.status': '状态',
      'table.duration': '耗时',
      'table.where': '轮次/步骤',
      'table.error': '错误',
      'kind.request': '模型请求',
      'legend.ok': '成功',
      'legend.failed': '失败',
      'legend.running': '进行中',
      'legend.incomplete': '未完成',
      'unit.ms': '{value} 毫秒',
      'unit.seconds': '{value} 秒',
      'turn.step': '第 {turn} 轮 · 第 {step} 步',
      'aria.ring': '完成度 {pct}%',
      'aria.timeline': '工具时间线图表',
      'aria.tokens': '输出令牌图表',
      'aria.mix': '结果分布图表',
      'strip.summary': '{ok} 成功 · {failed} 失败 · {running} 进行中',
      'widget.aria': '浮动执行监视器',
      'widget.drag': '拖动以移动',
      'widget.minimize': '折叠监视器',
      'widget.expand': '展开监视器',
      'widget.noSession': '无活动会话',
      'checklist.title': '计划',
      'checklist.progress': '已完成 {done} / {total}',
      'checklist.empty': '本轮没有任务列表',
      'checklist.skippedCount': '{count} 项跳过',
      'warnings.title': '警告 · 已跳过',
      'warnings.hint': '未完成即从计划中移除的项',
      'warnings.empty': '没有跳过项',
      'state.done': '已完成',
      'state.active': '进行中',
      'state.pending': '待办',
      'state.skipped': '已跳过',
      'activity.more': '还有 {count} 项',
      'supa.title': 'Supabase MCP',
      'supa.read': '读取',
      'supa.write': '写入',
      'supa.readsOnly': '仅读取',
      'supa.empty': '本会话没有 Supabase MCP 调用',
      'supa.hint': '点击一行查看格式化响应',
      'supa.chipReads': '读取 {count}',
      'supa.chipWrites': '写入 {count}',
      'supa.chipErrors': '错误 {count}',
      'supa.query': '查询',
      'supa.arguments': '参数',
      'supa.response': '响应',
      'supa.status': '状态',
      'supa.pending': '进行中…',
      'supa.noSql': '无 SQL',
      'supa.rows': '{count} 行',
      'supa.emptyResponse': '空响应',
      'supa.derived': '状态码由 MCP 结果推导',
      'supa.close': '关闭详情',
      'supa.pick': '本次调用',
    }

    /** English dictionary, checked complete against the zh key set. */
    const en = {
      'view.label': 'Monitor',
      'strip.label': 'Run monitor',
      'panel.title': 'Execution monitor',
      'panel.hint': 'Live progress, tool calls and failures',
      'status.running': 'Running',
      'status.idle': 'Idle',
      'status.failed': 'Has failures',
      'status.empty': 'No activity',
      'kpi.completion': 'Completion',
      'kpi.completionHint': 'Finished tool calls over every tool call',
      'kpi.tools': 'Tool calls',
      'kpi.requests': 'Model requests',
      'kpi.failures': 'Failures',
      'kpi.tokens': 'Tokens',
      'kpi.elapsed': 'Elapsed',
      'kpi.count': '{done} / {total}',
      'kpi.errorRate': '{pct}% of finished calls failed',
      'kpi.tokensValue': 'in {input} · out {output}',
      'chart.mix': 'Outcome mix',
      'chart.timeline': 'Tool timeline',
      'chart.timelineHint': 'One bar per tool call, height is duration',
      'chart.tokens': 'Output tokens per response',
      'list.activity': 'Recent tool calls',
      'list.failures': 'Failures',
      'empty.activity': 'No tool calls yet',
      'empty.failures': 'No failures',
      'empty.session': 'This session has not started working yet',
      'table.tool': 'Tool',
      'table.status': 'Status',
      'table.duration': 'Duration',
      'table.where': 'Turn / step',
      'table.error': 'Error',
      'kind.request': 'Model request',
      'legend.ok': 'OK',
      'legend.failed': 'Failed',
      'legend.running': 'Running',
      'legend.incomplete': 'Unfinished',
      'unit.ms': '{value} ms',
      'unit.seconds': '{value} s',
      'turn.step': 'Turn {turn} · step {step}',
      'aria.ring': 'Completion {pct}%',
      'aria.timeline': 'Tool timeline chart',
      'aria.tokens': 'Output tokens chart',
      'aria.mix': 'Outcome mix chart',
      'strip.summary': '{ok} ok · {failed} failed · {running} running',
      'widget.aria': 'Floating execution monitor',
      'widget.drag': 'Drag to move',
      'widget.minimize': 'Collapse the monitor',
      'widget.expand': 'Expand the monitor',
      'widget.noSession': 'No active session',
      'checklist.title': 'Plan',
      'checklist.progress': '{done} of {total} done',
      'checklist.empty': 'No task list in this turn',
      'checklist.skippedCount': '{count} skipped',
      'warnings.title': 'Warnings · skipped',
      'warnings.hint': 'Items dropped from the plan without completing',
      'warnings.empty': 'Nothing skipped',
      'state.done': 'Done',
      'state.active': 'In progress',
      'state.pending': 'To do',
      'state.skipped': 'Skipped',
      'activity.more': '{count} more',
      'supa.title': 'Supabase MCP',
      'supa.read': 'Read',
      'supa.write': 'Write',
      'supa.readsOnly': 'Reads only',
      'supa.empty': 'No Supabase MCP calls in this session',
      'supa.hint': 'Click a row to see the formatted response',
      'supa.chipReads': '{count} reads',
      'supa.chipWrites': '{count} writes',
      'supa.chipErrors': '{count} errors',
      'supa.query': 'Query',
      'supa.arguments': 'Arguments',
      'supa.response': 'Response',
      'supa.status': 'Status',
      'supa.pending': 'Running…',
      'supa.noSql': 'No SQL',
      'supa.rows': '{count} rows',
      'supa.emptyResponse': 'Empty response',
      'supa.derived': 'Status codes are derived from the MCP result',
      'supa.close': 'Close detail',
      'supa.pick': 'This call',
    }

    /** Spanish language pack registered by this plugin (optional extra locale). */
    const es = {
      'view.label': 'Monitor',
      'strip.label': 'Monitor de ejecución',
      'panel.title': 'Monitor de ejecución',
      'panel.hint': 'Progreso en vivo, llamadas a herramientas y fallos',
      'status.running': 'En ejecución',
      'status.idle': 'Inactivo',
      'status.failed': 'Con fallos',
      'status.empty': 'Sin actividad',
      'kpi.completion': 'Completado',
      'kpi.completionHint': 'Llamadas terminadas sobre el total de llamadas',
      'kpi.tools': 'Herramientas',
      'kpi.requests': 'Peticiones al modelo',
      'kpi.failures': 'Fallos',
      'kpi.tokens': 'Tokens',
      'kpi.elapsed': 'Transcurrido',
      'kpi.count': '{done} / {total}',
      'kpi.errorRate': '{pct}% de las llamadas terminadas falló',
      'kpi.tokensValue': 'entrada {input} · salida {output}',
      'chart.mix': 'Reparto de resultados',
      'chart.timeline': 'Cronología de herramientas',
      'chart.timelineHint': 'Una barra por llamada; la altura es la duración',
      'chart.tokens': 'Tokens de salida por respuesta',
      'list.activity': 'Últimas llamadas',
      'list.failures': 'Fallos',
      'empty.activity': 'Aún no hay llamadas',
      'empty.failures': 'Sin fallos',
      'empty.session': 'Esta sesión todavía no ha empezado a trabajar',
      'table.tool': 'Herramienta',
      'table.status': 'Estado',
      'table.duration': 'Duración',
      'table.where': 'Turno / paso',
      'table.error': 'Error',
      'kind.request': 'Petición al modelo',
      'legend.ok': 'OK',
      'legend.failed': 'Fallo',
      'legend.running': 'En curso',
      'legend.incomplete': 'Sin terminar',
      'unit.ms': '{value} ms',
      'unit.seconds': '{value} s',
      'turn.step': 'Turno {turn} · paso {step}',
      'aria.ring': 'Completado {pct}%',
      'aria.timeline': 'Gráfico de cronología de herramientas',
      'aria.tokens': 'Gráfico de tokens de salida',
      'aria.mix': 'Gráfico de reparto de resultados',
      'strip.summary': '{ok} ok · {failed} fallos · {running} en curso',
      'widget.aria': 'Monitor de ejecución flotante',
      'widget.drag': 'Arrastra para mover',
      'widget.minimize': 'Plegar el monitor',
      'widget.expand': 'Desplegar el monitor',
      'widget.noSession': 'Sin sesión activa',
      'checklist.title': 'Plan',
      'checklist.progress': '{done} de {total} hechas',
      'checklist.empty': 'Sin lista de tareas en este turno',
      'checklist.skippedCount': '{count} saltadas',
      'warnings.title': 'Avisos · saltado',
      'warnings.hint': 'Elementos que salieron del plan sin completarse',
      'warnings.empty': 'Nada saltado',
      'state.done': 'Hecho',
      'state.active': 'En curso',
      'state.pending': 'Por hacer',
      'state.skipped': 'Saltado',
      'activity.more': '{count} más',
      'supa.title': 'Supabase MCP',
      'supa.read': 'Lectura',
      'supa.write': 'Escritura',
      'supa.readsOnly': 'Solo lectura',
      'supa.empty': 'Sin llamadas al MCP de Supabase en esta sesión',
      'supa.hint': 'Haz clic en una fila para ver la respuesta formateada',
      'supa.chipReads': '{count} lecturas',
      'supa.chipWrites': '{count} escrituras',
      'supa.chipErrors': '{count} errores',
      'supa.query': 'Consulta',
      'supa.arguments': 'Argumentos',
      'supa.response': 'Respuesta',
      'supa.status': 'Estado',
      'supa.pending': 'En curso…',
      'supa.noSql': 'Sin SQL',
      'supa.rows': '{count} filas',
      'supa.emptyResponse': 'Respuesta vacía',
      'supa.derived': 'Los códigos de estado se derivan del resultado del MCP',
      'supa.close': 'Cerrar detalle',
      'supa.pick': 'Esta llamada',
    }

    //#endregion

    //#region model

    const EMPTY_LIST = []
    /** Stable empty Trajectory used until the Session assembles one. */
    const EMPTY_TRAJECTORY = { eventNodes: EMPTY_LIST, requests: EMPTY_LIST, runningCalls: EMPTY_LIST }
    /** Fallback translator used when the locale seat is unavailable. */
    const fallbackT = (key) => key

    /** A finite number, or null for anything else. */
    function finite(value) {
      return typeof value === 'number' && Number.isFinite(value) ? value : null
    }

    /** Own-duration seconds between two epoch-ms stamps. */
    function secondsBetween(later, earlier) {
      const end = finite(later)
      const start = finite(earlier)
      if (end === null || start === null) return null
      return Math.max(0, (end - start) / 1000)
    }

    /** Human-readable failure text from a tool-result node. */
    function errorTextOf(result) {
      if (result === null || result === undefined) return null
      const error = result.error
      if (typeof error === 'string' && error !== '') return error
      if (error !== null && typeof error === 'object') {
        if (typeof error.message === 'string' && error.message !== '') return error.message
        if (typeof error.code === 'string' && error.code !== '') return error.code
        if (typeof error.name === 'string' && error.name !== '') return error.name
      }
      return null
    }

    /** One tool call: its identity, where it ran, how it ended. */
    function buildCall(id, name, turn, step, result, live, startedAt) {
      const failed = result !== undefined && (result.isError === true || result.error != null)
      const interrupted = result !== undefined && result.interrupted === true
      let status = 'ok'
      if (failed) status = 'failed'
      else if (result === undefined) status = live ? 'running' : 'incomplete'
      else if (interrupted) status = 'incomplete'
      return {
        id,
        name: typeof name === 'string' && name !== '' ? name : null,
        turn,
        step,
        status,
        kind: 'tool',
        seconds: result === undefined ? null : secondsBetween(result.time, result.callTime),
        startedAt: finite(startedAt),
        error: failed ? errorTextOf(result) : null,
      }
    }

    /**
     * Fold a Trajectory snapshot plus the live run flag into the numbers and
     * rows this panel draws. Pure: the same input yields the same output.
     */
    function deriveMonitor(trajectory, running) {
      const nodes = trajectory !== null && typeof trajectory === 'object' && Array.isArray(trajectory.eventNodes)
        ? trajectory.eventNodes
        : EMPTY_LIST
      const requests = trajectory !== null && typeof trajectory === 'object' && Array.isArray(trajectory.requests)
        ? trajectory.requests
        : EMPTY_LIST
      const liveCalls = trajectory !== null && typeof trajectory === 'object' && Array.isArray(trajectory.runningCalls)
        ? trajectory.runningCalls
        : EMPTY_LIST

      const resultByCall = new Map()
      for (const node of nodes) {
        if (node !== null && typeof node === 'object' && node.kind === 'tool-result' && node.callId != null) {
          resultByCall.set(String(node.callId), node)
        }
      }
      const liveById = new Map()
      for (const call of liveCalls) {
        if (call !== null && typeof call === 'object' && call.callId != null) liveById.set(String(call.callId), call)
      }

      const calls = []
      const seen = new Set()
      const turns = new Set()
      let currentTurn = 0
      let currentStep = 0
      let firstAt = null
      let lastAt = null
      let usageSeen = false
      let inputTokens = 0
      let outputTokens = 0
      let cacheReadTokens = 0
      let reasoningTokens = 0
      const tokenSeries = []

      const noteTime = (value) => {
        const time = finite(value)
        if (time === null) return
        if (firstAt === null || time < firstAt) firstAt = time
        if (lastAt === null || time > lastAt) lastAt = time
      }

      for (const node of nodes) {
        if (node === null || typeof node !== 'object') continue
        if (node.kind === 'tool-result') {
          noteTime(node.callTime)
          noteTime(node.time)
          continue
        }
        if (node.kind !== 'assistant') continue
        const turn = finite(node.turn) ?? 0
        const step = finite(node.step) ?? 0
        if (turn > 0) turns.add(turn)
        if (turn > currentTurn || (turn === currentTurn && step > currentStep)) {
          currentTurn = turn
          currentStep = step
        }
        noteTime(node.time)
        const usage = node.usage
        if (usage !== null && typeof usage === 'object') {
          usageSeen = true
          inputTokens += finite(usage.inputTokens) ?? 0
          outputTokens += finite(usage.outputTokens) ?? 0
          cacheReadTokens += finite(usage.cacheReadTokens) ?? 0
          reasoningTokens += finite(usage.reasoningTokens) ?? 0
          tokenSeries.push(finite(usage.outputTokens) ?? 0)
        } else {
          tokenSeries.push(0)
        }
        const blocks = Array.isArray(node.blocks) ? node.blocks : EMPTY_LIST
        for (const block of blocks) {
          if (block === null || typeof block !== 'object') continue
          if (block.kind !== 'tool-call' || block.callId == null) continue
          const id = String(block.callId)
          if (seen.has(id)) continue
          seen.add(id)
          const result = resultByCall.get(id)
          const live = liveById.get(id)
          calls.push(buildCall(
            id,
            block.name,
            turn,
            step,
            result,
            live !== undefined,
            result !== undefined ? result.callTime : (live !== undefined ? live.time : null),
          ))
        }
      }

      for (const entry of liveById) {
        const id = entry[0]
        if (seen.has(id)) continue
        seen.add(id)
        const call = entry[1]
        calls.push(buildCall(
          id,
          call.name,
          finite(call.turn) ?? currentTurn,
          finite(call.step) ?? currentStep,
          undefined,
          true,
          call.time,
        ))
      }

      const failures = []
      let ok = 0
      let failed = 0
      let runningCalls = 0
      let incomplete = 0
      let durationSum = 0
      let durationCount = 0
      for (const call of calls) {
        if (call.status === 'ok') ok++
        else if (call.status === 'failed') {
          failed++
          failures.push(call)
        } else if (call.status === 'running') runningCalls++
        else incomplete++
        if (call.seconds !== null) {
          durationSum += call.seconds
          durationCount++
        }
        noteTime(call.startedAt)
      }

      let requestTotal = 0
      let requestDone = 0
      let requestError = 0
      let requestRunning = 0
      for (const request of requests) {
        if (request === null || typeof request !== 'object') continue
        requestTotal++
        const requestTurn = finite(request.turn) ?? 0
        const requestStep = finite(request.step) ?? 0
        if (requestTurn > 0) turns.add(requestTurn)
        if (requestTurn > currentTurn || (requestTurn === currentTurn && requestStep > currentStep)) {
          currentTurn = requestTurn
          currentStep = requestStep
        }
        if (request.status === 'error') {
          requestError++
          failures.push({
            id: 'request:' + String(requestTotal),
            name: null,
            turn: finite(request.turn) ?? 0,
            step: finite(request.step) ?? 0,
            status: 'failed',
            kind: 'request',
            seconds: null,
            startedAt: null,
            error: typeof request.error === 'string' && request.error !== ''
              ? request.error
              : (typeof request.errorCode === 'string' && request.errorCode !== '' ? request.errorCode : null),
          })
        } else if (request.status === 'running') requestRunning++
        else if (request.status === 'complete') requestDone++
      }

      const total = calls.length
      const finished = ok + failed
      const completion = total === 0 ? 0 : Math.round((finished / total) * 100)
      const errorRate = finished === 0 ? 0 : Math.round((failed / finished) * 100)

      return {
        active: running === true,
        hasData: total > 0 || requestTotal > 0 || nodes.length > 0,
        completion,
        errorRate,
        turn: currentTurn,
        step: currentStep,
        turns: turns.size,
        calls: { total, ok, failed, running: runningCalls, incomplete },
        requests: { total: requestTotal, done: requestDone, error: requestError, running: requestRunning },
        failures: failures.reverse(),
        recent: calls.slice(-40).reverse(),
        timeline: calls.slice(-48),
        tokens: usageSeen
          ? { input: inputTokens, output: outputTokens, cacheRead: cacheReadTokens, reasoning: reasoningTokens }
          : null,
        tokenSeries,
        averageSeconds: durationCount === 0 ? null : durationSum / durationCount,
        firstAt,
        lastAt,
      }
    }

    //#endregion

    //#region formatting

    /** Compact integer text for token counts. */
    function formatCompact(value) {
      const number = finite(value) ?? 0
      if (number >= 1000000) return (number / 1000000).toFixed(1) + 'M'
      if (number >= 10000) return Math.round(number / 1000) + 'k'
      if (number >= 1000) return (number / 1000).toFixed(1) + 'k'
      return String(Math.round(number))
    }

    /** Duration text in the active locale. */
    function formatSeconds(seconds, t) {      const value = finite(seconds)
      if (value === null) return '—'
      if (value < 1) return t('unit.ms', { value: Math.round(value * 1000) })
      return t('unit.seconds', { value: value < 10 ? value.toFixed(1) : String(Math.round(value)) })
    }

    /** Elapsed clock as m:ss. */
    function formatClock(milliseconds) {
      const total = Math.max(0, Math.floor((finite(milliseconds) ?? 0) / 1000))
      const minutes = Math.floor(total / 60)
      const seconds = total % 60
      return minutes + ':' + (seconds < 10 ? '0' : '') + seconds
    }

    /** Theme token colour for one call status. */
    function statusColor(status) {
      if (status === 'failed') return 'var(--dsw-alias-state-error-primary, #ef4444)'
      if (status === 'running') return 'var(--dsw-alias-brand-primary, #4176e6)'
      if (status === 'incomplete') return 'var(--dsw-alias-state-idle-primary, #a2a4a6)'
      return 'var(--dsw-alias-state-success-primary, #22c55e)'
    }

    /** Bar height in px for one timeline entry, scaled to the longest bar. */
    function barHeight(seconds, bars) {
      let max = 0
      for (const bar of bars) {
        const value = bar.seconds === null ? 0 : bar.seconds
        if (value > max) max = value
      }
      const ratio = max <= 0 || seconds === null ? 0 : Math.min(1, seconds / max)
      return 4 + Math.round(26 * ratio)
    }

    //#endregion

    //#region checklist and floating widget state

    /** localStorage key holding the floating widget's position and fold state. */
    const WIDGET_STORAGE_KEY = 'dsh.execution-monitor.widget'
    /** localStorage key holding the Supabase MCP widget's placement. */
    const SUPABASE_STORAGE_KEY = 'dsh.execution-monitor.supabase'
    /** Stable empty list for a Session that never dropped a plan item. */
    const EMPTY_SKIPPED = Object.freeze([])
    /** Null is the todo projection's own "no list yet" value. */
    const EMPTY_TODOS = null

    /** Last todo list seen per Session, used to notice items dropped from the plan. */
    const lastTodosBySession = new Map()
    /** Items that left a Session's plan while still unfinished. */
    const skippedTodosBySession = new Map()

    /**
     * Remember the todo items that left the plan unfinished and forget the ones the
     * plan took back. Plugin-owned derived memory: the session log stays the only
     * source of truth, and this cache only annotates what the list already says.
     * @param sessionId - Session owning the list.
     * @param todos - the projection's current list, or null.
     * @returns stable array of skipped item texts.
     */
    function trackTodos(sessionId, todos) {
      if (sessionId === undefined || sessionId === null) return EMPTY_SKIPPED
      const previous = lastTodosBySession.get(sessionId)
      const present = []
      if (Array.isArray(todos)) {
        for (const item of todos) {
          if (item === null || typeof item !== 'object') continue
          if (typeof item.content !== 'string' || item.content === '') continue
          present.push({ content: item.content, status: typeof item.status === 'string' ? item.status : 'pending' })
        }
      }
      const names = new Set(present.map((item) => item.content))
      const accumulated = (skippedTodosBySession.get(sessionId) ?? EMPTY_SKIPPED).filter((content) => !names.has(content))
      if (previous !== undefined && previous.length > 0) {
        for (const item of previous) {
          if (names.has(item.content) || item.status === 'completed') continue
          if (accumulated.includes(item.content)) continue
          accumulated.push(item.content)
        }
      }
      lastTodosBySession.set(sessionId, present)
      const before = skippedTodosBySession.get(sessionId)
      const next = Object.freeze(accumulated.slice(-30))
      if (before !== undefined && before.length === next.length && before.every((value, index) => value === next[index])) return before
      skippedTodosBySession.set(sessionId, next)
      return next
    }

    /**
     * Fold the turn's plan plus the skipped memory into checklist rows.
     * @param todos - projection list, or null.
     * @param skipped - skipped item texts.
     * @returns rows, counts and the plan's own completion.
     */
    function deriveChecklist(todos, skipped) {
      const rows = []
      let done = 0
      let active = 0
      let pending = 0
      if (Array.isArray(todos)) {
        for (const item of todos) {
          if (item === null || typeof item !== 'object') continue
          if (typeof item.content !== 'string' || item.content === '') continue
          const state = item.status === 'completed' ? 'done' : item.status === 'in_progress' ? 'active' : 'pending'
          if (state === 'done') done++
          else if (state === 'active') active++
          else pending++
          rows.push({ key: 'todo:' + item.content, content: item.content, state })
        }
      }
      const skippedRows = []
      for (const content of skipped) skippedRows.push({ key: 'skipped:' + content, content, state: 'skipped' })
      const total = rows.length
      return {
        rows,
        skipped: skippedRows,
        done,
        active,
        pending,
        total,
        completion: total === 0 ? 0 : Math.round((done / total) * 100),
      }
    }

    /** Clamp the floating widget into the viewport. */
    function clampLayout(x, y) {
      const width = typeof window === 'undefined' || !Number.isFinite(window.innerWidth) ? 1280 : window.innerWidth
      const height = typeof window === 'undefined' || !Number.isFinite(window.innerHeight) ? 800 : window.innerHeight
      const maxX = Math.max(8, width - 140)
      const maxY = Math.max(8, height - 56)
      const safeX = Number.isFinite(x) ? x : width - 392
      const safeY = Number.isFinite(y) ? y : 96
      return { x: Math.min(Math.max(8, safeX), maxX), y: Math.min(Math.max(8, safeY), maxY) }
    }

    /** Where a widget starts before anyone drags it. */
    function defaultLayout(placement) {
      const width = typeof window === 'undefined' || !Number.isFinite(window.innerWidth) ? 1280 : window.innerWidth
      const height = typeof window === 'undefined' || !Number.isFinite(window.innerHeight) ? 800 : window.innerHeight
      const collapsed = false
      // The two widgets start in their own column so neither covers the other.
      if (placement === 'left') return { x: width >= 1000 ? 300 : 24, y: 96, collapsed }
      return { x: Math.max(8, width - 392), y: 96, collapsed }
    }

    /** Restore a widget's position and fold state, falling back to its placement. */
    function loadWidgetLayout(storageKey, placement) {
      const fallback = defaultLayout(placement)
      if (typeof window === 'undefined' || window.localStorage === undefined) return fallback
      try {
        const raw = window.localStorage.getItem(storageKey)
        if (raw === null) return fallback
        const parsed = JSON.parse(raw)
        if (parsed === null || typeof parsed !== 'object') return fallback
        const clamped = clampLayout(parsed.x, parsed.y)
        return { x: clamped.x, y: clamped.y, collapsed: parsed.collapsed === true }
      } catch (error) {
        return fallback
      }
    }

    /** Persist a widget's position and fold state. */
    function saveWidgetLayout(storageKey, layout) {
      if (typeof window === 'undefined' || window.localStorage === undefined) return
      try {
        window.localStorage.setItem(storageKey, JSON.stringify({
          x: Math.round(layout.x),
          y: Math.round(layout.y),
          collapsed: layout.collapsed === true,
        }))
      } catch (error) {
        /* a blocked store only loses the remembered position */
      }
    }

    /** True for a value shaped like an observable snapshot. */
    function isObservable(value) {
      return value !== null && value !== undefined && typeof value.getSnapshot === 'function' && typeof value.subscribe === 'function'
    }

    /** Immutable empty sources so hook arguments stay stable. */
    const EMPTY_TRAJECTORY_SOURCE = { getSnapshot: () => EMPTY_TRAJECTORY, subscribe: () => () => {} }
    const EMPTY_TODOS_SOURCE = { getSnapshot: () => EMPTY_TODOS, subscribe: () => () => {} }

    /**
     * Resolve the session-scoped sources the root-scoped floating widget needs from
     * the main binding's own hook shares — the same Trajectory and Session
     * projection the session-scoped slots receive. Cached per Session.
     * @returns resolver from a materialized main binding to its sources.
     */
    function createSourceResolver() {
      const cache = new Map()
      return (mainValue) => {
        const sessionId = mainValue === null || mainValue === undefined || mainValue.key === undefined ? undefined : String(mainValue.key)
        if (sessionId === undefined) return { trajectory: EMPTY_TRAJECTORY_SOURCE, todos: EMPTY_TODOS_SOURCE }
        const cached = cache.get(sessionId)
        if (cached !== undefined) return cached
        let trajectory
        let todos
        try {
          trajectory = mainValue.hooks === undefined ? undefined : mainValue.hooks.trajectory
        } catch (error) {
          trajectory = undefined
        }
        try {
          todos = mainValue.keyedHooks === undefined || typeof mainValue.keyedHooks.projection !== 'function'
            ? undefined
            : mainValue.keyedHooks.projection('todos')
        } catch (error) {
          todos = undefined
        }
        const resolved = {
          trajectory: isObservable(trajectory) ? trajectory : EMPTY_TRAJECTORY_SOURCE,
          todos: isObservable(todos) ? todos : EMPTY_TODOS_SOURCE,
        }
        if (cache.size >= 8) {
          const oldest = cache.keys().next()
          if (oldest.done !== true) cache.delete(oldest.value)
        }
        cache.set(sessionId, resolved)
        return resolved
      }
    }

    //#endregion

    //#region supabase MCP traffic

    /** Tool names owned by the Supabase MCP server (`mcp__supabase__*`). */
    const SUPABASE_TOOL = /(^|__)supabase(__|$)/i
    /** Supabase tools that only read. */
    const READ_TOOL = /^(list_|get_|search_|generate_|read_)/i
    /** SQL that only reads. */
    const READ_SQL = /^\s*(select|with|table|values|show|explain|describe|analyze)\b/i
    /** SQL that changes data or schema. */
    const WRITE_SQL = /^\s*(insert|update|delete|merge|create|alter|drop|truncate|grant|revoke|comment|copy|call|do|set|reset|begin|commit|rollback|refresh|vacuum|reindex|cluster|notify|listen|unlisten|lock|savepoint|prepare|execute|deallocate|import|security|move|checkpoint|discard|declare|fetch|close)\b/i

    /** Whether a tool call belongs to the Supabase MCP server. */
    function isSupabaseTool(name) {
      return typeof name === 'string' && SUPABASE_TOOL.test(name)
    }

    /** `mcp__supabase__execute_sql` -> `execute_sql`; other names unchanged. */
    function shortToolName(name) {
      if (typeof name !== 'string' || name === '') return 'tool'
      const parts = name.split('__')
      return parts.length > 1 ? parts[parts.length - 1] : name
    }

    /** Parse a JSON object out of a raw argument string. */
    function parseJsonObject(text) {
      if (typeof text !== 'string' || text === '') return null
      try {
        const value = JSON.parse(text)
        return value !== null && typeof value === 'object' && !Array.isArray(value) ? value : null
      } catch (error) {
        return null
      }
    }

    /** The SQL a Supabase call ran, when its arguments carry one. */
    function sqlOfCall(argsRaw) {
      const args = parseJsonObject(argsRaw)
      if (args === null) return null
      for (const key of ['query', 'sql', 'statement']) {
        if (typeof args[key] === 'string' && args[key].trim() !== '') return args[key]
      }
      return null
    }

    /** Whether a Supabase call only reads. */
    function isReadCall(shortName, sql) {
      if (sql !== null) {
        if (READ_SQL.test(sql)) return true
        if (WRITE_SQL.test(sql)) return false
      }
      return READ_TOOL.test(shortName)
    }

    /** Text of a tool result's content blocks. */
    function flattenBlocks(blocks) {
      if (typeof blocks === 'string') return blocks
      if (!Array.isArray(blocks)) return null
      const parts = []
      for (const block of blocks) {
        if (block === null || typeof block !== 'object') continue
        if (typeof block.text === 'string') parts.push(block.text)
        else if (typeof block.value === 'string') parts.push(block.value)
        else if (block.type === 'image') parts.push('[image]')
      }
      return parts.length === 0 ? null : parts.join('\n')
    }

    /** The SQLSTATE or PostgREST code quoted by an error message. */
    function sqlStateOf(text) {
      if (typeof text !== 'string' || text === '') return null
      const quoted = /"code"\s*:\s*"([0-9A-Za-z]{5,9})"/.exec(text)
      if (quoted !== null) return quoted[1].toUpperCase()
      const pgrst = /\b(PGRST[0-9]{3})\b/.exec(text)
      if (pgrst !== null) return pgrst[1].toUpperCase()
      const sqlstate = /\bSQLSTATE\s+([0-9A-Za-z]{5})\b/i.exec(text)
      return sqlstate === null ? null : sqlstate[1].toUpperCase()
    }

    /** Postgres SQLSTATE / PostgREST class -> HTTP-style status. */
    function statusFromCode(code) {
      if (code === '42501' || code.startsWith('28')) return 403
      if (code.startsWith('PGRST')) return code === 'PGRST116' ? 404 : 400
      if (code.startsWith('42') || code.startsWith('22')) return 400
      if (code.startsWith('23') || code.startsWith('40')) return 409
      if (code.startsWith('53')) return 503
      if (code.startsWith('54') || code.startsWith('55')) return 500
      if (code.startsWith('57')) return 499
      return 500
    }

    /**
     * HTTP-style status for one call. The MCP result carries no status line, so a
     * reported `meta.statusCode` wins, otherwise the code is derived from the
     * failure: a SQLSTATE/PostgREST code when the message names one, and the
     * message's own wording for the rest.
     */
    function deriveStatus(entity) {
      if (entity.status === 'running') return { code: null, reason: null }
      if (entity.status === 'incomplete') return { code: 499, reason: null }
      if (entity.status === 'ok') return { code: 200, reason: null }
      const text = entity.errorText === null ? '' : entity.errorText
      const code = sqlStateOf(text)
      if (code !== null) return { code: statusFromCode(code), reason: code }
      if (/interrupt|denied|rejected|cancel|abort/i.test(text)) return { code: 499, reason: null }
      if (/timeout|timed out|deadline/i.test(text)) return { code: 504, reason: null }
      if (/permission|privilege|unauthor|forbidden/i.test(text)) return { code: 403, reason: null }
      if (/not found|does not exist|no such|undefined (table|column|function)/i.test(text)) return { code: 404, reason: null }
      if (/syntax|invalid input|invalid json/i.test(text)) return { code: 400, reason: null }
      return { code: 500, reason: null }
    }

    /** HTTP class of a derived status, for colouring. */
    function statusTone(code) {
      if (code === null) return 'running'
      if (code >= 500) return 'failed'
      if (code >= 400) return 'warn'
      return 'ok'
    }

    /** Display colour token for a derived status. */
    function statusToneColor(code) {
      const tone = statusTone(code)
      if (tone === 'failed') return statusColor('failed')
      if (tone === 'warn') return 'var(--dsw-alias-state-warn-primary, #f59e0b)'
      if (tone === 'running') return statusColor('running')
      return statusColor('ok')
    }

    /** Columns of an array of row objects, in first-seen order. */
    function columnsOf(rows) {
      const columns = []
      for (const row of rows.slice(0, 25)) {
        if (row === null || typeof row !== 'object' || Array.isArray(row)) continue
        for (const key of Object.keys(row)) if (!columns.includes(key)) columns.push(key)
      }
      return columns
    }

    /** Shape a response body: parsed rows, parsed JSON, or raw text. */
    function shapeResponse(text) {
      if (text === null || text.trim() === '') return { kind: 'empty', rows: null, columns: null, wrapper: null, text: null }
      const trimmed = text.trim()
      if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        try {
          const value = JSON.parse(trimmed)
          if (Array.isArray(value)) {
            const columns = columnsOf(value)
            if (columns.length > 0) return { kind: 'rows', rows: value, columns, wrapper: null, text: null }
            return { kind: 'json', rows: null, columns: null, wrapper: null, text: JSON.stringify(value, null, 2) }
          }
          if (value !== null && typeof value === 'object') {
            // Most MCP tools wrap their rows in one named array: show those rows.
            const arrayKeys = Object.keys(value).filter((key) => {
              const candidate = value[key]
              return Array.isArray(candidate) && candidate.length > 0 &&
                candidate[0] !== null && typeof candidate[0] === 'object' && !Array.isArray(candidate[0])
            })
            if (arrayKeys.length === 1) {
              const rows = value[arrayKeys[0]]
              const columns = columnsOf(rows)
              if (columns.length > 0) return { kind: 'rows', rows, columns, wrapper: arrayKeys[0], text: null }
            }
            return { kind: 'json', rows: null, columns: null, wrapper: null, text: JSON.stringify(value, null, 2) }
          }
        } catch (error) {
          /* the payload only looked like JSON */
        }
      }
      return { kind: 'text', rows: null, columns: null, wrapper: null, text }
    }

    /** One Supabase call, with its response, timing and derived status. */
    function buildSupabaseEntry(id, name, argsRaw, turn, step, result, live) {
      const short = shortToolName(name)
      const sql = sqlOfCall(argsRaw)
      const responseText = result === undefined ? null : flattenBlocks(result.content)
      const failed = result !== undefined && (result.isError === true || result.error != null)
      let status = 'ok'
      if (result === undefined) status = live !== undefined ? 'running' : 'incomplete'
      else if (failed) status = 'failed'
      else if (result.interrupted === true) status = 'incomplete'
      const errorText = failed ? (responseText !== null && responseText !== '' ? responseText : errorTextOf(result)) : null
      const entity = {
        id,
        name,
        short,
        isRead: isReadCall(short, sql),
        sql,
        argsRaw: typeof argsRaw === 'string' && argsRaw !== '' ? argsRaw : null,
        turn: finite(turn) ?? 0,
        step: finite(step) ?? 0,
        status,
        errorText,
        startedAt: result === undefined ? finite(live === undefined ? null : live.time) : finite(result.callTime),
        endedAt: result === undefined ? null : finite(result.time),
        seconds: result === undefined ? null : secondsBetween(result.time, result.callTime),
      }
      const reported = result !== undefined && result.meta !== null && typeof result.meta === 'object' && Number.isInteger(result.meta.statusCode)
        ? result.meta.statusCode
        : null
      const derived = deriveStatus(entity)
      return {
        ...entity,
        code: reported === null ? derived.code : reported,
        codeReason: reported === null ? derived.reason : 'meta',
        response: shapeResponse(responseText),
      }
    }

    /**
     * Every Supabase MCP call in a Trajectory, newest first, with the counts the
     * widget shows. Reads and writes are classified from the SQL when there is
     * one and from the tool name otherwise.
     */
    function deriveSupabaseActivity(trajectory) {
      const nodes = trajectory !== null && typeof trajectory === 'object' && Array.isArray(trajectory.eventNodes)
        ? trajectory.eventNodes
        : EMPTY_LIST
      const liveCalls = trajectory !== null && typeof trajectory === 'object' && Array.isArray(trajectory.runningCalls)
        ? trajectory.runningCalls
        : EMPTY_LIST
      const resultByCall = new Map()
      for (const node of nodes) {
        if (node !== null && typeof node === 'object' && node.kind === 'tool-result' && node.callId != null) {
          resultByCall.set(String(node.callId), node)
        }
      }
      const liveById = new Map()
      for (const call of liveCalls) {
        if (call !== null && typeof call === 'object' && call.callId != null && isSupabaseTool(call.name)) {
          liveById.set(String(call.callId), call)
        }
      }
      const entries = []
      const seen = new Set()
      for (const node of nodes) {
        if (node === null || typeof node !== 'object' || node.kind !== 'assistant') continue
        const blocks = Array.isArray(node.blocks) ? node.blocks : EMPTY_LIST
        for (const block of blocks) {
          if (block === null || typeof block !== 'object' || block.kind !== 'tool-call' || block.callId == null) continue
          if (!isSupabaseTool(block.name)) continue
          const id = String(block.callId)
          if (seen.has(id)) continue
          seen.add(id)
          entries.push(buildSupabaseEntry(id, block.name, block.argsRaw, node.turn, node.step, resultByCall.get(id), liveById.get(id)))
        }
      }
      for (const entry of liveById) {
        if (seen.has(entry[0])) continue
        seen.add(entry[0])
        const call = entry[1]
        entries.push(buildSupabaseEntry(entry[0], call.name, call.argsRaw, call.turn, call.step, undefined, call))
      }
      let reads = 0
      let writes = 0
      let errors = 0
      let running = 0
      let totalSeconds = 0
      let timed = 0
      for (const entry of entries) {
        if (entry.isRead) reads++
        else writes++
        if (entry.status === 'failed' || entry.status === 'incomplete') errors++
        if (entry.status === 'running') running++
        if (entry.seconds !== null) {
          totalSeconds += entry.seconds
          timed++
        }
      }
      return {
        entries: entries.reverse(),
        total: entries.length,
        reads,
        writes,
        errors,
        running,
        averageSeconds: timed === 0 ? null : totalSeconds / timed,
      }
    }

    //#endregion

    //#region hooks

    /** Stable no-op subscription for fallback hooks. */
    const subscribeNothing = () => () => {}

    /** Build a stable hook that reads one constant while a provider is absent. */
    function createEmptyHook(emptyValue) {
      const read = () => emptyValue
      return function useEmpty() {
        return React.useSyncExternalStore(subscribeNothing, read, read)
      }
    }

    const useEmptyTrajectory = createEmptyHook(EMPTY_TRAJECTORY)
    const useEmptyBoolean = createEmptyHook(false)
    const useEmptyString = createEmptyHook('')
    const useEmptyProjection = createEmptyHook(EMPTY_TODOS)
    const useEmptyMain = createEmptyHook(undefined)

    /** The whole Trajectory snapshot: a stable reference per assembly revision. */
    const selectTrajectory = (snapshot) => snapshot
    /** The open state of the Session, as a primitive. */
    const selectOpenState = (snapshot) => (snapshot === null || snapshot === undefined ? '' : String(snapshot.openState ?? ''))
    /** The todo projection: this turn's plan, or null before its first write. */
    const selectTodos = (value) => (Array.isArray(value) ? value : EMPTY_TODOS)
    /** The materialized main binding, compared by reference. */
    const selectMainValue = (value) => value
    /** Fallback resolver when the widget registration supplies none. */
    const resolveNoSources = () => ({ trajectory: EMPTY_TRAJECTORY_SOURCE, todos: EMPTY_TODOS_SOURCE })

    /** A ticking clock, running only while the Session is working. */
    function useNow(active) {
      const [now, setNow] = React.useState(() => Date.now())
      React.useEffect(() => {
        if (active !== true) return undefined
        const timer = setInterval(() => setNow(Date.now()), 1000)
        return () => clearInterval(timer)
      }, [active])
      return now
    }

    /**
     * Read the live Trajectory, the run flag, the Session open state and this
     * turn's plan through the standard slot props, falling back to constants when
     * a provider is absent. The chosen hook function is stable, so hook order
     * never moves.
     */
    function useMonitorInputs(props) {
      const sessionId = props.sessionId
      const useTrajectorySafe = typeof props.useTrajectory === 'function' ? props.useTrajectory : useEmptyTrajectory
      const useStatusSafe = typeof props.useSessionStatus === 'function' ? props.useSessionStatus : useEmptyBoolean
      const useSessionSafe = typeof props.useSession === 'function' ? props.useSession : useEmptyString
      const useProjectionSafe = typeof props.useProjection === 'function' ? props.useProjection : useEmptyProjection
      const selectRunning = React.useCallback(
        (statuses) => {
          if (statuses === null || statuses === undefined || typeof statuses.get !== 'function') return false
          return statuses.get(sessionId)?.running === true
        },
        [sessionId],
      )
      const trajectory = useTrajectorySafe(selectTrajectory)
      const running = useStatusSafe(selectRunning)
      const openState = useSessionSafe(selectOpenState)
      const todos = useProjectionSafe('todos', selectTodos)
      const stats = React.useMemo(() => deriveMonitor(trajectory, running), [trajectory, running])
      // Derived plugin memory: idempotent, so repeating it during a render is safe.
      const skipped = React.useMemo(() => trackTodos(sessionId, todos), [sessionId, todos])
      const checklist = React.useMemo(() => deriveChecklist(todos, skipped), [todos, skipped])
      return { stats, running, openState, todos, checklist }
    }

    //#endregion

    //#region styles

    /** Rules every surface needs, whatever else is mounted. */
    const SHARED_CSS = [
      '.dshEm_dot{width:7px;height:7px;border-radius:50%;flex:none;background:var(--dsw-alias-state-idle-primary,#a2a4a6)}',
      '.dshEm_track{flex:none;width:76px;height:6px;border-radius:999px;overflow:hidden;background:var(--dsw-alias-border-l1,#ededed)}',
      '.dshEm_fill{display:block;height:100%;border-radius:999px;background:var(--dsw-alias-brand-primary,#4176e6);transition:width .3s ease}',
      '.dshEm_spacer{flex:1 1 auto;min-width:0}',
      '.dshEm_card{display:flex;flex-direction:column;gap:6px;min-width:0;padding:12px 14px;border:.5px solid var(--dsw-alias-border-l2,#e5e5e5);border-radius:var(--dsw-radius-md,12px);background:var(--dsw-alias-bg-layer-2,#f5f5f5)}',
      '.dshEm_cardLabel{color:var(--dsw-alias-label-secondary,#545557);font-size:11.5px;letter-spacing:.02em}',
      '.dshEm_hint{color:var(--dsw-alias-label-tertiary,#a2a4a6);font-size:11.5px;line-height:16px}',
      '.dshEm_badge{display:inline-flex;align-items:center;height:18px;padding:0 6px;border-radius:999px;background:var(--dsw-alias-state-error-primary,#ef4444);color:#fff;font-size:11px;font-weight:600}',
      '.dshEm_mono{font-family:var(--ds-font-family-code,ui-monospace,Consolas,monospace);font-size:11.5px}',
      '.dshEm_errorText{color:var(--dsw-alias-state-error-primary,#ef4444)}',
      '.dshEm_col{flex:1 1 0;min-width:2px;border-radius:2px 2px 0 0;background:var(--dsw-alias-state-idle-primary,#a2a4a6)}',
    ].join('')

    /** Checklist rules shared by the full screen and the floating widget. */
    const CHECKLIST_CSS = [
      '.dshEm_check{display:flex;flex-direction:column;gap:6px;min-width:0}',
      '.dshEm_progressRow{display:flex;align-items:center;gap:8px;color:var(--dsw-alias-label-secondary,#545557);font-size:11.5px;font-variant-numeric:tabular-nums}',
      '.dshEm_items{display:flex;flex-direction:column;gap:2px;margin:0;padding:0;list-style:none;max-height:240px;overflow:auto}',
      '.dshEm_item{display:flex;align-items:flex-start;gap:7px;padding:2px 0;font-size:12px;line-height:16px}',
      '.dshEm_itemText{min-width:0;word-break:break-word}',
      '.dshEm_item--done .dshEm_itemText{text-decoration:line-through;color:var(--dsw-alias-label-tertiary,#a2a4a6)}',
      '.dshEm_item--skipped .dshEm_itemText{text-decoration:line-through;color:var(--dsw-alias-state-warn-primary,#f59e0b)}',
      '.dshEm_item--active .dshEm_itemText{color:var(--dsw-alias-label-primary,#0f0f0f)}',
      '.dshEm_item--pending .dshEm_itemText{color:var(--dsw-alias-label-secondary,#545557)}',
      '.dshEm_mark{flex:none;width:13px;text-align:center;font-size:11px;line-height:16px}',
      '.dshEm_mark--done{color:var(--dsw-alias-state-success-primary,#22c55e)}',
      '.dshEm_mark--active{color:var(--dsw-alias-brand-primary,#4176e6)}',
      '.dshEm_mark--pending{color:var(--dsw-alias-label-tertiary,#a2a4a6)}',
      '.dshEm_mark--skipped{color:var(--dsw-alias-state-warn-primary,#f59e0b)}',
      '.dshEm_sr{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0}',
    ].join('')

    const BASE_CSS = [
      '.dshEm_root{box-sizing:border-box;display:flex;flex-direction:column;gap:12px;flex:1 1 auto;width:100%;min-height:0;overflow:auto;padding:14px 18px 26px;background:var(--dsw-alias-bg-layer-1,#fff);color:var(--dsw-alias-label-primary,#0f0f0f);font-family:var(--dsw-font-family,system-ui);font-size:13px;line-height:18px}',
      '.dshEm_root *{box-sizing:border-box}',
      '.dshEm_header{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap}',
      '.dshEm_titleRow{display:flex;align-items:center;gap:8px;min-width:0}',
      '.dshEm_title{font-size:14px;font-weight:600}',
      '.dshEm_hint{color:var(--dsw-alias-label-tertiary,#a2a4a6);font-size:11.5px;line-height:16px}',
      '.dshEm_muted{color:var(--dsw-alias-label-tertiary,#a2a4a6)}',
      '.dshEm_pill{display:inline-flex;align-items:center;gap:6px;height:22px;padding:0 9px;border-radius:999px;background:var(--dsw-alias-bg-module-platform,var(--dsw-alias-bg-layer-2,#f5f5f5));color:var(--dsw-alias-label-secondary,#545557);font-size:11.5px;white-space:nowrap}',
      '.dshEm_dot{width:7px;height:7px;border-radius:50%;flex:none;background:var(--dsw-alias-state-idle-primary,#a2a4a6)}',
      '.dshEm_grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(168px,1fr));gap:10px}',
      '.dshEm_card{display:flex;flex-direction:column;gap:6px;min-width:0;padding:12px 14px;border:.5px solid var(--dsw-alias-border-l2,#e5e5e5);border-radius:var(--dsw-radius-md,12px);background:var(--dsw-alias-bg-layer-2,#f5f5f5)}',
      '.dshEm_ringCard{flex-direction:row;align-items:center;gap:14px}',
      '.dshEm_cardLabel{color:var(--dsw-alias-label-secondary,#545557);font-size:11.5px;letter-spacing:.02em}',
      '.dshEm_big{font-size:22px;font-weight:600;font-variant-numeric:tabular-nums;line-height:26px}',
      '.dshEm_errorText{color:var(--dsw-alias-state-error-primary,#ef4444)}',
      '.dshEm_bar{display:flex;height:8px;border-radius:999px;overflow:hidden;background:var(--dsw-alias-border-l1,#ededed)}',
      '.dshEm_seg{height:100%;min-width:0}',
      '.dshEm_legend{display:flex;flex-wrap:wrap;gap:10px;color:var(--dsw-alias-label-secondary,#545557);font-size:11.5px}',
      '.dshEm_legendItem{display:inline-flex;align-items:center;gap:5px}',
      '.dshEm_swatch{width:8px;height:8px;border-radius:2px;flex:none}',
      '.dshEm_timeline{display:flex;align-items:flex-end;gap:2px;height:76px;padding-top:2px}',
      '.dshEm_col{flex:1 1 0;min-width:2px;border-radius:2px 2px 0 0;background:var(--dsw-alias-state-idle-primary,#a2a4a6)}',
      '.dshEm_spark{display:block;width:100%;height:52px}',
      '.dshEm_columns{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:10px;align-items:start}',
      '.dshEm_table{width:100%;border-collapse:collapse;table-layout:fixed}',
      '.dshEm_table th{text-align:left;font-weight:500;font-size:11px;letter-spacing:.04em;text-transform:uppercase;color:var(--dsw-alias-label-tertiary,#a2a4a6);padding:2px 8px 4px 0}',
      '.dshEm_table td{padding:5px 8px 5px 0;border-top:.5px solid var(--dsw-alias-border-l1,#ededed);vertical-align:top;word-break:break-word}',
      '.dshEm_mono{font-family:var(--ds-font-family-code,ui-monospace,Consolas,monospace);font-size:11.5px}',
      '.dshEm_num{font-variant-numeric:tabular-nums;color:var(--dsw-alias-label-secondary,#545557);white-space:nowrap}',
      '.dshEm_state{display:inline-flex;align-items:center;gap:5px;white-space:nowrap}',
      '.dshEm_emptyState{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;min-height:180px;color:var(--dsw-alias-label-tertiary,#a2a4a6)}',
      '.dshEm_scroll{max-height:340px;overflow:auto}',
      '@media (prefers-reduced-motion:reduce){.dshEm_root *{transition:none !important;animation:none !important}}',
    ].join('') + SHARED_CSS + CHECKLIST_CSS

    const STRIP_CSS = [
      '.dshEm_strip{display:flex;flex:1 1 auto;align-items:center;gap:9px;box-sizing:border-box;width:100%;min-width:0;height:28px;padding:0 10px;border:.5px solid var(--dsw-alias-border-l2,#e5e5e5);border-radius:var(--dsw-radius-sm,8px);background:var(--dsw-alias-bg-layer-2,#f5f5f5);color:var(--dsw-alias-label-secondary,#545557);font-family:var(--dsw-font-family,system-ui);font-size:12px;font-variant-numeric:tabular-nums;overflow:hidden}',
      '.dshEm_stripLabel{color:var(--dsw-alias-label-primary,#0f0f0f);font-weight:500;white-space:nowrap}',
      '.dshEm_track{flex:none;width:76px;height:6px;border-radius:999px;overflow:hidden;background:var(--dsw-alias-border-l1,#ededed)}',
      '.dshEm_fill{height:100%;border-radius:999px;background:var(--dsw-alias-brand-primary,#4176e6);transition:width .3s ease}',
      '.dshEm_stripSummary{color:var(--dsw-alias-label-secondary,#545557);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
      '.dshEm_badge{display:inline-flex;align-items:center;height:18px;padding:0 6px;border-radius:999px;background:var(--dsw-alias-state-error-primary,#ef4444);color:#fff;font-size:11px;font-weight:600}',
      '.dshEm_spacer{flex:1 1 auto;min-width:0}',
    ].join('') + SHARED_CSS

    /** The floating frame both widgets share: shell, head, fold control. */
    const WIDGET_SHELL_CSS = [
      '.dshEm_widget{position:absolute;z-index:30;display:flex;flex-direction:column;width:364px;max-height:66vh;overflow:hidden;pointer-events:auto;border:.5px solid var(--dsw-alias-border-l3,#dcdcdc);border-radius:var(--dsw-radius-lg,16px);background:var(--dsw-alias-bg-overlay,#fff);box-shadow:var(--dsw-elevation-prominent,0 4px 16px rgba(0,0,0,.12));color:var(--dsw-alias-label-primary,#0f0f0f);font-family:var(--dsw-font-family,system-ui);font-size:12px;line-height:16px}',
      '.dshEm_widget *{box-sizing:border-box}',
      '.dshEm_widgetHead{display:flex;align-items:center;gap:8px;padding:8px 10px;cursor:grab;touch-action:none;user-select:none;border-bottom:.5px solid var(--dsw-alias-border-l2,#e5e5e5)}',
      '.dshEm_widget--collapsed .dshEm_widgetHead{border-bottom:0}',
      '.dshEm_widgetTitle{font-weight:600;white-space:nowrap}',
      '.dshEm_widgetPct{font-variant-numeric:tabular-nums;color:var(--dsw-alias-label-secondary,#545557)}',
      '.dshEm_widgetBody{display:flex;flex-direction:column;gap:10px;padding:10px;overflow:auto;min-height:0}',
      '.dshEm_widgetRow{display:flex;align-items:center;gap:6px;flex-wrap:wrap;color:var(--dsw-alias-label-secondary,#545557)}',
      '.dshEm_chip{display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 7px;border-radius:999px;background:var(--dsw-alias-bg-module-platform,var(--dsw-alias-bg-layer-2,#f5f5f5));font-variant-numeric:tabular-nums;white-space:nowrap}',
      '.dshEm_iconBtn{display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;flex:none;border:0;border-radius:var(--dsw-radius-xs,4px);background:transparent;color:var(--dsw-alias-label-secondary,#545557);cursor:pointer;font-size:13px;line-height:1}',
      '.dshEm_iconBtn:hover{background:var(--dsw-alias-interactive-bg-hover,rgba(0,0,0,.05));color:var(--dsw-alias-label-primary,#0f0f0f)}',
      '.dshEm_iconBtn:focus-visible{outline:var(--dsw-focus-ring-width,2px) solid var(--dsw-focus-ring-color,var(--dsw-alias-state-business-primary,#4176e6));outline-offset:1px}',
      '.dshEm_widget .dshEm_card{padding:8px 10px;gap:5px}',
    ].join('')

    /** The execution monitor's floating widget. */
    const WIDGET_CSS = WIDGET_SHELL_CSS + SHARED_CSS + CHECKLIST_CSS + [
      '.dshEm_widgetSection{display:flex;flex-direction:column;gap:5px;min-width:0}',
      '.dshEm_widgetSectionTitle{color:var(--dsw-alias-label-secondary,#545557);font-size:11px;letter-spacing:.04em;text-transform:uppercase}',
      '.dshEm_widgetTimeline{display:flex;align-items:flex-end;gap:2px;height:34px}',
      '.dshEm_widgetEmpty{color:var(--dsw-alias-label-tertiary,#a2a4a6)}',
    ].join('')

    /** The Supabase MCP widget: call list, status codes and the detail panel. */
    const SUPABASE_CSS = WIDGET_SHELL_CSS + SHARED_CSS + [
      '.dshEm_supaList{display:flex;flex-direction:column;gap:2px;max-height:280px;overflow:auto}',
      '.dshEm_supaRow{display:flex;align-items:center;gap:6px;width:100%;padding:4px 6px;border:0;border-radius:var(--dsw-radius-xs,4px);background:transparent;color:inherit;font:inherit;text-align:left;cursor:pointer}',
      '.dshEm_supaRow:hover{background:var(--dsw-alias-interactive-bg-hover,rgba(0,0,0,.05))}',
      '.dshEm_supaRow[aria-expanded=true]{background:var(--dsw-alias-bg-module-platform,var(--dsw-alias-bg-layer-2,#f5f5f5))}',
      '.dshEm_supaRow:focus-visible{outline:var(--dsw-focus-ring-width,2px) solid var(--dsw-focus-ring-color,var(--dsw-alias-state-business-primary,#4176e6));outline-offset:-1px}',
      '.dshEm_code{display:inline-flex;align-items:center;justify-content:center;min-width:34px;height:18px;padding:0 6px;border-radius:999px;font-size:11px;font-weight:600;color:#fff;font-variant-numeric:tabular-nums}',
      '.dshEm_tag{display:inline-flex;align-items:center;height:18px;padding:0 6px;border-radius:999px;font-size:10.5px;text-transform:uppercase;letter-spacing:.04em;background:var(--dsw-alias-bg-module-platform,var(--dsw-alias-bg-layer-2,#f5f5f5));color:var(--dsw-alias-label-secondary,#545557)}',
      '.dshEm_tool{font-family:var(--ds-font-family-code,ui-monospace,Consolas,monospace);font-size:11.5px;white-space:nowrap}',
      '.dshEm_supaText{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--dsw-alias-label-secondary,#545557);font-size:11.5px}',
      '.dshEm_supaTime{flex:none;color:var(--dsw-alias-label-tertiary,#a2a4a6);font-size:11px;font-variant-numeric:tabular-nums}',
      '.dshEm_pre{margin:0;padding:8px;max-height:200px;overflow:auto;border-radius:var(--dsw-radius-sm,8px);background:var(--dsw-alias-bg-layer-1,#fff);border:.5px solid var(--dsw-alias-border-l2,#e5e5e5);font-family:var(--ds-font-family-code,ui-monospace,Consolas,monospace);font-size:11px;line-height:15px;white-space:pre-wrap;word-break:break-word}',
      '.dshEm_detail{display:flex;flex-direction:column;gap:6px;padding:8px;border-radius:var(--dsw-radius-sm,8px);background:var(--dsw-alias-bg-layer-2,#f5f5f5);border:.5px solid var(--dsw-alias-border-l2,#e5e5e5)}',
      '.dshEm_detailHead{display:flex;align-items:center;gap:6px;flex-wrap:wrap}',
      '.dshEm_metaRow{display:flex;flex-wrap:wrap;gap:8px;color:var(--dsw-alias-label-tertiary,#a2a4a6);font-size:11px;font-variant-numeric:tabular-nums}',
      '.dshEm_toggle{display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 8px;border:.5px solid var(--dsw-alias-border-l2,#e5e5e5);border-radius:999px;background:transparent;color:var(--dsw-alias-label-secondary,#545557);font:inherit;font-size:11.5px;cursor:pointer}',
      '.dshEm_toggle[aria-pressed=true]{background:var(--dsw-alias-bg-module-platform,var(--dsw-alias-bg-layer-2,#f5f5f5));color:var(--dsw-alias-label-primary,#0f0f0f);border-color:var(--dsw-alias-border-l3,#dcdcdc)}',
      '.dshEm_toggle:focus-visible{outline:var(--dsw-focus-ring-width,2px) solid var(--dsw-focus-ring-color,var(--dsw-alias-state-business-primary,#4176e6));outline-offset:1px}',
      '.dshEm_resScroll{max-height:220px;overflow:auto;border-radius:var(--dsw-radius-xs,4px);background:var(--dsw-alias-bg-layer-1,#fff)}',
      '.dshEm_resTable{width:100%;border-collapse:collapse;font-size:11px}',
      '.dshEm_resTable th{position:sticky;top:0;background:var(--dsw-alias-bg-layer-1,#fff);text-align:left;font-weight:500;color:var(--dsw-alias-label-tertiary,#a2a4a6);padding:3px 6px 3px 0;white-space:nowrap}',
      '.dshEm_resTable td{padding:3px 6px 3px 0;border-top:.5px solid var(--dsw-alias-border-l1,#ededed);max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
    ].join('')

    //#endregion

    //#region components

    /** The completion ring. */
    function Ring(props) {
      const clamped = Math.max(0, Math.min(100, Math.round(props.pct)))
      const radius = 34
      const circumference = 2 * Math.PI * radius
      return h('svg', {
        viewBox: '0 0 88 88',
        width: 88,
        height: 88,
        role: 'img',
        'aria-label': props.caption,
        style: { flex: 'none' },
      },
      h('circle', {
        cx: 44, cy: 44, r: radius, fill: 'none', strokeWidth: 8,
        style: { stroke: 'var(--dsw-alias-border-l2, #e5e5e5)' },
      }),
      h('circle', {
        cx: 44, cy: 44, r: radius, fill: 'none', strokeWidth: 8, strokeLinecap: 'round',
        strokeDasharray: String(circumference),
        strokeDashoffset: String(circumference * (1 - clamped / 100)),
        transform: 'rotate(-90 44 44)',
        style: {
          stroke: clamped > 0 && props.failed > 0 ? 'var(--dsw-alias-state-warn-primary, #f59e0b)' : 'var(--dsw-alias-brand-primary, #4176e6)',
          transition: 'stroke-dashoffset .3s ease',
        },
      }),
      h('text', {
        x: 44, y: 49, textAnchor: 'middle',
        style: {
          fill: 'var(--dsw-alias-label-primary, #0f0f0f)',
          fontSize: '17px',
          fontWeight: 600,
          fontVariantNumeric: 'tabular-nums',
          fontFamily: 'inherit',
        },
      }, clamped + '%'))
    }

    /** Outcome mix bar with its legend. */
    function MixBar(props) {
      const counts = props.counts
      const total = counts.total
      const segment = (amount, token, key) => {
        if (total === 0 || amount === 0) return null
        return h('div', { key, className: 'dshEm_seg', style: { width: (amount / total) * 100 + '%', background: token } })
      }
      const legend = (key, amount, token) => h('span', { key, className: 'dshEm_legendItem' },
        h('span', { className: 'dshEm_swatch', style: { background: token } }),
        props.t(key) + ' ' + amount)
      return h('div', { className: 'dshEm_card' },
        h('div', { className: 'dshEm_cardLabel' }, props.t('chart.mix')),
        h('div', { className: 'dshEm_bar', role: 'img', 'aria-label': props.t('aria.mix') },
          segment(counts.ok, statusColor('ok'), 'ok'),
          segment(counts.failed, statusColor('failed'), 'failed'),
          segment(counts.running, statusColor('running'), 'running'),
          segment(counts.incomplete, statusColor('incomplete'), 'incomplete')),
        h('div', { className: 'dshEm_legend' },
          legend('legend.ok', counts.ok, statusColor('ok')),
          legend('legend.failed', counts.failed, statusColor('failed')),
          legend('legend.running', counts.running, statusColor('running')),
          legend('legend.incomplete', counts.incomplete, statusColor('incomplete'))))
    }

    /** One bar per tool call, height by duration, colour by outcome. */
    function Timeline(props) {
      const now = props.now
      const bars = props.bars
      let max = 0
      for (const bar of bars) {
        const seconds = bar.seconds === null ? 0 : bar.seconds
        if (seconds > max) max = seconds
      }
      if (max <= 0) max = 1
      return h('div', { className: 'dshEm_card' },
        h('div', { className: 'dshEm_cardLabel' }, props.t('chart.timeline')),
        h('div', { className: 'dshEm_timeline', role: 'img', 'aria-label': props.t('aria.timeline') },
          bars.map((bar, index) => {
            let seconds = bar.seconds
            if (seconds === null && bar.status === 'running' && bar.startedAt !== null) {
              seconds = Math.max(0, (now - bar.startedAt) / 1000)
            }
            const ratio = Math.min(1, (seconds === null ? 0 : seconds) / max)
            return h('div', {
              key: bar.id + ':' + index,
              className: 'dshEm_col',
              style: { height: 6 + Math.round(62 * ratio) + 'px', background: statusColor(bar.status) },
              title: (bar.name === null ? props.t('kind.request') : bar.name) + ' · ' + props.t('legend.' + bar.status) + ' · ' + formatSeconds(seconds, props.t),
            })
          })),
        h('div', { className: 'dshEm_hint' }, props.t('chart.timelineHint')))
    }

    /** Output tokens per assistant response. */
    function TokenSpark(props) {
      const series = props.series
      let max = 0
      for (const value of series) if (value > max) max = value
      if (series.length < 2 || max <= 0) return null
      const width = 260
      const height = 52
      const step = width / (series.length - 1)
      const points = series.map((value, index) => [
        index * step,
        height - 4 - (value / max) * (height - 12),
      ])
      let line = ''
      for (let index = 0; index < points.length; index++) {
        const point = points[index]
        line += (index === 0 ? 'M' : 'L') + point[0].toFixed(1) + ' ' + point[1].toFixed(1)
      }
      const area = line + ' L' + width + ' ' + height + ' L0 ' + height + ' Z'
      return h('div', { className: 'dshEm_card' },
        h('div', { className: 'dshEm_cardLabel' }, props.t('chart.tokens')),
        h('svg', {
          viewBox: '0 0 ' + width + ' ' + height,
          preserveAspectRatio: 'none',
          className: 'dshEm_spark',
          role: 'img',
          'aria-label': props.t('aria.tokens'),
        },
        h('path', { d: area, style: { fill: 'color-mix(in srgb, var(--dsw-alias-brand-primary, #4176e6) 16%, transparent)' } }),
        h('path', { d: line, fill: 'none', strokeWidth: 1.5, style: { stroke: 'var(--dsw-alias-brand-primary, #4176e6)' } })))
    }

    /** A labelled number. */
    function StatCard(props) {
      return h('div', { className: 'dshEm_card' },
        h('div', { className: 'dshEm_cardLabel' }, props.label),
        h('div', { className: 'dshEm_big' + (props.tone === undefined ? '' : ' ' + props.tone) }, props.value),
        props.hint === undefined ? null : h('div', { className: 'dshEm_hint' }, props.hint))
    }

    /** The failures table. */
    function FailuresTable(props) {
      const t = props.t
      const rows = props.failures
      if (rows.length === 0) {
        return h('div', { className: 'dshEm_card' },
          h('div', { className: 'dshEm_cardLabel' }, t('list.failures')),
          h('div', { className: 'dshEm_hint' }, t('empty.failures')))
      }
      const body = rows.slice(0, 40).map((row, index) => {
        const state = h('span', { className: 'dshEm_state' },
          h('span', { className: 'dshEm_swatch', style: { background: statusColor('failed') } }),
          h('span', { className: 'dshEm_mono' }, row.name === null ? t('kind.request') : row.name))
        const message = h('span', { className: 'dshEm_mono dshEm_errorText' },
          row.error === null ? t('legend.failed') : row.error)
        return h('tr', { key: row.id + ':' + index },
          h('td', null, state),
          h('td', { className: 'dshEm_num' }, row.turn + ' / ' + row.step),
          h('td', null, message))
      })
      const table = h('table', { className: 'dshEm_table' },
        h('thead', null, h('tr', null,
          h('th', { style: { width: '26%' } }, t('table.tool')),
          h('th', { style: { width: '14%' } }, t('table.where')),
          h('th', null, t('table.error')))),
        h('tbody', null, body))
      return h('div', { className: 'dshEm_card' },
        h('div', { className: 'dshEm_cardLabel' }, t('list.failures')),
        h('div', { className: 'dshEm_scroll' }, table))
    }

    /** The most recent tool calls. */
    function ActivityTable(props) {
      const t = props.t
      const rows = props.rows
      if (rows.length === 0) {
        return h('div', { className: 'dshEm_card' },
          h('div', { className: 'dshEm_cardLabel' }, t('list.activity')),
          h('div', { className: 'dshEm_hint' }, t('empty.activity')))
      }
      const body = rows.map((row, index) => {
        const name = h('span', { className: 'dshEm_mono' }, row.name === null ? t('kind.request') : row.name)
        const state = h('span', { className: 'dshEm_state' },
          h('span', { className: 'dshEm_swatch', style: { background: statusColor(row.status) } }),
          t('legend.' + row.status))
        return h('tr', { key: row.id + ':' + index },
          h('td', null, name),
          h('td', null, state),
          h('td', { className: 'dshEm_num' }, formatSeconds(row.seconds, t)))
      })
      const table = h('table', { className: 'dshEm_table' },
        h('thead', null, h('tr', null,
          h('th', { style: { width: '44%' } }, t('table.tool')),
          h('th', { style: { width: '26%' } }, t('table.status')),
          h('th', null, t('table.duration')))),
        h('tbody', null, body))
      return h('div', { className: 'dshEm_card' },
        h('div', { className: 'dshEm_cardLabel' }, t('list.activity')),
        h('div', { className: 'dshEm_scroll' }, table))
    }

    /** Checklist glyph for one row state. */
    function stateGlyph(state) {
      if (state === 'done') return '✓'
      if (state === 'active') return '●'
      if (state === 'skipped') return '⚠'
      return '○'
    }

    /** One checklist row, with its state exposed to assistive technology. */
    function ChecklistRow(props) {
      const row = props.row
      return h('li', { className: 'dshEm_item dshEm_item--' + row.state },
        h('span', { className: 'dshEm_mark dshEm_mark--' + row.state, 'aria-hidden': true }, stateGlyph(row.state)),
        h('span', { className: 'dshEm_itemText' }, row.content),
        h('span', { className: 'dshEm_sr' }, props.t('state.' + row.state)))
    }

    /** The plan checklist: done rows are struck through, pending rows are what is left. */
    function ChecklistCard(props) {
      const t = props.t
      const checklist = props.checklist
      const limit = props.limit === undefined ? checklist.rows.length : props.limit
      const rows = checklist.rows.slice(0, limit)
      const hidden = checklist.rows.length - rows.length
      return h('div', { className: 'dshEm_card dshEm_check' },
        h('div', { className: 'dshEm_cardLabel' }, t('checklist.title')),
        checklist.total === 0
          ? h('div', { className: 'dshEm_hint' }, t('checklist.empty'))
          : [
            h('div', { key: 'progress', className: 'dshEm_progressRow' },
              h('span', { className: 'dshEm_track', style: { width: '84px' } },
                h('span', {
                  className: 'dshEm_fill',
                  style: { width: checklist.completion + '%', background: 'var(--dsw-alias-state-success-primary, #22c55e)' },
                })),
              h('span', null, t('checklist.progress', { done: checklist.done, total: checklist.total })),
              checklist.active > 0 ? h('span', null, t('state.active') + ' ' + checklist.active) : null,
              checklist.pending > 0 ? h('span', null, t('state.pending') + ' ' + checklist.pending) : null),
            h('ul', { key: 'items', className: 'dshEm_items' },
              rows.map((row) => h(ChecklistRow, { key: row.key, row, t }))),
            hidden > 0 ? h('div', { key: 'more', className: 'dshEm_hint' }, t('activity.more', { count: hidden })) : null,
          ])
    }

    /** Items that left the plan unfinished: the warning surface. */
    function WarningsCard(props) {
      const t = props.t
      const skipped = props.checklist.skipped
      const limit = props.limit === undefined ? 12 : props.limit
      const rows = skipped.slice(0, limit)
      if (rows.length === 0) {
        return h('div', { className: 'dshEm_card dshEm_check' },
          h('div', { className: 'dshEm_cardLabel' }, t('warnings.title')),
          h('div', { className: 'dshEm_hint' }, t('warnings.empty')))
      }
      return h('div', { className: 'dshEm_card dshEm_check' },
        h('div', { className: 'dshEm_cardLabel' }, t('warnings.title')),
        h('div', { className: 'dshEm_hint' }, t('warnings.hint')),
        h('ul', { className: 'dshEm_items' }, rows.map((row) => h(ChecklistRow, { key: row.key, row, t }))))
    }

    /**
     * The full monitor surface, registered as a Conversation View.
     * @param props - standard Session slot props plus the framework `t` seat.
     */
    function MonitorView(props) {
      const t = typeof props.t === 'function' ? props.t : fallbackT
      const inputs = useMonitorInputs(props)
      const stats = inputs.stats
      const now = useNow(inputs.running)

      const statusKey = stats.calls.failed + stats.requests.error > 0
        ? 'status.failed'
        : inputs.running
          ? 'status.running'
          : stats.hasData ? 'status.idle' : 'status.empty'
      const statusTone = stats.calls.failed + stats.requests.error > 0 ? statusColor('failed') : inputs.running ? statusColor('running') : statusColor('incomplete')
      const reference = inputs.running ? now : (stats.lastAt === null ? now : stats.lastAt)
      const elapsed = stats.firstAt === null ? 0 : Math.max(0, reference - stats.firstAt)
      const totalFailures = stats.calls.failed + stats.requests.error

      const header = h('div', { className: 'dshEm_header' },
        h('div', { className: 'dshEm_titleRow' },
          h('span', { className: 'dshEm_dot', style: { background: statusTone } }),
          h('span', { className: 'dshEm_title' }, t('panel.title')),
          h('span', { className: 'dshEm_pill' }, t(statusKey)),
          h('span', { className: 'dshEm_pill' }, t('turn.step', { turn: stats.turn, step: stats.step }))),
        h('div', { className: 'dshEm_titleRow' },
          h('span', { className: 'dshEm_pill' }, t('kpi.elapsed') + ' ' + formatClock(elapsed)),
          stats.averageSeconds === null ? null : h('span', { className: 'dshEm_pill' }, formatSeconds(stats.averageSeconds, t))))

      const body = stats.hasData
        ? [
          h('div', { key: 'grid', className: 'dshEm_grid' },
            h('div', { className: 'dshEm_card dshEm_ringCard' },
              h(Ring, { pct: stats.completion, failed: totalFailures, caption: t('aria.ring', { pct: stats.completion }) }),
              h('div', { style: { display: 'flex', flexDirection: 'column', gap: '6px', minWidth: 0 } },
                h('div', { className: 'dshEm_cardLabel' }, t('kpi.completion')),
                h('div', { className: 'dshEm_hint' }, t('kpi.completionHint')),
                h('div', { className: 'dshEm_hint' }, t('kpi.errorRate', { pct: stats.errorRate })))),
            h(StatCard, {
              label: t('kpi.tools'),
              value: t('kpi.count', { done: stats.calls.ok + stats.calls.failed, total: stats.calls.total }),
              hint: t('legend.ok') + ' ' + stats.calls.ok + ' · ' + t('legend.failed') + ' ' + stats.calls.failed + ' · ' + t('legend.running') + ' ' + stats.calls.running,
            }),
            h(StatCard, {
              label: t('kpi.requests'),
              value: t('kpi.count', { done: stats.requests.done, total: stats.requests.total }),
              hint: t('legend.running') + ' ' + stats.requests.running + ' · ' + t('legend.failed') + ' ' + stats.requests.error,
            }),
            h(StatCard, {
              label: t('kpi.failures'),
              value: String(totalFailures),
              tone: totalFailures > 0 ? 'dshEm_errorText' : undefined,
              hint: t('kpi.errorRate', { pct: stats.errorRate }),
            }),
            h(StatCard, {
              label: t('kpi.tokens'),
              value: stats.tokens === null ? '—' : formatCompact(stats.tokens.input + stats.tokens.output),
              hint: stats.tokens === null
                ? t('empty.session')
                : t('kpi.tokensValue', { input: formatCompact(stats.tokens.input), output: formatCompact(stats.tokens.output) }),
            })),
          h('div', { key: 'charts', className: 'dshEm_columns' },
            h(MixBar, { counts: stats.calls, t }),
            h(Timeline, { bars: stats.timeline, now, t })),
          stats.tokens === null ? null : h(TokenSpark, { key: 'spark', series: stats.tokenSeries, t }),
          h('div', { key: 'plan', className: 'dshEm_columns' },
            h(ChecklistCard, { checklist: inputs.checklist, t }),
            h(WarningsCard, { checklist: inputs.checklist, t })),
          h('div', { key: 'lists', className: 'dshEm_columns' },
            h(ActivityTable, { rows: stats.recent, t }),
            h(FailuresTable, { failures: stats.failures, t })),
        ]
        : h('div', { className: 'dshEm_emptyState' },
          h('div', { className: 'dshEm_title' }, t('panel.title')),
          h('div', { className: 'dshEm_hint' }, t('empty.session')))

      return h(React.Fragment, null,
        h('style', { key: 'css' }, BASE_CSS),
        h('div', { className: 'dshEm_root' }, header, body))
    }

    /**
     * The always-visible compact strip, registered in the input dock.
     * @param props - standard Session slot props plus the framework `t` seat.
     */
    function MonitorStrip(props) {
      const t = typeof props.t === 'function' ? props.t : fallbackT
      const inputs = useMonitorInputs(props)
      const stats = inputs.stats
      if (!stats.hasData) return null
      const totalFailures = stats.calls.failed + stats.requests.error
      const tone = totalFailures > 0 ? statusColor('failed') : inputs.running ? statusColor('running') : statusColor('incomplete')
      return h(React.Fragment, null,
        h('style', { key: 'css' }, STRIP_CSS),
        h('div', {
          className: 'dshEm_strip',
          role: 'status',
          'aria-label': t('strip.summary', { ok: stats.calls.ok, failed: totalFailures, running: stats.calls.running }),
        },
        h('span', { className: 'dshEm_dot', style: { background: tone } }),
        h('span', { className: 'dshEm_stripLabel' }, t('strip.label')),
        h('span', { className: 'dshEm_track' },
          h('span', {
            className: 'dshEm_fill',
            style: {
              width: stats.completion + '%',
              background: tone,
              display: 'block',
            },
          })),
        h('span', null, stats.completion + '%'),
        h('span', { className: 'dshEm_stripSummary' }, t('strip.summary', {
          ok: stats.calls.ok,
          failed: stats.calls.failed,
          running: stats.calls.running,
        })),
        h('span', { className: 'dshEm_spacer' }),
        stats.turn > 0 ? h('span', null, t('turn.step', { turn: stats.turn, step: stats.step })) : null,
        totalFailures > 0 ? h('span', { className: 'dshEm_badge' }, String(totalFailures)) : null))
    }

    //#endregion

    //#region floating widget

    /**
     * The floating frame-wide widget. A root-scoped entry receives no Session
     * props, so it follows the main Session binding and reads that binding's own
     * hook shares — the same live Trajectory and plan the Session slots receive.
     * Dragging and folding are plugin-owned view state, remembered per browser.
     * @param props - root slot props plus the injected main-Session hook and resolver.
     */
    /**
     * Plugin-owned view state for one floating widget: placement, dragging and
     * folding, remembered per browser under its own storage key.
     * @param storageKey - localStorage key this widget owns.
     * @param placement - starting corner when nothing is stored.
     * @returns the layout plus the pointer handlers the frame wires up.
     */
    function useFloatingLayout(storageKey, placement) {
      const [layout, setLayout] = React.useState(() => loadWidgetLayout(storageKey, placement))
      const layoutRef = React.useRef(layout)
      layoutRef.current = layout
      const dragRef = React.useRef(null)

      const startDrag = (event) => {
        if (event === null || event === undefined) return
        if (typeof event.button === 'number' && event.button !== 0) return
        const current = layoutRef.current
        dragRef.current = { x: event.clientX, y: event.clientY, originX: current.x, originY: current.y }
        const target = event.currentTarget
        if (target !== null && target !== undefined && typeof target.setPointerCapture === 'function') {
          try {
            target.setPointerCapture(event.pointerId)
          } catch (error) {
            /* capture is best effort: the move handler follows the pointer anyway */
          }
        }
      }
      const moveDrag = (event) => {
        const active = dragRef.current
        if (active === null) return
        const clamped = clampLayout(active.originX + (event.clientX - active.x), active.originY + (event.clientY - active.y))
        const current = layoutRef.current
        if (current.x === clamped.x && current.y === clamped.y) return
        const next = { x: clamped.x, y: clamped.y, collapsed: current.collapsed }
        layoutRef.current = next
        setLayout(next)
      }
      const endDrag = () => {
        if (dragRef.current === null) return
        dragRef.current = null
        saveWidgetLayout(storageKey, layoutRef.current)
      }
      const toggleCollapsed = () => {
        const current = layoutRef.current
        const next = { x: current.x, y: current.y, collapsed: current.collapsed !== true }
        layoutRef.current = next
        saveWidgetLayout(storageKey, next)
        setLayout(next)
      }

      return { layout, folded: layout.collapsed === true, startDrag, moveDrag, endDrag, toggleCollapsed }
    }

    /** The draggable, foldable frame both floating widgets render inside. */
    function FloatingFrame(props) {
      const folded = props.layout.collapsed === true
      // Re-clamp while rendering so a resized window cannot strand the widget.
      const placed = clampLayout(props.layout.x, props.layout.y)
      const foldLabel = folded ? props.expandLabel : props.minimizeLabel
      return h(React.Fragment, null,
        h('style', { key: 'css' }, props.css),
        h('div', {
          key: 'frame',
          className: 'dshEm_widget' + (folded ? ' dshEm_widget--collapsed' : ''),
          style: { left: Math.round(placed.x) + 'px', top: Math.round(placed.y) + 'px' },
          role: 'complementary',
          'aria-label': props.label,
        },
        h('div', {
          className: 'dshEm_widgetHead',
          onPointerDown: props.startDrag,
          onPointerMove: props.moveDrag,
          onPointerUp: props.endDrag,
          onPointerCancel: props.endDrag,
          title: props.dragTitle,
        },
        h('span', { className: 'dshEm_dot', style: { background: props.tone } }),
        h('span', { className: 'dshEm_widgetTitle' }, props.title),
        h('span', { className: 'dshEm_widgetPct' }, props.headline),
        h('span', { className: 'dshEm_spacer' }),
        folded && props.foldedExtras !== undefined ? props.foldedExtras : null,
        h('button', {
          type: 'button',
          className: 'dshEm_iconBtn',
          onPointerDown: (event) => event.stopPropagation(),
          onClick: props.toggleCollapsed,
          'aria-expanded': folded ? 'false' : 'true',
          'aria-label': foldLabel,
          title: foldLabel,
        }, folded ? '▢' : '–')),
        folded ? null : props.children))
    }

    function MonitorWidget(props) {
      const t = typeof props.t === 'function' ? props.t : fallbackT
      const useMainSafe = typeof props.useMainSession === 'function' ? props.useMainSession : useEmptyMain
      const useStatusSafe = typeof props.useSessionStatus === 'function' ? props.useSessionStatus : useEmptyBoolean
      const resolveSources = typeof props.resolveSources === 'function' ? props.resolveSources : resolveNoSources

      const mainValue = useMainSafe(selectMainValue)
      const sources = resolveSources(mainValue)
      const trajectory = React.useSyncExternalStore(sources.trajectory.subscribe, sources.trajectory.getSnapshot, sources.trajectory.getSnapshot)
      const todos = React.useSyncExternalStore(sources.todos.subscribe, sources.todos.getSnapshot, sources.todos.getSnapshot)
      const sessionId = mainValue === null || mainValue === undefined || mainValue.key === undefined ? undefined : String(mainValue.key)
      const selectRunning = React.useCallback(
        (statuses) => {
          if (sessionId === undefined) return false
          if (statuses === null || statuses === undefined || typeof statuses.get !== 'function') return false
          return statuses.get(sessionId)?.running === true
        },
        [sessionId],
      )
      const running = useStatusSafe(selectRunning)
      const stats = React.useMemo(() => deriveMonitor(trajectory, running), [trajectory, running])
      const skipped = React.useMemo(() => trackTodos(sessionId, todos), [sessionId, todos])
      const checklist = React.useMemo(() => deriveChecklist(todos, skipped), [todos, skipped])
      const now = useNow(running)

      const floating = useFloatingLayout(WIDGET_STORAGE_KEY, 'top-right')

      const folded = floating.folded
      const totalFailures = stats.calls.failed + stats.requests.error
      const tone = totalFailures > 0 ? statusColor('failed') : running ? statusColor('running') : statusColor('incomplete')
      const statusKey = totalFailures > 0 ? 'status.failed' : running ? 'status.running' : stats.hasData ? 'status.idle' : 'status.empty'
      const reference = running ? now : (stats.lastAt === null ? now : stats.lastAt)
      const elapsed = stats.firstAt === null ? 0 : Math.max(0, reference - stats.firstAt)
      const timeline = stats.timeline.slice(-24)

      // What a folded widget still shows: the plan progress and the failure count.
      const foldedExtras = [
        checklist.total > 0
          ? h('span', { key: 'plan', className: 'dshEm_chip' }, t('checklist.progress', { done: checklist.done, total: checklist.total }))
          : null,
        totalFailures > 0 ? h('span', { key: 'fail', className: 'dshEm_badge' }, String(totalFailures)) : null,
      ]

      const body = h('div', { className: 'dshEm_widgetBody' },
        h('div', { className: 'dshEm_widgetRow' },
          h('span', null, t(statusKey)),
          h('span', null, t('turn.step', { turn: stats.turn, step: stats.step })),
          h('span', null, t('kpi.elapsed') + ' ' + formatClock(elapsed))),
        h('div', { className: 'dshEm_widgetRow' },
          h('span', { className: 'dshEm_chip' }, t('kpi.tools') + ' ' + t('kpi.count', { done: stats.calls.ok + stats.calls.failed, total: stats.calls.total })),
          h('span', { className: 'dshEm_chip' }, t('legend.failed') + ' ' + totalFailures),
          h('span', { className: 'dshEm_chip' }, t('legend.running') + ' ' + stats.calls.running),
          stats.tokens === null
            ? null
            : h('span', { className: 'dshEm_chip' }, formatCompact(stats.tokens.input + stats.tokens.output) + ' ' + t('kpi.tokens'))),
        timeline.length === 0
          ? null
          : h('div', { className: 'dshEm_widgetTimeline', role: 'img', 'aria-label': t('aria.timeline') },
            timeline.map((bar, index) => {
              let seconds = bar.seconds
              if (seconds === null && bar.status === 'running' && bar.startedAt !== null) {
                seconds = Math.max(0, (now - bar.startedAt) / 1000)
              }
              return h('div', {
                key: bar.id + ':' + index,
                className: 'dshEm_col',
                style: { height: barHeight(seconds, timeline) + 'px', background: statusColor(bar.status) },
                title: (bar.name === null ? t('kind.request') : bar.name) + ' · ' + t('legend.' + bar.status),
              })
            })),
        h('div', { className: 'dshEm_widgetSection' }, h(ChecklistCard, { checklist, t, limit: 12 })),
        h('div', { className: 'dshEm_widgetSection' }, h(WarningsCard, { checklist, t, limit: 6 })),
        stats.failures.length === 0
          ? null
          : h('div', { className: 'dshEm_widgetSection' },
            h('div', { className: 'dshEm_widgetSectionTitle' }, t('list.failures')),
            stats.failures.slice(0, 3).map((failure, index) => h('div', {
              key: failure.id + ':' + index,
              className: 'dshEm_mono dshEm_errorText',
            }, (failure.name === null ? t('kind.request') : failure.name) + ' — ' + (failure.error === null ? t('legend.failed') : failure.error)))))

      return h(FloatingFrame, {
        css: WIDGET_CSS,
        label: t('widget.aria'),
        dragTitle: t('widget.drag'),
        title: t('panel.title'),
        headline: stats.completion + '%',
        tone,
        foldedExtras,
        expandLabel: t('widget.expand'),
        minimizeLabel: t('widget.minimize'),
        layout: floating.layout,
        startDrag: floating.startDrag,
        moveDrag: floating.moveDrag,
        endDrag: floating.endDrag,
        toggleCollapsed: floating.toggleCollapsed,
      }, body)
    }

    /** Cell text for a response table. */
    function cellText(value) {
      if (value === null) return 'null'
      if (value === undefined) return ''
      if (typeof value === 'string') return value
      if (typeof value === 'number' || typeof value === 'boolean') return String(value)
      try {
        return JSON.stringify(value)
      } catch (error) {
        return String(value)
      }
    }

    /** One Supabase call row: status code, kind, tool, SQL preview and duration. */
    function SupabaseRow(props) {
      const t = props.t
      const entry = props.entry
      // A failed call with no SQL shows what went wrong instead of "no SQL".
      const preview = entry.sql !== null
        ? entry.sql.replace(/\s+/g, ' ').trim()
        : (entry.errorText === null ? t('supa.noSql') : entry.errorText.replace(/\s+/g, ' ').trim())
      return h('button', {
        type: 'button',
        className: 'dshEm_supaRow',
        'aria-expanded': props.selected ? 'true' : 'false',
        title: preview,
        onClick: () => props.onSelect(entry.id),
      },
      h('span', {
        className: 'dshEm_code',
        style: { background: statusToneColor(entry.code) },
      }, entry.code === null ? '\u2026' : String(entry.code)),
      h('span', { className: 'dshEm_tag' }, entry.isRead ? t('supa.read') : t('supa.write')),
      h('span', { className: 'dshEm_tool' }, entry.short),
      h('span', { className: 'dshEm_supaText' }, preview),
      h('span', { className: 'dshEm_supaTime' }, formatSeconds(entry.seconds, t)))
    }

    /** The formatted detail of one Supabase call: SQL, status and response. */
    function SupabaseDetail(props) {
      const t = props.t
      const entry = props.entry
      const response = entry.response
      const children = [
        h('div', { key: 'head', className: 'dshEm_detailHead' },
          h('span', { className: 'dshEm_code', style: { background: statusToneColor(entry.code) } },
            entry.code === null ? '\u2026' : String(entry.code)),
          h('span', { className: 'dshEm_tag' }, entry.isRead ? t('supa.read') : t('supa.write')),
          h('span', { className: 'dshEm_tool' }, entry.short),
          h('span', { className: 'dshEm_spacer' }),
          h('button', {
            type: 'button',
            className: 'dshEm_iconBtn',
            onClick: props.onClose,
            'aria-label': t('supa.close'),
            title: t('supa.close'),
          }, '\u2715')),
        h('div', { key: 'meta', className: 'dshEm_metaRow' },
          h('span', null, t('supa.status') + ' ' + (entry.code === null ? t('supa.pending') : String(entry.code))),
          entry.codeReason === null ? null : h('span', null, entry.codeReason),
          h('span', null, t('table.where') + ' ' + entry.turn + ' / ' + entry.step),
          h('span', null, formatSeconds(entry.seconds, t))),
        h('div', { key: 'sqltitle', className: 'dshEm_widgetSectionTitle' }, t('supa.query')),
        h('pre', { key: 'sql', className: 'dshEm_pre' },
          entry.sql === null ? (entry.argsRaw === null ? t('supa.noSql') : entry.argsRaw) : entry.sql),
        h('div', { key: 'restitle', className: 'dshEm_widgetSectionTitle' }, t('supa.response')),
      ]
      if (response.kind === 'empty') {
        children.push(h('div', { key: 'empty', className: 'dshEm_hint' }, t('supa.emptyResponse')))
      } else if (response.kind === 'rows') {
        const columns = response.columns.slice(0, 6)
        const rows = response.rows.slice(0, 8)
        children.push(h('div', { key: 'rows', className: 'dshEm_resScroll' },
          h('table', { className: 'dshEm_resTable' },
            h('thead', null, h('tr', null, columns.map((column) => h('th', { key: column }, column)))),
            h('tbody', null, rows.map((row, index) => h('tr', { key: 'row-' + index },
              columns.map((column) => h('td', { key: column, title: cellText(row[column]) }, cellText(row[column])))))))))
        children.push(h('div', { key: 'count', className: 'dshEm_hint' },
          (response.wrapper === null ? '' : response.wrapper + ' \u00b7 ') + t('supa.rows', { count: response.rows.length })))
      } else {
        children.push(h('pre', {
          key: 'text',
          className: 'dshEm_pre' + (entry.status === 'ok' ? '' : ' dshEm_errorText'),
        }, response.text === null ? '' : response.text))
      }
      return h('div', { className: 'dshEm_detail' }, children)
    }

    /**
     * The Supabase MCP widget: every call the session made to the MCP server, with
     * the SQL it ran, the status code and the response one click away. It follows
     * the main Session binding like the other floating widget, because a
     * root-scoped entry receives no Session props.
     * @param props - root slot props plus the injected main-Session hook and resolver.
     */
    function SupabaseWidget(props) {
      const t = typeof props.t === 'function' ? props.t : fallbackT
      const useMainSafe = typeof props.useMainSession === 'function' ? props.useMainSession : useEmptyMain
      const resolveSources = typeof props.resolveSources === 'function' ? props.resolveSources : resolveNoSources

      const mainValue = useMainSafe(selectMainValue)
      const sources = resolveSources(mainValue)
      const trajectory = React.useSyncExternalStore(sources.trajectory.subscribe, sources.trajectory.getSnapshot, sources.trajectory.getSnapshot)
      const activity = React.useMemo(() => deriveSupabaseActivity(trajectory), [trajectory])
      const [selectedId, setSelectedId] = React.useState(null)
      const [readsOnly, setReadsOnly] = React.useState(false)
      const floating = useFloatingLayout(SUPABASE_STORAGE_KEY, 'left')

      let selected = null
      for (const entry of activity.entries) {
        if (entry.id === selectedId) {
          selected = entry
          break
        }
      }
      const visible = readsOnly ? activity.entries.filter((entry) => entry.isRead) : activity.entries
      const tone = activity.errors > 0 ? statusColor('failed') : activity.running > 0 ? statusColor('running') : statusColor('ok')

      const body = h('div', { className: 'dshEm_widgetBody' },
        h('div', { className: 'dshEm_widgetRow' },
          h('span', { className: 'dshEm_chip' }, t('supa.chipReads', { count: activity.reads })),
          h('span', { className: 'dshEm_chip' }, t('supa.chipWrites', { count: activity.writes })),
          activity.errors > 0
            ? h('span', { className: 'dshEm_badge' }, String(activity.errors))
            : h('span', { className: 'dshEm_chip' }, t('supa.chipErrors', { count: 0 }))),
        h('div', { className: 'dshEm_widgetRow' },
          h('button', {
            type: 'button',
            className: 'dshEm_toggle',
            'aria-pressed': readsOnly ? 'true' : 'false',
            onClick: () => setReadsOnly(readsOnly !== true),
          }, t('supa.readsOnly')),
          h('span', { className: 'dshEm_hint' }, t('supa.hint'))),
        activity.total === 0
          ? h('div', { className: 'dshEm_hint' }, t('supa.empty'))
          : h('div', { className: 'dshEm_supaList' },
            visible.map((entry) => h(SupabaseRow, {
              key: entry.id,
              entry,
              t,
              selected: entry.id === selectedId,
              onSelect: (id) => setSelectedId(selectedId === id ? null : id),
            }))),
        selected === null ? null : h(SupabaseDetail, { entry: selected, t, onClose: () => setSelectedId(null) }),
        h('div', { className: 'dshEm_hint' }, t('supa.derived')))

      return h(FloatingFrame, {
        css: SUPABASE_CSS,
        label: t('supa.title'),
        dragTitle: t('widget.drag'),
        title: t('supa.title'),
        headline: String(activity.total),
        tone,
        foldedExtras: activity.errors > 0 ? h('span', { className: 'dshEm_badge' }, String(activity.errors)) : null,
        expandLabel: t('widget.expand'),
        minimizeLabel: t('widget.minimize'),
        layout: floating.layout,
        startDrag: floating.startDrag,
        moveDrag: floating.moveDrag,
        endDrag: floating.endDrag,
        toggleCollapsed: floating.toggleCollapsed,
      }, body)
    }

    //#endregion

    /** Client plugin body: dictionary registration and the four slot entries. */
    function apply(ctx) {
      ctx.effect(() => ctx.locale.register(NS, { zh, en }), 'execution-monitor: dictionaries')

      // Optional extra locale: a failure here must never take the panel down.
      if (typeof ctx.locale.addLanguage === 'function') {
        ctx.effect(() => {
          try {
            return ctx.locale.addLanguage({ id: 'es', label: 'Español', fallback: 'en' })
          } catch (error) {
            return undefined
          }
        }, 'execution-monitor: spanish language')
        ctx.effect(() => {
          try {
            return ctx.locale.register(NS, 'es', es)
          } catch (error) {
            return undefined
          }
        }, 'execution-monitor: spanish dictionary')
      }

      // Bound after registration so the label thunk always resolves.
      const t = ctx.locale.bind(NS)

      ctx.slots.inject('conversation.view', () => ctx.slots.register({
        name: 'conversation.view',
        id: 'execution-monitor',
        order: 20,
        locale: NS,
        label: () => t('view.label'),
      }, MonitorView))

      if (SHOW_COMPOSER_STRIP) {
        ctx.slots.inject('conversation.composer.dock', () => ctx.slots.register({
          name: 'conversation.composer.dock',
          id: 'execution-monitor',
          order: 5,
          locale: NS,
        }, MonitorStrip))
      }

      // The floating widget lives in the frame-wide overlay, so it receives no
      // Session props: it follows the main Session binding instead. The service is
      // read optionally, so its absence only costs this one surface.
      const uiSession = typeof ctx.get === 'function' ? ctx.get('uiSession') : undefined
      if (uiSession !== undefined && uiSession !== null && uiSession.current !== undefined) {
        const resolveSources = createSourceResolver()
        ctx.slots.inject('shell.overlay', () => ctx.slots.register({
          name: 'shell.overlay',
          id: 'execution-monitor-widget',
          order: 15,
          locale: NS,
          inject: () => ({ hooks: { mainSession: uiSession.current }, resolveSources }),
        }, MonitorWidget))

        ctx.slots.inject('shell.overlay', () => ctx.slots.register({
          name: 'shell.overlay',
          id: 'execution-monitor-supabase',
          order: 16,
          locale: NS,
          inject: () => ({ hooks: { mainSession: uiSession.current }, resolveSources }),
        }, SupabaseWidget))
      }
    }

    // Components are exported the way shipped client plugins do it, so a surface
    // that is not registered (the composer strip) stays testable.
    return { inject, apply, MonitorView, MonitorStrip, MonitorWidget, SupabaseWidget }
  },
})
