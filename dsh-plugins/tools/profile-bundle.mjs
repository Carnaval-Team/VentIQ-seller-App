/**
 * Add or remove one bundle name in a DSH profile manifest's `dsh.profile.bundles`,
 * preserving field order and the manifest's two-space indentation.
 *
 *   node profile-bundle.mjs <profileDir> <bundleName> add|remove
 */

import fs from 'node:fs'
import path from 'node:path'

const [profileDir, name, action] = process.argv.slice(2)
if (profileDir === undefined || name === undefined || (action !== 'add' && action !== 'remove')) {
  console.error('usage: node profile-bundle.mjs <profileDir> <bundleName> add|remove')
  process.exit(2)
}

const manifestPath = path.join(profileDir, 'package.json')
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
const profile = (manifest.dsh ??= {}).profile ??= {}
const bundles = Array.isArray(profile.bundles) ? profile.bundles : (profile.bundles = [])

const before = bundles.slice()
if (action === 'add') {
  if (!bundles.includes(name)) bundles.push(name)
} else {
  profile.bundles = bundles.filter((entry) => entry !== name)
}

fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n')
console.log(JSON.stringify({ manifestPath, action, before, after: profile.bundles }))
