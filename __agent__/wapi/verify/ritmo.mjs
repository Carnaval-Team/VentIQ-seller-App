// Ritmo anti-ban: antes (por producto) vs después (por destino).
// Constantes reales del código: delay [5,10]s (minMs/maxMs con floor 5000),
// FANOUT_PAUSE_MS=1500, ENTRE_DESTINOS_MS=20000, DESTINO_FALLOS_MAX=3.
const delay = (5 + 10) / 2;                 // 7.5 s medio
const ENTRE = 20;                           // s (ENTRE_DESTINOS_MS) + 0-5s aleatorio
const N = 5;                                // destinos por defecto
const P = 25;                               // productos "20-30"
const envios = [8, 16, 27, 45];             // s por imagen (8 = techo optimista del código; 16-50 = medido)

const fila = (s) => {
  const gapNuevo = s + delay;                          // mismo chat, orden por destino
  const gapViejo = N * (s + delay);                    // mismo chat, orden por producto
  const sesionViejo = gapViejo / N;                    // = s+delay (1 mensaje por hueco global)
  const sesionNuevo = s + delay + ENTRE / P;           // + pausa entre destinos repartida
  return {
    s,
    gapViejo, gapNuevo, factor: gapViejo / gapNuevo,
    chatViejoH: 3600 / gapViejo, chatNuevoH: 3600 / gapNuevo,
    sesViejoMin: 60 / sesionViejo, sesNuevoMin: 60 / sesionNuevo,
    rafagaViejoMin: (P * gapViejo) / 60, rafagaNuevoMin: (P * gapNuevo) / 60,
  };
};

console.log(`delay medio=${delay}s  destinos=${N}  productos=${P}  pausa entre destinos=${ENTRE}s+0-5s`);
console.log("sEnvio | gap/chat ANTES | gap/chat AHORA | factor | msgs/h/chat ANTES -> AHORA | msgs/min sesion ANTES -> AHORA | rafaga de 25 al mismo grupo");
for (const s of envios) {
  const f = fila(s);
  console.log(
    `${String(f.s).padStart(5)}s | ${f.gapViejo.toFixed(1).padStart(12)}s | ${f.gapNuevo.toFixed(1).padStart(12)}s | ` +
    `${f.factor.toFixed(1).padStart(6)}x | ${f.chatViejoH.toFixed(0).padStart(4)} -> ${f.chatNuevoH.toFixed(0).padStart(4)} | ` +
    `${f.sesViejoMin.toFixed(2).padStart(6)} -> ${f.sesNuevoMin.toFixed(2).padStart(6)} | ${f.rafagaViejoMin.toFixed(1)}min -> ${f.rafagaNuevoMin.toFixed(1)}min`,
  );
}
console.log(`\ncarga total de la tanda: ${N * P} mensajes, ${N * P * (8 + delay) / 60} min (envio 8s) o ${N * P * (27 + delay) / 60} min (envio 27s)`);
console.log(`techo citado en el propio codigo (index.ts L32-33): 20 msgs/min/sesion -> uso real ${(60 / (8 + delay)).toFixed(2)}-${(60 / (45 + delay)).toFixed(2)} msgs/min/sesion`);