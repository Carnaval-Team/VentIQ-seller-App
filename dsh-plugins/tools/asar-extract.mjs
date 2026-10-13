/**
 * Extracts files from the DeepSeek Harness app.asar for read-only inspection.
 *
 * The Harness ships its packages inside app.asar, which the file tools, glob,
 * ripgrep and shell commands cannot open. This script parses the asar header and
 * writes the matching entries to a normal directory so they can be read.
 *
 *   node tools/asar-extract.mjs <outDir> [pathFilterRegex] [maxFileBytes]
 *   node tools/asar-extract.mjs C:\temp\dsh-inspect "^/dsh/node_modules/@deepseek-ai/" 8388608
 *
 * Extract into the workspace: the sandbox denies writes to platform temp paths
 * outside the session directory.
 */

import fs from 'node:fs'
import path from 'node:path'

const ASAR = 'C:\\Users\\cesar\\AppData\\Local\\Programs\\DeepSeek Harness\\resources\\app.asar'
const OUT = process.argv[2]
const FILTER = new RegExp(process.argv[3] ?? '^/dsh/node_modules/@deepseek-ai/')
const MAX_SIZE = Number(process.argv[4] ?? 8 * 1024 * 1024)

if (OUT === undefined) {
  console.error('usage: node asar-extract.mjs <outDir> [pathFilterRegex] [maxFileBytes]')
  process.exit(2)
}

const fd = fs.openSync(ASAR, 'r')
const head = Buffer.alloc(16)
fs.readSync(fd, head, 0, 16, 0)
const headerSize = head.readUInt32LE(12)
const headerBuf = Buffer.alloc(headerSize)
fs.readSync(fd, headerBuf, 0, headerSize, 16)
const header = JSON.parse(headerBuf.toString('utf8').replace(/\0+$/, ''))
const dataBase = 16 + headerSize

const entries = []
;(function walk(node, prefix) {
  for (const name of Object.keys(node.files ?? {})) {
    const child = node.files[name]
    const entryPath = prefix + '/' + name
    if (child.files) walk(child, entryPath)
    else entries.push([entryPath, child])
  }
})(header, '')

let written = 0
let skipped = 0
for (const [entryPath, meta] of entries) {
  if (!FILTER.test(entryPath)) continue
  if (meta.unpacked) {
    skipped++
    continue
  }
  const size = Number(meta.size ?? 0)
  if (size > MAX_SIZE) {
    skipped++
    continue
  }
  const buffer = Buffer.alloc(size)
  if (size > 0) fs.readSync(fd, buffer, 0, size, dataBase + Number(meta.offset))
  const destination = path.join(OUT, entryPath.replace(/^\//, '').replace(/\//g, path.sep))
  fs.mkdirSync(path.dirname(destination), { recursive: true })
  fs.writeFileSync(destination, buffer)
  written++
}
fs.closeSync(fd)
console.log(JSON.stringify({ out: OUT, written, skipped, entries: entries.length }))
