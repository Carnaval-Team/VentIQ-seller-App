/**
 * Smoke test for the Execution Monitor client module.
 *
 * It evaluates the real `client.js` against a minimal React shim, drives the
 * plugin's activation path with a fake cordis context, renders the three slot
 * components over synthetic data, exercises the floating widget's drag/fold
 * handlers, and fails on any missing locale key. Run with the bundled Node:
 *
 *   node test/smoke.mjs
 */

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const packageDir = path.join(here, '..')
const source = fs.readFileSync(path.join(packageDir, 'client.js'), 'utf8')

let failures = 0
function check(name, condition, detail) {
  if (condition) {
    console.log('  ok   ' + name)
  } else {
    failures++
    console.log('  FAIL ' + name + (detail === undefined ? '' : ' — ' + detail))
  }
}

//#region manifest (mirrors the Harness validators)

const manifest = JSON.parse(fs.readFileSync(path.join(packageDir, 'package.json'), 'utf8'))
const clientDeclaration = manifest.dsh === undefined ? undefined : manifest.dsh.client
const bundleDeclaration = manifest.dsh === undefined ? undefined : manifest.dsh.bundle

check('manifest is private and ESM', manifest.private === true && manifest.type === 'module')
check('dsh.client.platform is "web"', clientDeclaration !== undefined && clientDeclaration.platform === 'web')
check('dsh.client.inject lists package names',
  Array.isArray(clientDeclaration.inject) && clientDeclaration.inject.every((entry) => entry.startsWith('@')))
check('dsh.client.immediately is a boolean', typeof clientDeclaration.immediately === 'boolean')
check('dsh.bundle.patch points at the patch file',
  bundleDeclaration.patch === './cordis.patch.yml' && fs.existsSync(path.join(packageDir, 'cordis.patch.yml')))
check('exports["./client"] resolves to the browser bundle',
  manifest.exports['./client'] === './client.js' && fs.existsSync(path.join(packageDir, 'client.js')))
check('exports["."] resolves to the host half',
  manifest.exports['.'] === './index.js' && fs.existsSync(path.join(packageDir, 'index.js')))
check('host half exports apply', /export function apply/.test(fs.readFileSync(path.join(packageDir, 'index.js'), 'utf8')))

const patchText = fs.readFileSync(path.join(packageDir, 'cordis.patch.yml'), 'utf8')
check('patch inserts this plugin row', patchText.includes('- insert:') && patchText.includes(manifest.name))
check('patch row id is stable', /id:\s*execution-monitor/.test(patchText))

const icon = manifest.icon
const iconPath = icon === undefined ? null : path.join(packageDir, icon)
check('icon is a relative file inside the package',
  typeof icon === 'string' && !path.isAbsolute(icon) && !icon.includes('..') && fs.existsSync(iconPath))
check('icon is an SVG under 256 KiB',
  iconPath !== null && icon.endsWith('.svg') && fs.statSync(iconPath).size <= 256 * 1024)
check('locale metadata files exist for en and zh',
  ['en', 'zh'].every((locale) => fs.existsSync(path.join(packageDir, 'locale', locale + '.json'))))

const requires = [...source.matchAll(/require\(\s*'([^']+)'\s*\)/g)].map((match) => match[1])
check('the client module only requires react',
  requires.length > 0 && requires.every((id) => id === 'react' || id === 'react/jsx-runtime'),
  requires.join(', '))
check('the client module imports no Harness package',
  !/require\(\s*'@deepseek-ai\//.test(source))
check('the client module keeps its styles plugin-owned',
  source.includes("h('style'") && !source.includes('document.createElement'))

//#endregion

//#region minimal React shim

let hookLog = []
let stateIndex = 0
let stateScope = 'root'
let rerenderRequested = false
/** State cells keyed by component path, so each instance keeps its own state. */
const stateCells = new Map()
const stateInitialized = new Set()

function resetComponentState() {
  stateCells.clear()
  stateInitialized.clear()
}

function createElement(type, props, ...children) {
  const flat = []
  const push = (child) => {
    if (Array.isArray(child)) child.forEach(push)
    else if (child !== null && child !== undefined && child !== false) flat.push(child)
  }
  children.forEach(push)
  return { type, props: props === null ? {} : props, children: flat }
}

const React = {
  createElement,
  Fragment: Symbol('react.fragment'),
  useState: (initial) => {
    hookLog.push('useState')
    const key = stateScope + '#' + stateIndex++
    if (!stateInitialized.has(key)) {
      stateInitialized.add(key)
      stateCells.set(key, typeof initial === 'function' ? initial() : initial)
    }
    const setter = (next) => {
      const value = typeof next === 'function' ? next(stateCells.get(key)) : next
      if (value === stateCells.get(key)) return
      stateCells.set(key, value)
      rerenderRequested = true
    }
    return [stateCells.get(key), setter]
  },
  useEffect: () => {
    hookLog.push('useEffect')
  },
  useMemo: (factory) => {
    hookLog.push('useMemo')
    return factory()
  },
  useCallback: (callback) => {
    hookLog.push('useCallback')
    return callback
  },
  useRef: (initial) => {
    hookLog.push('useRef')
    return { current: initial }
  },
  useSyncExternalStore: (subscribe, getSnapshot) => {
    hookLog.push('useSyncExternalStore')
    return getSnapshot()
  },
}

/** Resolve function components so the whole tree is materialized for assertions. */
function renderTree(node, path = 'root') {
  if (node === null || node === undefined || typeof node !== 'object') return node
  if (Array.isArray(node)) return node.map((child, index) => renderTree(child, path + '.' + index))
  if (typeof node.type === 'function') {
    const props = { ...node.props }
    if (node.children.length === 1) props.children = node.children[0]
    else if (node.children.length > 1) props.children = node.children
    const scope = path + '/' + (node.type.name === '' ? 'anon' : node.type.name)
    const previousScope = stateScope
    stateScope = scope
    const rendered = node.type(props)
    stateScope = previousScope
    return renderTree(rendered, scope)
  }
  return { type: node.type, props: node.props, children: node.children.map((child, index) => renderTree(child, path + '.' + index)) }
}

//#endregion

//#region load the module

const storage = new Map()
let loaded = null
const windowShim = {
  innerWidth: 1440,
  innerHeight: 900,
  localStorage: {
    getItem: (key) => (storage.has(key) ? storage.get(key) : null),
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: (key) => storage.delete(key),
  },
  __ModuleLoader__: {
    load: (definition) => {
      loaded = definition
    },
  },
}
const requireShim = (id) => {
  if (id === 'react') return React
  throw new Error('the plugin must not require ' + id)
}
new Function('window', 'require', source)(windowShim, requireShim)

check('module registers itself with the loader', loaded !== null)
check('module id is the package name', loaded.id === '@local/dsh-execution-monitor', loaded.id)

const plugin = loaded.factory(requireShim)
check('factory returns inject + apply', Array.isArray(plugin.inject) && typeof plugin.apply === 'function')
check('services declared are slots + locale', plugin.inject.join(',') === 'slots,locale', plugin.inject.join(','))

//#endregion

//#region synthetic data

const t0 = 1_700_000_000_000
const liveTrajectory = {
  eventNodes: [
    {
      kind: 'assistant', turn: 1, step: 1, seq: 1, time: t0,
      usage: { inputTokens: 1200, outputTokens: 300, cacheReadTokens: 100 },
      blocks: [
        { kind: 'tool-call', callId: 'c1', name: 'read' },
        { kind: 'tool-call', callId: 'c2', name: 'pwsh' },
      ],
    },
    { kind: 'tool-result', callId: 'c1', callTime: t0 + 100, time: t0 + 900, isError: false },
    { kind: 'tool-result', callId: 'c2', callTime: t0 + 950, time: t0 + 3950, isError: true, error: { message: 'boom', code: 'E_FAIL' } },
    {
      kind: 'assistant', turn: 1, step: 2, seq: 4, time: t0 + 4000,
      usage: { inputTokens: 2000, outputTokens: 500 },
      blocks: [{ kind: 'tool-call', callId: 'c3', name: 'edit' }],
    },
  ],
  requests: [
    { turn: 1, step: 1, status: 'complete' },
    { turn: 1, step: 2, status: 'running' },
  ],
  runningCalls: [{ callId: 'c3', turn: 1, step: 2, time: t0 + 4100, phase: 'start' }],
}

const cleanTrajectory = {
  eventNodes: [
    {
      kind: 'assistant', turn: 1, step: 1, seq: 1, time: t0,
      usage: { inputTokens: 10, outputTokens: 5 },
      blocks: [{ kind: 'tool-call', callId: 'd1', name: 'read' }],
    },
    { kind: 'tool-result', callId: 'd1', callTime: t0 + 10, time: t0 + 210, isError: false },
  ],
  requests: [{ turn: 1, step: 1, status: 'complete' }],
  runningCalls: [],
}

const emptyTrajectory = { eventNodes: [], requests: [], runningCalls: [] }

const planA = [
  { content: 'read the file', status: 'completed' },
  { content: 'write the plugin', status: 'in_progress' },
  { content: 'publish the package', status: 'pending' },
]
const planB = [
  { content: 'read the file', status: 'completed' },
  { content: 'write the plugin', status: 'completed' },
]

//#endregion

//#region activation against a fake context

const dictionaries = {}
const languages = []
const registrations = []
let interpolationMissing = null

function translate(locale, key, params) {
  const dictionary = dictionaries[locale]
  if (dictionary === undefined) {
    interpolationMissing = 'dictionary ' + locale + ' is not registered'
    return key
  }
  if (!(key in dictionary)) {
    interpolationMissing = 'missing "' + key + '" in ' + locale
    return key
  }
  const template = dictionary[key]
  if (params === undefined) return template
  return template.replace(/\{(\w+)\}/g, (match, name) => (name in params ? String(params[name]) : match))
}

/** Live values behind the materialized main binding's sources. */
const liveMain = { trajectory: liveTrajectory, todos: null }

/**
 * Materialized main binding, shaped like the one ui-session publishes. Its
 * sources stay live, exactly as the real store-backed ones do.
 */
const currentMain = {
  key: 'session-1',
  hooks: {
    trajectory: { getSnapshot: () => liveMain.trajectory, subscribe: () => () => {} },
  },
  keyedHooks: {
    projection: (key) => (key === 'todos' ? { getSnapshot: () => liveMain.todos, subscribe: () => () => {} } : undefined),
  },
}

const uiSessionService = {
  current: {
    getSnapshot: () => currentMain,
    subscribe: () => () => {},
  },
}

const ctx = {
  effect: (factory) => factory(),
  get: (name) => (name === 'uiSession' ? uiSessionService : undefined),
  locale: {
    bind: () => (key, params) => translate('en', key, params),
    register: (namespace, localeOrDicts, dict) => {
      if (typeof localeOrDicts === 'string') {
        dictionaries[localeOrDicts] = dict
      } else {
        dictionaries.zh = localeOrDicts.zh
        dictionaries.en = localeOrDicts.en
      }
      return () => {}
    },
    addLanguage: (definition) => {
      languages.push(definition)
      return () => {}
    },
  },
  slots: {
    inject: (key, callback) => {
      callback()
      return () => {}
    },
    register: (options, Component) => {
      registrations.push({ options, Component })
      return () => {}
    },
  },
}

plugin.apply(ctx)

check('three slot entries registered', registrations.length === 3, String(registrations.length))
const viewEntry = registrations.find((entry) => entry.options.name === 'conversation.view')
const overlayEntries = registrations.filter((entry) => entry.options.name === 'shell.overlay')
const widgetEntry = overlayEntries.find((entry) => entry.options.id === 'execution-monitor-widget')
const supabaseEntry = overlayEntries.find((entry) => entry.options.id === 'execution-monitor-supabase')
/** The composer strip is off by default; it is rendered through its export. */
const stripEntry = { Component: plugin.MonitorStrip }
check('registers the conversation.view screen', viewEntry !== undefined)
check('the composer strip stays unregistered', registrations.every((entry) => entry.options.name !== 'conversation.composer.dock'))
check('the strip component is still exported', typeof plugin.MonitorStrip === 'function')
check('registers the frame-wide floating widget', widgetEntry !== undefined)
check('registers the Supabase MCP widget', supabaseEntry !== undefined)
check('view entry declares its id and locale', viewEntry.options.id === 'execution-monitor' && viewEntry.options.locale === 'executionMonitor')
check('view entry exposes a label thunk', viewEntry.options.label() === 'Monitor', String(viewEntry.options.label()))
check('widget entry declares its own id', widgetEntry.options.id === 'execution-monitor-widget', String(widgetEntry.options.id))

const keySets = Object.keys(dictionaries).map((locale) => [locale, Object.keys(dictionaries[locale]).sort().join('|')])
const referenceKeys = keySets[0][1]
check('en/zh/es dictionaries share one key set', keySets.every(([, keys]) => keys === referenceKeys),
  keySets.map(([locale, keys]) => locale + ':' + keys.split('|').length).join(' '))
check('spanish language pack declares a fallback', languages.length === 1 && languages[0].id === 'es' && languages[0].fallback === 'en')

//#endregion

//#region render helpers

function propsFor(snapshot, running, options) {
  const settings = options === undefined ? {} : options
  const sessionId = settings.sessionId === undefined ? 'session-1' : settings.sessionId
  const todos = settings.todos === undefined ? null : settings.todos
  return {
    sessionId,
    t: (key, params) => translate('en', key, params),
    useTrajectory: (selector) => selector(snapshot),
    useSessionStatus: (selector) => selector(new Map([[sessionId, { running }]])),
    useSession: (selector) => selector({ openState: 'open' }),
    useProjection: (key, selector) => selector(key === 'todos' ? todos : undefined),
  }
}

/** Render one slot entry, replaying state updates until the tree settles. */
function render(entry, props) {
  let tree = null
  for (let pass = 0; pass < 4; pass++) {
    hookLog = []
    stateIndex = 0
    rerenderRequested = false
    tree = renderTree(entry.Component(props))
    if (!rerenderRequested) break
  }
  return tree
}

function textOf(tree) {
  if (tree === null || tree === undefined) return ''
  if (typeof tree === 'string' || typeof tree === 'number') return String(tree)
  if (Array.isArray(tree)) return tree.map(textOf).join(' ')
  if (tree.type === 'style') return ''
  return (tree.children ?? []).map(textOf).join(' ')
}

function collect(tree, predicate, found = []) {
  if (tree === null || tree === undefined || typeof tree !== 'object') return found
  if (Array.isArray(tree)) {
    for (const child of tree) collect(child, predicate, found)
    return found
  }
  if (predicate(tree)) found.push(tree)
  for (const child of tree.children ?? []) collect(child, predicate, found)
  return found
}

function hasClassIn(tree, className) {
  return countClass(tree, className) > 0
}

function countClass(tree, className) {
  return collect(tree, (node) => typeof node.props.className === 'string' && node.props.className.split(' ').includes(className)).length
}

/** The hook the framework builds from an injected ObservableSnapshot. */
function hookFrom(source) {
  return (selector) => (selector === undefined ? source.getSnapshot() : selector(source.getSnapshot()))
}

//#endregion

//#region render: live run

const live = render(viewEntry, propsFor(liveTrajectory, true))
const liveText = textOf(live)
check('live view renders', live !== null)
check('no locale key is missing while rendering', interpolationMissing === null, String(interpolationMissing))
check('live view reports 67% completion (2 of 3 calls finished)', liveText.includes('67%'), liveText.slice(0, 300))
check('live view reports the failure rate', liveText.includes('50% of finished calls failed'), liveText.slice(0, 300))
check('live view shows the current turn and step', liveText.includes('Turn 1') && liveText.includes('step 2'))
check('live view counts the running tool call', liveText.includes('Running 1'), liveText.slice(0, 300))
check('live view shows the failing tool name', liveText.includes('pwsh'))
check('live view shows the failure message', liveText.includes('boom'))
check('live view aggregates input and output tokens', liveText.includes('3.2k') && liveText.includes('out 800'), liveText.slice(0, 300))
check('live view renders the outcome chart', hasClassIn(live, 'dshEm_bar'))
check('live view renders one timeline bar per call', countClass(live, 'dshEm_col') >= 3)
check('live view renders the token sparkline', hasClassIn(live, 'dshEm_spark'))
check('live view renders its scrollable tables', hasClassIn(live, 'dshEm_scroll'))
check('live view renders the completion ring', collect(live, (node) => node.type === 'svg').length >= 2)

//#endregion

//#region render: other states, hook order, degraded props

const firstHookLog = hookLog.join(',')
render(viewEntry, propsFor(liveTrajectory, true))
check('hook order is identical across renders', hookLog.join(',') === firstHookLog, hookLog.join(','))

const idleText = textOf(render(viewEntry, propsFor(cleanTrajectory, false)))
check('a clean finished run reports idle at 100%', idleText.includes('Idle') && idleText.includes('100%'), idleText.slice(0, 300))
check('no locale key is missing while idle', interpolationMissing === null, String(interpolationMissing))

const failedText = textOf(render(viewEntry, propsFor(liveTrajectory, false)))
check('a stopped run with failures reports that state', failedText.includes('Has failures'), failedText.slice(0, 300))

const emptyText = textOf(render(viewEntry, propsFor(emptyTrajectory, false)))
check('empty run shows the waiting state', emptyText.includes('has not started working'), emptyText.slice(0, 300))
check('no locale key is missing while empty', interpolationMissing === null, String(interpolationMissing))

const partialTrajectory = {
  eventNodes: [],
  requests: [],
  runningCalls: [{ callId: 'only', turn: 3, step: 1, time: t0, phase: 'preparing' }],
}
const partialText = textOf(render(viewEntry, propsFor(partialTrajectory, true)))
check('a preparing-only call still renders', partialText.includes('Running'), partialText.slice(0, 300))

let degraded = null
try {
  degraded = render(viewEntry, { sessionId: 'session-1', t: (key) => translate('en', key) })
} catch (error) {
  check('a view without the standard hooks renders', false, error && error.message)
}
check('a view without the standard hooks renders', degraded !== null)

//#endregion

//#region checklist: done, in progress, pending and skipped

const planProps = (todos) => propsFor(liveTrajectory, true, { sessionId: 'session-plan', todos })
const planFirst = render(viewEntry, planProps(planA))
const planFirstText = textOf(planFirst)
check('checklist reports the plan progress', planFirstText.includes('1 of 3 done'), planFirstText.slice(0, 400))
check('checklist shows every plan item', planFirstText.includes('read the file') && planFirstText.includes('write the plugin') && planFirstText.includes('publish the package'))
check('checklist marks the completed row', countClass(planFirst, 'dshEm_item--done') === 1)
check('checklist marks the active row', countClass(planFirst, 'dshEm_item--active') === 1)
check('checklist marks the pending row', countClass(planFirst, 'dshEm_item--pending') === 1)
check('checklist strikes through completed items',
  source.includes('.dshEm_item--done .dshEm_itemText{text-decoration:line-through'))
check('checklist counts what is left', planFirstText.includes('To do 1') && planFirstText.includes('In progress 1'), planFirstText.slice(0, 400))
check('nothing is skipped while the plan is intact', planFirstText.includes('Nothing skipped'))

const planSecond = render(viewEntry, planProps(planB))
const planSecondText = textOf(planSecond)
check('checklist follows the plan to completion', planSecondText.includes('2 of 2 done'), planSecondText.slice(0, 400))
const skippedRows = collect(planSecond, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_item--skipped'))
check('an item dropped unfinished becomes a warning', skippedRows.length === 1, String(skippedRows.length))
check('the warning names the dropped item', textOf(skippedRows[0] ?? null).includes('publish the package'), textOf(skippedRows[0] ?? null))
check('completed items are never reported as skipped', !textOf(skippedRows[0] ?? null).includes('read the file'))
check('the warning surface explains itself', planSecondText.includes('Items dropped from the plan without completing'))

//#endregion

//#region render: the compact strip (exported, not registered)

const stripLive = render(stripEntry, propsFor(liveTrajectory, true))
const stripText = textOf(stripLive)
check('strip renders while the session has data', stripLive !== null)
check('strip shows the completion percentage', stripText.includes('67%'), stripText)
check('strip summarises outcomes', stripText.includes('1 ok') && stripText.includes('1 failed') && stripText.includes('1 running'), stripText)
check('strip marks the failure count', countClass(stripLive, 'dshEm_badge') === 1)
check('strip exposes a status role with an aria label', collect(stripLive, (node) => node.props.role === 'status' && typeof node.props['aria-label'] === 'string').length === 1)

const stripEmpty = render(stripEntry, propsFor(emptyTrajectory, false))
check('strip renders nothing without data', stripEmpty === null)

const stripDegraded = render(stripEntry, { sessionId: 'session-1', t: (key) => translate('en', key) })
check('strip renders nothing without the standard hooks', stripDegraded === null)

//#endregion

//#region render: the floating widget

const widgetInjected = widgetEntry.options.inject()
check('the widget injects the main-Session hook', widgetInjected.hooks !== undefined && widgetInjected.hooks.mainSession !== undefined)
check('the widget receives the source resolver', typeof widgetInjected.resolveSources === 'function')

function widgetProps(running) {
  return {
    t: (key, params) => translate('en', key, params),
    useMainSession: hookFrom(widgetInjected.hooks.mainSession),
    useSessionStatus: (selector) => selector(new Map([['session-1', { running }]])),
    resolveSources: widgetInjected.resolveSources,
  }
}

liveMain.trajectory = liveTrajectory
liveMain.todos = planA
const widget = render(widgetEntry, widgetProps(true))
const widgetText = textOf(widget)
check('the widget renders without throwing', widget !== null)
check('no locale key is missing in the widget', interpolationMissing === null, String(interpolationMissing))
check('the widget shows the live numbers', widgetText.includes('67%') && widgetText.includes('Execution monitor'), widgetText.slice(0, 300))
check('the widget reads the main binding trajectory', widgetText.includes('pwsh') || widgetText.includes('boom'), widgetText.slice(0, 400))
check('the widget shows the plan checklist', widgetText.includes('Plan') && widgetText.includes('1 of 3 done'), widgetText.slice(0, 400))
check('the widget is positioned over the frame', collect(widget, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_widget')).some((node) => node.props.style !== undefined && node.props.style.left === '1048px'))
check('the widget is a complementary landmark', collect(widget, (node) => node.props.role === 'complementary').length === 1)
check('the widget offers a fold control', countClass(widget, 'dshEm_iconBtn') === 1)

const head = collect(widget, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_widgetHead'))[0]
check('the widget header is the drag handle', head !== undefined && typeof head.props.onPointerDown === 'function')
head.props.onPointerDown({ button: 0, clientX: 1200, clientY: 200, pointerId: 1, currentTarget: { setPointerCapture: () => {} } })
head.props.onPointerMove({ clientX: 1100, clientY: 260 })
head.props.onPointerUp({})
const stored = storage.get('dsh.execution-monitor.widget')
const storedLayout = stored === undefined ? null : JSON.parse(stored)
check('dragging moves and remembers the widget', storedLayout !== null && storedLayout.x === 948 && storedLayout.y === 156, stored)

const foldButton = collect(widget, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_iconBtn'))[0]
foldButton.props.onClick()
const foldedLayout = JSON.parse(storage.get('dsh.execution-monitor.widget'))
check('folding is remembered', foldedLayout.collapsed === true, storage.get('dsh.execution-monitor.widget'))

const foldedWidget = render(widgetEntry, widgetProps(true))
check('a folded widget keeps its head and drops the body',
  countClass(foldedWidget, 'dshEm_widgetBody') === 0 && textOf(foldedWidget).includes('67%'))
check('a folded widget still reports the plan progress', textOf(foldedWidget).includes('1 of 3 done'), textOf(foldedWidget).slice(0, 200))

storage.set('dsh.execution-monitor.widget', JSON.stringify({ x: 1048, y: 96, collapsed: false }))
resetComponentState()
liveMain.trajectory = emptyTrajectory
liveMain.todos = null
const emptyWidget = render(widgetEntry, widgetProps(false))
check('the widget renders without a plan', emptyWidget !== null && textOf(emptyWidget).includes('No task list in this turn'), textOf(emptyWidget).slice(0, 300))

const noSources = render(widgetEntry, { t: (key) => translate('en', key) })
check('the widget renders without injected sources', noSources !== null)

//#endregion

//#region the Supabase MCP widget

const supabaseTrajectory = {
  eventNodes: [
    {
      kind: 'assistant', turn: 2, step: 1, seq: 10, time: t0,
      blocks: [
        { kind: 'tool-call', callId: 's1', name: 'mcp__supabase__execute_sql', argsRaw: JSON.stringify({ query: 'select id, name from products order by id limit 2' }) },
        { kind: 'tool-call', callId: 's2', name: 'pwsh', argsRaw: '{"command":"ls"}' },
      ],
    },
    {
      kind: 'tool-result', callId: 's1', callTime: t0 + 20, time: t0 + 320, isError: false,
      content: [{ type: 'text', text: '[{"id":1,"name":"Cafe"},{"id":2,"name":"Azucar"}]' }],
    },
    { kind: 'tool-result', callId: 's2', callTime: t0 + 330, time: t0 + 400, isError: false, content: [{ type: 'text', text: 'ok' }] },
    {
      kind: 'assistant', turn: 2, step: 2, seq: 12, time: t0 + 500,
      blocks: [
        { kind: 'tool-call', callId: 's3', name: 'mcp__supabase__execute_sql', argsRaw: JSON.stringify({ query: 'update products set price = 0 where id = 1' }) },
        { kind: 'tool-call', callId: 's4', name: 'mcp__supabase__list_storage_buckets', argsRaw: '{}' },
      ],
    },
    {
      kind: 'tool-result', callId: 's3', callTime: t0 + 520, time: t0 + 700, isError: true,
      content: [{ type: 'text', text: '{"code":"42501","message":"permission denied for table products"}' }],
    },
    {
      kind: 'tool-result', callId: 's4', callTime: t0 + 720, time: t0 + 900, isError: false,
      content: [{ type: 'text', text: '{"buckets":[{"id":"medias_ventiq","public":false},{"id":"images","public":true}]}' }],
    },
    {
      kind: 'assistant', turn: 2, step: 3, seq: 14, time: t0 + 950,
      blocks: [
        { kind: 'tool-call', callId: 's5', name: 'mcp__dart__analyze_files', argsRaw: '{}' },
        { kind: 'tool-call', callId: 's6', name: 'mcp__supabase__get_advisors', argsRaw: '{"type":"security"}' },
      ],
    },
    {
      kind: 'tool-result', callId: 's6', callTime: t0 + 970, time: t0 + 1100, isError: true,
      content: [{ type: 'text', text: 'connection reset by peer' }],
    },
  ],
  requests: [],
  runningCalls: [],
}

resetComponentState()
storage.delete('dsh.execution-monitor.supabase')
liveMain.trajectory = supabaseTrajectory
liveMain.todos = null

const supaInjected = supabaseEntry.options.inject()
check('the Supabase widget injects the main-Session hook', supaInjected.hooks !== undefined && supaInjected.hooks.mainSession !== undefined)

function supaProps() {
  return {
    t: (key, params) => translate('en', key, params),
    useMainSession: hookFrom(supaInjected.hooks.mainSession),
    resolveSources: supaInjected.resolveSources,
  }
}

const supa = render(supabaseEntry, supaProps())
const supaText = textOf(supa)
check('the Supabase widget renders without throwing', supa !== null)
check('no locale key is missing in the Supabase widget', interpolationMissing === null, String(interpolationMissing))
check('the widget is labelled as the Supabase MCP surface', supaText.includes('Supabase MCP'))

const supaRows = collect(supa, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_supaRow'))
check('one row per Supabase call', supaRows.length === 4, String(supaRows.length))
check('non-Supabase tool calls stay out', !supaText.includes('analyze_files') && !supaText.includes('pwsh'))
check('the widget counts reads and writes', supaText.includes('3 reads') && supaText.includes('1 writes'), supaText.slice(0, 300))
check('the widget flags the errors', supaText.includes('2 errors') || countClass(supa, 'dshEm_badge') === 1)
check('a successful read is reported as 200', supaText.includes('200'))
check('a denied write is reported as 403', supaText.includes('403'))
check('a broken call is reported as 500', supaText.includes('500'))
check('the widget explains that codes are derived', supaText.includes('derived from the MCP result'))
check('the widget shows the SQL it ran', supaText.includes('select id, name from products'))
check('the widget positions itself in its own column', collect(supa, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_widget')).some((node) => node.props.style !== undefined && node.props.style.left === '300px' && node.props.style.top === '96px'))

const readRow = supaRows.find((row) => textOf(row).includes('select id, name'))
check('the read call is listed with its kind', readRow !== undefined && textOf(readRow).includes('Read'))
check('the write call is listed with its kind', supaRows.some((row) => textOf(row).includes('Write')))

readRow.props.onClick()
const detailTree = render(supabaseEntry, supaProps())
const detailText = textOf(detailTree)
check('clicking a row opens its detail', detailText.includes('Response'))
check('the detail repeats the SQL', detailText.includes('select id, name from products order by id limit 2'))
check('the detail reports the status', detailText.includes('Status 200'))
check('the detail formats rows as a table', detailText.includes('id') && detailText.includes('name') && detailText.includes('Cafe') && detailText.includes('Azucar'))
check('the detail counts the rows', detailText.includes('2 rows'))
check('the detail can be closed', collect(detailTree, (node) => node.props['aria-label'] === 'Close detail').length === 1)

collect(detailTree, (node) => node.props['aria-label'] === 'Close detail')[0].props.onClick()
const closedTree = render(supabaseEntry, supaProps())
check('closing the detail hides it', !textOf(closedTree).includes('Response'))

const bucketsRow = collect(closedTree, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_supaRow'))
  .find((row) => textOf(row).includes('list_storage_buckets'))
check('a read tool with no SQL is listed too', bucketsRow !== undefined && textOf(bucketsRow).includes('No SQL'))
bucketsRow.props.onClick()
const bucketsTree = render(supabaseEntry, supaProps())
const bucketsText = textOf(bucketsTree)
check('a wrapped array is formatted as a table', bucketsText.includes('medias_ventiq') && bucketsText.includes('images'), bucketsText.slice(0, 400))
check('the table names its wrapper and row count', bucketsText.includes('buckets') && bucketsText.includes('2 rows'))
collect(bucketsTree, (node) => node.props['aria-label'] === 'Close detail')[0].props.onClick()
const afterBuckets = render(supabaseEntry, supaProps())

const toggle = collect(afterBuckets, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_toggle'))[0]
check('the reads-only filter starts off', toggle !== undefined && toggle.props['aria-pressed'] === 'false')
toggle.props.onClick()
const filteredTree = render(supabaseEntry, supaProps())
const filteredText = textOf(filteredTree)
check('the reads-only filter hides writes', !filteredText.includes('set price = 0'), filteredText.slice(0, 300))
check('the filter is announced as pressed', collect(filteredTree, (node) => node.props['aria-pressed'] === 'true').length === 1)
check('the filter keeps the reads', filteredText.includes('select id, name'))

const failingRow = collect(filteredTree, (node) => typeof node.props.className === 'string' && node.props.className.includes('dshEm_supaRow'))
  .find((row) => textOf(row).includes('get_advisors'))
check('a failed call is listed too', failingRow !== undefined)
check('a failed call previews its error when it has no SQL', textOf(failingRow ?? null).includes('connection reset'))
failingRow.props.onClick()
const failureTree = render(supabaseEntry, supaProps())
check('a failure detail shows the raw message', textOf(failureTree).includes('connection reset by peer'))
check('a failure detail keeps the derived code', textOf(failureTree).includes('Status 500'))

resetComponentState()
liveMain.trajectory = emptyTrajectory
const emptySupa = render(supabaseEntry, supaProps())
check('the Supabase widget renders with no calls', emptySupa !== null && textOf(emptySupa).includes('No Supabase MCP calls'))
check('the empty widget renders no rows', countClass(emptySupa, 'dshEm_supaRow') === 0)

//#endregion

console.log('')
if (failures === 0) {
  console.log('smoke: all checks passed')
  process.exit(0)
}
console.log('smoke: ' + failures + ' check(s) failed')
process.exit(1)
