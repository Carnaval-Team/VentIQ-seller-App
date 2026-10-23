// Puerta de sintaxis para TypeScript sin deno ni tsc.
//
// Node 22 trae `module.stripTypeScriptTypes`, que elimina las anotaciones de
// tipo. Después compilamos el JavaScript resultante como MÓDULO con
// `vm.SourceTextModule` (necesita --experimental-vm-modules), que falla si
// queda cualquier error de sintaxis.
//
// NO valida tipos (para eso hace falta tsc o deno check): solo garantiza que
// el archivo parsea.
//
// Uso:
//   node --experimental-strip-types --experimental-vm-modules \
//        __agent__/wapi/check_ts.mjs <archivo.ts> [...]
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { stripTypeScriptTypes } from "node:module";

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error("uso: node --experimental-strip-types --experimental-vm-modules check_ts.mjs <archivo.ts> [...]");
  process.exit(2);
}
if (typeof vm.SourceTextModule !== "function") {
  console.error("falta --experimental-vm-modules: sin él no se puede parsear como módulo.");
  process.exit(2);
}

let fallos = 0;
for (const f of files) {
  try {
    const src = readFileSync(f, "utf8");
    const js = stripTypeScriptTypes(src, { mode: "strip" });
    new vm.SourceTextModule(js, { identifier: f });
    console.log(`OK    ${f}`);
  } catch (e) {
    fallos++;
    console.error(`FALLO ${f}\n      ${e.name}: ${e.message}`);
  }
}
console.log(
  fallos === 0
    ? "\nSintaxis OK (los tipos NO se validan con esto)."
    : `\n${fallos} archivo(s) con errores.`,
);
process.exit(fallos === 0 ? 0 : 1);