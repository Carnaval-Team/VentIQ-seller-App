#!/usr/bin/env node
// =============================================================================
//  Pruebas de la lógica pura de las Edge Functions WAPI.
//
//  No hay `deno` en este entorno, así que estos módulos se escribieron para ser
//  importables sin `Deno.env` y se prueban con el type-stripping nativo de Node:
//
//    node --experimental-strip-types ventiq_admin_app/scripts/tests/wapi_shared.test.mjs
//
//  Cubre `_shared/status.ts` (mapeo de estados) y `_shared/session_recovery.ts`
//  (planificador + escalera de recuperación con cliente inyectado).
// =============================================================================

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  isSessionDown,
  isSessionSendable,
  isSessionTerminal,
  normalizeWapiStatus,
} from "../../supabase/functions/_shared/status.ts";
import {
  isReady,
  planRecovery,
  runRecovery,
} from "../../supabase/functions/_shared/session_recovery.ts";
import { updateSessionState } from "../../supabase/functions/_shared/session_store.ts";

// ─────────────────────────────────────────────────────────────────────────────
//  status.ts
// ─────────────────────────────────────────────────────────────────────────────
test("normalizeWapiStatus: estados del cable de OpenWA", () => {
  assert.equal(normalizeWapiStatus("ready"), "CONNECTED");
  assert.equal(normalizeWapiStatus("qr_ready"), "SCAN_QR");
  assert.equal(normalizeWapiStatus("authenticating"), "CONNECTING");
  assert.equal(normalizeWapiStatus("disconnected"), "DISCONNECTED");
  assert.equal(normalizeWapiStatus("failed"), "FAILED");
  assert.equal(normalizeWapiStatus("created"), "INITIALIZING");
  assert.equal(normalizeWapiStatus("initializing"), "INITIALIZING");
});

test("normalizeWapiStatus: action_required ya NO se confunde con INITIALIZING", () => {
  // Antes caía al fallback y la UI pintaba "Inicializando" (ámbar) una sesión
  // que en realidad necesitaba intervención humana.
  assert.equal(normalizeWapiStatus("action_required"), "DISCONNECTED");
  assert.equal(normalizeWapiStatus("ACTION_REQUIRED"), "DISCONNECTED");
  assert.equal(normalizeWapiStatus("restricted"), "DISCONNECTED");
  assert.equal(normalizeWapiStatus("reconnecting"), "CONNECTING");
});

test("normalizeWapiStatus: alias y normalización de forma", () => {
  assert.equal(normalizeWapiStatus("Qr-Ready"), "SCAN_QR");
  assert.equal(normalizeWapiStatus(" QR  Ready "), "SCAN_QR");
  assert.equal(normalizeWapiStatus(null, "SCAN_QR"), "SCAN_QR");
  assert.equal(normalizeWapiStatus("", "CONNECTED"), "CONNECTED");
});

test("isSessionDown / isSessionSendable / isSessionTerminal", () => {
  assert.equal(isSessionDown("disconnected"), true);
  assert.equal(isSessionDown("action_required"), true);
  assert.equal(isSessionDown("failed"), true);
  assert.equal(isSessionDown("ready"), false);
  assert.equal(isSessionDown("qr_ready"), false);

  assert.equal(isSessionSendable("ready"), true);
  assert.equal(isSessionSendable("connected"), true);
  assert.equal(isSessionSendable("action_required"), false);
  assert.equal(isSessionSendable("qr_ready"), false);

  assert.equal(isSessionTerminal("failed"), true);
  assert.equal(isSessionTerminal("disconnected"), false);
});

// ─────────────────────────────────────────────────────────────────────────────
//  planRecovery
// ─────────────────────────────────────────────────────────────────────────────
test("planRecovery: sesión lista no se toca", () => {
  const p = planRecovery("ready");
  assert.equal(p.action, "none");
});

test("planRecovery: estados intermedios → sólo /start", () => {
  assert.equal(planRecovery("qr_ready").action, "start");
  assert.equal(planRecovery("qr_ready").needsQr, true);
  assert.equal(planRecovery("initializing").action, "start");
  assert.equal(planRecovery("created").action, "start");
});

test("planRecovery: caída → reinicio soportado (stop → start)", () => {
  const p = planRecovery("disconnected");
  assert.equal(p.action, "stop-start");
  assert.equal(p.needsHumanAck, false);
});

test("planRecovery: failed es terminal → force-kill → start", () => {
  const p = planRecovery("failed");
  assert.equal(p.action, "force-kill-start");
  assert.equal(p.terminal, true);
});

test("planRecovery: action_required exige confirmar el modal a mano", () => {
  const p = planRecovery("action_required");
  assert.equal(p.action, "stop-start");
  assert.equal(p.needsHumanAck, true);
  assert.equal(p.needsQr, false);
});

test("planRecovery: cooldown por recuperación reciente", () => {
  const p = planRecovery("disconnected", {
    lastRecoveryAt: new Date(Date.now() - 60_000).toISOString(),
    cooldownMinutes: 10,
  });
  assert.equal(p.action, "cooldown");
});

test("planRecovery: cooldown tras agotar intentos", () => {
  const p = planRecovery("disconnected", {
    recoveryAttempts: 3,
    maxAttempts: 3,
  });
  assert.equal(p.action, "cooldown");
});

test("planRecovery: cooldown ya vencido → se recupera", () => {
  const p = planRecovery("disconnected", {
    lastRecoveryAt: new Date(Date.now() - 30 * 60_000).toISOString(),
    cooldownMinutes: 10,
  });
  assert.equal(p.action, "stop-start");
});

test("planRecovery: estado desconocido no se toca", () => {
  const p = planRecovery("invented_state");
  assert.equal(p.action, "none");
});

// ─────────────────────────────────────────────────────────────────────────────
//  runRecovery con cliente falso
// ─────────────────────────────────────────────────────────────────────────────
function fakeClient(handlers) {
  const llamadas = [];
  const wrap = (name) => async (id) => {
    llamadas.push(name);
    const r = handlers[name]?.(id);
    return r ?? { success: true, data: {} };
  };
  return {
    llamadas,
    stopSession: wrap("stopSession"),
    startSession: wrap("startSession"),
    forceKill: wrap("forceKill"),
    getSession: wrap("getSession"),
  };
}

test("runRecovery: disconnected → stop, start, verifica READY", async () => {
  const c = fakeClient({
    startSession: () => ({ success: true, data: { status: "qr_ready" } }),
    getSession: () => ({ success: true, data: { status: "ready" } }),
  });
  const r = await runRecovery(c, "sess-1", "disconnected", { settleMs: 0 });
  assert.deepEqual(c.llamadas, ["stopSession", "startSession", "getSession"]);
  assert.equal(r.ok, true);
  assert.equal(r.finalRawStatus, "READY");
  assert.equal(
    r.steps.map((s) => s.step).join(","),
    "stop,start,getSession",
  );
});

test("runRecovery: /stop con 400 'not active' se tolera", async () => {
  const c = fakeClient({
    stopSession: () => ({
      success: false,
      error: { code: "HTTP_400", message: "Session is not active. Start the session first." },
    }),
    getSession: () => ({ success: true, data: { status: "ready" } }),
  });
  const r = await runRecovery(c, "sess-1", "disconnected", { settleMs: 0 });
  assert.equal(r.ok, true);
  assert.equal(r.steps[0].ok, false);
});

test("runRecovery: /start 400 'already started' se tolera (sólo queríamos el estado)", async () => {
  const c = fakeClient({
    startSession: () => ({
      success: false,
      error: { code: "HTTP_400", message: "Session is already started" },
    }),
    getSession: () => ({ success: true, data: { status: "ready" } }),
  });
  const r = await runRecovery(c, "sess-1", "disconnected", { settleMs: 0 });
  assert.equal(r.ok, true);
});

test("runRecovery: failed → stop, force-kill, start, verifica", async () => {
  const c = fakeClient({
    startSession: () => ({ success: true, data: { status: "initializing" } }),
    getSession: () => ({ success: true, data: { status: "connected" } }),
  });
  const r = await runRecovery(c, "sess-1", "failed", { settleMs: 0 });
  assert.deepEqual(c.llamadas, [
    "stopSession",
    "forceKill",
    "startSession",
    "getSession",
  ]);
  assert.equal(r.ok, true);
  assert.equal(r.terminal, true);
});

test("runRecovery: si sigue caída devuelve ok=false y pide QR", async () => {
  const c = fakeClient({
    startSession: () => ({ success: true, data: { status: "qr_ready" } }),
    getSession: () => ({ success: true, data: { status: "disconnected" } }),
  });
  const r = await runRecovery(c, "sess-1", "disconnected", { settleMs: 0 });
  assert.equal(r.ok, false);
  assert.equal(r.finalRawStatus, "DISCONNECTED");
});

test("runRecovery: /start falla de verdad → ok=false y no verifica", async () => {
  const c = fakeClient({
    startSession: () => ({
      success: false,
      error: { code: "HTTP_500", message: "Internal server error" },
    }),
  });
  const r = await runRecovery(c, "sess-1", "disconnected", { settleMs: 0 });
  assert.equal(r.ok, false);
  assert.equal(c.llamadas.includes("getSession"), false);
});

test("runRecovery: 429 con retryAfterSeconds se propaga", async () => {
  const c = fakeClient({
    stopSession: () => ({
      success: false,
      error: {
        code: "HTTP_429",
        message: "Too Many Requests",
        retryAfterSeconds: 45,
      },
    }),
    getSession: () => ({ success: true, data: { status: "ready" } }),
  });
  const r = await runRecovery(c, "sess-1", "disconnected", { settleMs: 0 });
  assert.equal(r.retryAfterSeconds, 45);
});

test("runRecovery: action_required marca needsHumanAck", async () => {
  const c = fakeClient({});
  const r = await runRecovery(c, "sess-1", "action_required", { settleMs: 0 });
  assert.equal(r.needsHumanAck, true);
  assert.equal(r.action, "stop-start");
});

test("isReady: sólo ready/connected", () => {
  assert.equal(isReady("ready"), true);
  assert.equal(isReady("READY"), true);
  assert.equal(isReady("qr_ready"), false);
  assert.equal(isReady(null), false);
});

// ─────────────────────────────────────────────────────────────────────────────
//  session_store: persistencia tolerante a la migración
// ─────────────────────────────────────────────────────────────────────────────
/** Admin falso que devuelve la respuesta i-ésima de `respuestas`. */
function fakeAdmin(respuestas) {
  const updates = [];
  let i = 0;
  return {
    updates,
    from(table) {
      return {
        update(values) {
          updates.push({ table, values });
          const r = respuestas[Math.min(i++, respuestas.length - 1)];
          return { eq: async () => r };
        },
        select() {
          return {
            eq: () => ({ maybeSingle: async () => ({ data: { recovery_attempts: 4 }, error: null }) }),
          };
        },
      };
    },
  };
}

test("updateSessionState: patch sólo base hace una sola llamada", async () => {
  const admin = fakeAdmin([{ error: null }]);
  const r = await updateSessionState(admin, 7, { status: "CONNECTED" });
  assert.equal(r.ok, true);
  assert.equal(r.degraded, false);
  assert.equal(admin.updates.length, 1);
  assert.equal(admin.updates[0].table, "app_wapi_sesion");
  assert.equal(admin.updates[0].values.status, "CONNECTED");
  assert.ok(admin.updates[0].values.last_status_at);
});

test("updateSessionState: degrada si la migración no está aplicada", async () => {
  // Primer intento: la columna no existe. Segundo: sólo columnas base.
  const admin = fakeAdmin([
    { error: { message: 'column "raw_status" does not exist' } },
    { error: null },
  ]);
  const r = await updateSessionState(admin, 7, {
    status: "DISCONNECTED",
    rawStatus: "action_required",
    recoveryAttempt: true,
  });
  assert.equal(r.ok, true);
  assert.equal(r.degraded, true);
  assert.equal(admin.updates.length, 2);
  // El reintento lleva SOLO columnas base.
  assert.deepEqual(Object.keys(admin.updates[1].values).sort(), [
    "last_status_at",
    "status",
  ]);
});

test("updateSessionState: un error que NO es de columna no se reintenta", async () => {
  const admin = fakeAdmin([{ error: { message: "permission denied" } }]);
  const r = await updateSessionState(admin, 7, {
    status: "CONNECTED",
    rawStatus: "ready",
  });
  assert.equal(r.ok, false);
  assert.equal(r.degraded, false);
  assert.equal(admin.updates.length, 1);
  assert.match(r.error, /permission denied/);
});

test("updateSessionState: recoveryAttempt incrementa el contador", async () => {
  const admin = fakeAdmin([{ error: null }]);
  await updateSessionState(admin, 7, {
    status: "DISCONNECTED",
    recoveryAttempt: true,
  });
  assert.equal(admin.updates[0].values.recovery_attempts, 5); // 4 + 1
  assert.ok(admin.updates[0].values.last_recovery_at);
});

test("updateSessionState: resetRecovery pone el contador a 0", async () => {
  const admin = fakeAdmin([{ error: null }]);
  await updateSessionState(admin, 7, { status: "CONNECTED", resetRecovery: true });
  assert.equal(admin.updates[0].values.recovery_attempts, 0);
});

test("updateSessionState: watchdogEnabled se guarda", async () => {
  const admin = fakeAdmin([{ error: null }]);
  await updateSessionState(admin, 7, { watchdogEnabled: false });
  assert.equal(admin.updates[0].values.watchdog_enabled, false);
});

test("planRecovery: sesión sin vincular esperando QR no se reinicia", () => {
  const p = planRecovery("qr_ready", { linked: false });
  assert.equal(p.action, "none");
  assert.match(p.reason, /sin vincular/);
  // Y si está vinculada, sí se arranca.
  assert.equal(planRecovery("qr_ready", { linked: true }).action, "start");
});