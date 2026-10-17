// POST /functions/v1/wapi-session-action
// Body: { id_sesion: number, action: 'qr' | 'logout' | 'restart' | 'delete'
//                              | 'stop' | 'force-kill' | 'health'
//                              | 'register-webhook' | 'recover' }
//
// CAMBIOS CLAVE (ver docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md)
//   1. `restart` YA NO llama a `/api/sessions/:id/restart`, que **no existe**
//      en OpenWA (su runbook: "there is no /restart route"). Antes acertaba sólo
//      por el fallback a `/start`. Ahora usa la escalera de verdad:
//          POST /stop → POST /start     (estado disconnected)
//          + POST /force-kill → /start  (estado failed, terminal en OpenWA)
//      y verifica leyendo el estado real en vez de fiarse del 2xx.
//   2. Se añaden `stop`, `force-kill`, `health` y `register-webhook`.
//      · `health` devuelve la **versión del servidor OpenWA**: es lo primero
//        que hay que mirar, porque el bug de "failed reconnect attempt arms
//        another attempt that tears down the engine" sólo está arreglado desde
//        v0.25.0.
//      · `register-webhook` re-registra el webhook por la ruta documentada y
//        **con secret**, que es el arreglo de las sesiones ya creadas con el
//        webhook roto (las que nunca recibieron `session.*`).
//   3. Se persiste el status CRUDO (`raw_status`) además del normalizado.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi, WAPI_WEBHOOK_EVENTS } from "../_shared/wapi_client.ts";
import { normalizeWapiStatus } from "../_shared/status.ts";
import { runRecovery } from "../_shared/session_recovery.ts";
import { updateSessionState } from "../_shared/session_store.ts";

const ACTIONS: string[] = [
  "qr",
  "logout",
  "restart",
  "recover", // alias de restart, con la escalera completa
  "delete",
  "stop",
  "force-kill",
  "health",
  "register-webhook",
];

/** Une la URL del webhook con el secret configurado en el proyecto. */
function webhookUrlFor(idTienda: number): string | undefined {
  const supaUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  return supaUrl.startsWith("https://")
    ? `${supaUrl}/functions/v1/wapi-webhook?tienda=${idTienda}`
    : undefined;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const ctx = await getAuthContext(req);
  if (!ctx) return errorResponse("No autenticado", 401);

  const { id_sesion, action } = await req.json().catch(() => ({}));
  const idSesion = Number(id_sesion);
  if (!Number.isFinite(idSesion) || !ACTIONS.includes(action)) {
    return errorResponse(
      `Parámetros inválidos. action debe ser una de: ${ACTIONS.join(", ")}`,
      400,
    );
  }

  const { data: ses } = await ctx.sb
    .from("app_wapi_sesion").select("*").eq("id", idSesion).maybeSingle();
  if (!ses) return errorResponse("Sesión no encontrada", 404);
  if (!(await assertStoreAccess(ctx, ses.id_tienda))) {
    return errorResponse("Sin acceso", 403);
  }

  const wapiSessionId = ses.wapi_session_id as string;

  // ── health ────────────────────────────────────────────────────────────
  // Devuelve la versión del servidor OpenWA (sólo visible con API key) y si
  // está listo. Es el primer dato que hay que tener para saber si el server
  // está atrasado respecto a los fixes de reconexión.
  if (action === "health") {
    const [salud, listo, vivo] = await Promise.all([
      wapi.health(),
      wapi.healthReady(),
      wapi.healthLive(),
    ]);
    return okResponse({
      api_health: salud.success ? salud.data : { error: salud.error },
      api_ready: listo.success ? listo.data : { error: listo.error },
      api_live: vivo.success ? vivo.data : { error: vivo.error },
      version: (salud.data as Record<string, unknown> | undefined)?.version ?? null,
      nota: "Si `version` es null, revisa WAPI_API_KEY: OpenWA sólo expone la " +
        "versión a keys válidas.",
    });
  }

  // ── register-webhook ──────────────────────────────────────────────────
  // Arreglo para las sesiones existentes cuyo webhook se registró sin secret
  // (o sin los eventos session.*). Idempotente: si ya hay uno apuntando a
  // nuestra URL, lo actualiza en vez de duplicarlo.
  if (action === "register-webhook") {
    const url = webhookUrlFor(ses.id_tienda);
    if (!url) {
      return errorResponse(
        "SUPABASE_URL no está configurado o no es https: no se puede registrar el webhook",
        500,
        "NO_WEBHOOK_URL",
      );
    }
    const secret = Deno.env.get("WAPI_WEBHOOK_SECRET") ?? "";
    const eventos = [...WAPI_WEBHOOK_EVENTS];
    const cuerpo = { url, events: eventos, ...(secret ? { secret } : {}) };

    const existentes = await wapi.listWebhooks(wapiSessionId);
    let res;
    if (existentes.success && Array.isArray(existentes.data)) {
      const previo = existentes.data.find((w) => w && w.url === url);
      if (previo) {
        res = await wapi.updateWebhook(wapiSessionId, previo.id, cuerpo);
      }
    }
    if (!res) res = await wapi.registerWebhook(wapiSessionId, cuerpo);

    if (!res.success) {
      return errorResponse(
        res.error?.message ?? "No se pudo registrar el webhook",
        502,
        res.error?.code,
      );
    }
    return okResponse({
      ok: true,
      webhook: res.data,
      eventos,
      con_secret: Boolean(secret),
      nota: secret
        ? "Webhook (re)registrado con secret: las firmas X-OpenWA-Signature deben validar."
        : "WAPI_WEBHOOK_SECRET no está configurado: el webhook va sin firma y " +
          "wapi-webhook aceptará cualquier POST.",
    });
  }

  // ── qr ────────────────────────────────────────────────────────────────
  // Devuelve el QR. No tocamos la columna status en DB: de eso ya se encarga
  // wapi-session-status, que además persiste last_qr_image.
  if (action === "qr") {
    let qrRes = await wapi.getQr(wapiSessionId);

    // Si el engine está detenido, /qr no devuelve nada útil. Lo arrancamos y
    // reintentamos.
    if (!qrRes.success) {
      console.warn(
        `[wapi-session-action] /qr falló (${qrRes.error?.code}): ${qrRes.error?.message}. Arrancando engine...`,
      );
      const startRes = await wapi.startSession(wapiSessionId);
      if (!startRes.success) {
        console.warn(
          `[wapi-session-action] /start falló (${startRes.error?.code}): ${startRes.error?.message}`,
        );
      }
      qrRes = await wapi.getQr(wapiSessionId);
    }

    if (!qrRes.success) {
      return errorResponse(
        qrRes.error?.message ?? "No se pudo obtener el QR",
        502,
        qrRes.error?.code,
      );
    }
    return okResponse({ ok: true, status: "SCAN_QR", qr: qrRes.data });
  }

  // ── delete ────────────────────────────────────────────────────────────
  if (action === "delete") {
    // `/logout` desvincula (borra credenciales); para liberar el engine sin
    // desvincular está `stop`. Antes de borrar la fila intentamos parar para no
    // dejar un Chromium huérfano consumiendo RAM (≈300-500 MB por sesión).
    const stopRes = await wapi.stopSession(wapiSessionId);
    if (!stopRes.success) {
      console.warn(
        `[wapi-session-action] /stop previo al delete falló (${stopRes.error?.code}): ${stopRes.error?.message}`,
      );
    }
    const apiRes = await wapi.deleteSession(wapiSessionId);
    if (!apiRes.success) {
      // No bloquear si la API ya no la tiene (404). Limpiamos DB igual.
      console.warn("[wapi-session-action] delete falló:", apiRes.error);
    }
    await ctx.admin.from("app_wapi_sesion").delete().eq("id", ses.id);
    return okResponse({ ok: true });
  }

  // ── stop / force-kill ─────────────────────────────────────────────────
  if (action === "stop" || action === "force-kill") {
    const r = action === "stop"
      ? await wapi.stopSession(wapiSessionId)
      : await wapi.forceKill(wapiSessionId);

    // 400 en force-kill = "no había engine vivo". Es el caso bueno.
    const noHabia = r.error?.code === "HTTP_400" || r.error?.code === "HTTP_404";
    if (!r.success && !noHabia) {
      return errorResponse(
        r.error?.message ?? `No se pudo ejecutar ${action}`,
        502,
        r.error?.code,
      );
    }

    if (action === "stop") {
      await updateSessionState(ctx.admin, ses.id, {
        status: "DISCONNECTED",
        rawStatus: "stopped",
        // Un stop es deliberado: el watchdog no debe resucitarla. Se vuelve a
        // activar con `restart`/`recover` o con `qr`.
        watchdogEnabled: false,
      });
    }
    return okResponse({ ok: true, action, no_habia_engine: noHabia });
  }

  // ── logout ────────────────────────────────────────────────────────────
  if (action === "logout") {
    const apiRes = await wapi.logout(wapiSessionId);
    if (!apiRes.success) {
      return errorResponse(
        apiRes.error?.message ?? "No se pudo desconectar la sesión",
        502,
        apiRes.error?.code,
      );
    }
    // OpenWA limpia el teléfono al desvincular: la sesión necesitará un QR
    // nuevo. Reflejarlo en la BD evita que la UI siga mostrando el número.
    await updateSessionState(ctx.admin, ses.id, {
      status: "DISCONNECTED",
      rawStatus: "logged_out",
      phoneNumber: null,
    });
    return okResponse({ ok: true, status: "DISCONNECTED", requiere_qr: true });
  }

  // ── restart / recover ─────────────────────────────────────────────────
  // Leemos el estado REAL antes de decidir: la columna `status` de la BD puede
  // estar desactualizada (es justo el fallo que dejaba el bot muerto).
  const live = await wapi.getSession(wapiSessionId);
  const rawStatus = live.success
    ? live.data?.status
    : (ses.status as string | undefined);

  if (!live.success) {
    console.warn(
      `[wapi-session-action] getSession falló (${live.error?.code}): ` +
        `${live.error?.message} — se decide con el estado de la BD (${ses.status})`,
    );
  }

  const outcome = await runRecovery(
    wapi,
    wapiSessionId,
    rawStatus,
    {
      lastRecoveryAt: (ses.last_recovery_at as string | null) ?? null,
      recoveryAttempts: Number(ses.recovery_attempts ?? 0),
    },
  );

  // El estado final puede ser el que devolvió /start o el que se leyó después.
  const rawFinal = outcome.finalRawStatus ?? rawStatus ?? ses.status;
  const newStatus = normalizeWapiStatus(
    rawFinal,
    outcome.action === "none" ? (ses.status as string) : "INITIALIZING",
  );

  const fallo = outcome.steps.find((s) => !s.ok);

  await updateSessionState(ctx.admin, ses.id, {
    status: newStatus,
    rawStatus: rawFinal ? String(rawFinal) : null,
    ...(live.success && live.data?.phoneNumber
      ? { phoneNumber: live.data.phoneNumber }
      : {}),
    recoveryAttempt: outcome.action !== "none" && outcome.action !== "cooldown",
    // Un reinicio explícito vuelve a habilitar el watchdog (por si la sesión
    // había quedado parada a propósito con `stop`).
    watchdogEnabled: true,
    errorCode: outcome.ok ? null : (fallo?.code ?? "RECOVERY_FAILED"),
    errorMessage: outcome.ok ? null : (fallo?.message ?? null),
  });

  console.log(
    `[wapi-session-action] ${action} sesion=${ses.id} raw=${rawStatus} → ${rawFinal} ` +
      `acción=${outcome.action} ok=${outcome.ok} pasos=${
        outcome.steps.map((s) => `${s.step}:${s.ok ? "ok" : s.code}`).join(",")
      }`,
  );

  if (!outcome.ok && outcome.action !== "none" && outcome.action !== "cooldown") {
    return errorResponse(
      `No se pudo recuperar la sesión (${outcome.action}). ` +
        `${fallo?.message ?? "OpenWA no confirmó el arranque"}. ` +
        (outcome.needsHumanAck
          ? "Además hay que confirmar el modal \"What's new\" de WhatsApp en el teléfono una vez, y volver a reiniciar."
          : outcome.terminal
          ? "La sesión está en FAILED (estado terminal en OpenWA): si el reinicio no basta, hay que borrarla y volver a vincularla."
          : ""),
      502,
      "RECOVERY_FAILED",
    );
  }

  return okResponse({
    ok: true,
    status: newStatus,
    raw_status: rawFinal,
    accion: outcome.action,
    requiere_qr: outcome.needsQr || newStatus === "SCAN_QR",
    requiere_confirmacion_manual: outcome.needsHumanAck,
    pasos: outcome.steps,
    reintento_sugerido_en_segundos: outcome.retryAfterSeconds ?? null,
  });
});