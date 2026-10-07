/**
 * Reads a DSH session transcript and prints the shape of the tool traffic it
 * contains — used to design plugins against real payloads instead of guesses.
 *
 *   node tools/inspect-session.mjs <session.v4.jsonl.zstd> [nameFilterRegex]
 *
 * The transcript is zstd-compressed JSONL; Node 24 decompresses it natively.
 */

import fs from 'node:fs'
import zlib from 'node:zlib'

/**
 * Decompress a transcript that may hold several concatenated zstd frames: the
 * logger appends one frame per flush, and a single sync call reads only the first.
 */
function decompressFrames(buffer) {
  const magic = Buffer.from([0x28, 0xb5, 0x2f, 0xfd])
  const starts = []
  let index = buffer.indexOf(magic)
  while (index !== -1) {
    starts.push(index)
    index = buffer.indexOf(magic, index + 4)
  }
  if (starts.length === 0) return zlib.zstdDecompressSync(buffer)
  const parts = []
  for (let frame = 0; frame < starts.length; frame++) {
    const from = starts[frame]
    const to = frame + 1 < starts.length ? starts[frame + 1] : buffer.length
    try {
      parts.push(zlib.zstdDecompressSync(buffer.subarray(from, to)))
    } catch (error) {
      /* a magic-looking byte sequence inside a frame: skip that slice */
    }
  }
  return Buffer.concat(parts)
}

const file = process.argv[2]
const filter = new RegExp(process.argv[3] ?? 'supabase', 'i')
if (file === undefined) {
  console.error('usage: node inspect-session.mjs <session.v4.jsonl.zstd> [nameFilterRegex]')
  process.exit(2)
}

const compressed = fs.readFileSync(file)
const decompressed = decompressFrames(compressed).toString('utf8')
const lines = decompressed.split('\n').filter((line) => line.trim() !== '')
console.log(JSON.stringify({ compressedBytes: compressed.length, bytes: decompressed.length, events: lines.length }))

const counts = new Map()
const samples = new Map()
const seen = new Set()

for (const line of lines) {
  let event
  try {
    event = JSON.parse(line)
  } catch (error) {
    continue
  }
  const serialized = JSON.stringify(event)
  if (!filter.test(serialized)) continue
  const type = typeof event.type === 'string' ? event.type : '(no type)'
  counts.set(type, (counts.get(type) ?? 0) + 1)
  if (seen.has(type)) continue
  seen.add(type)
  samples.set(type, event)
}

console.log('matching event types:')
for (const [type, count] of [...counts.entries()].sort((a, b) => b[1] - a[1])) {
  console.log('  ' + type + ' x' + count)
}

/** Summarize a value without dumping it. */
function shape(value, depth = 0) {
  if (value === null) return 'null'
  if (Array.isArray(value)) {
    return 'array(' + value.length + ')' + (value.length > 0 && depth < 3 ? ' of ' + shape(value[0], depth + 1) : '')
  }
  if (typeof value === 'object') {
    const keys = Object.keys(value)
    if (depth >= 3) return '{' + keys.slice(0, 12).join(',') + '}'
    return '{' + keys.slice(0, 20).map((key) => key + ': ' + shape(value[key], depth + 1)).join(', ') + '}'
  }
  if (typeof value === 'string') return 'string(' + value.length + ')'
  return typeof value
}

for (const [type, event] of samples) {
  console.log('')
  console.log('=== ' + type + ' ===')
  console.log('event keys: ' + Object.keys(event).join(', '))
  if (event.data !== undefined) console.log('data: ' + shape(event.data))
  const text = JSON.stringify(event)
  console.log('sample (truncated): ' + text.slice(0, 1200))
}
