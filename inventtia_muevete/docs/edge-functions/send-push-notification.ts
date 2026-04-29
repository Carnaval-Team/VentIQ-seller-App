// Supabase Edge Function: send-push-notification
// Deploy: supabase functions deploy send-push-notification
//
// Database webhooks trigger this function on:
//   1. muevete.notificaciones INSERT  → push to target user
//   2. muevete.solicitudes_transporte INSERT → push to nearby drivers
//   3. muevete.ofertas_chofer INSERT → push to the requesting client

const PUSHY_API_KEY = "9b86a185b26a04c7175673ac4393d7af00d5ee9a3fdcb4f761abb2a0c56e3923";
const PUSHY_API_URL = "https://api.pushy.me/push?api_key=";

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface PushPayload {
  to: string | string[];
  data: Record<string, unknown>;
  notification?: { title: string; body: string };
}

async function sendPush(tokens: string[], data: Record<string, unknown>, title: string, body: string) {
  if (tokens.length === 0) return;

  const payload: PushPayload = {
    to: tokens,
    data: { ...data, title, body },
    notification: { title, body },
  };

  const res = await fetch(`${PUSHY_API_URL}${PUSHY_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  const result = await res.json();
  console.log("Pushy response:", result);
}

async function getTokensForUser(supabase: ReturnType<typeof createClient>, userUuid: string): Promise<string[]> {
  const { data } = await supabase
    .schema("muevete")
    .from("push_tokens")
    .select("device_token")
    .eq("user_uuid", userUuid);

  return (data ?? []).map((r: { device_token: string }) => r.device_token);
}

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const { type, table, record } = body;

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ── 1. notificaciones INSERT ──
    if (table === "notificaciones" && type === "INSERT") {
      const userUuid = record.user_uuid;
      const tokens = await getTokensForUser(supabase, userUuid);
      await sendPush(
        tokens,
        { type: "notification", notification_id: record.id },
        record.titulo ?? "Muevete",
        record.mensaje ?? "",
      );
    }

    // ── 2. solicitudes_transporte INSERT → notify nearby drivers ──
    if (table === "solicitudes_transporte" && type === "INSERT") {
      // Get all driver tokens (edge function doesn't do geo-filtering;
      // the client-side background service handles radius logic).
      const { data: allTokens } = await supabase
        .schema("muevete")
        .from("push_tokens")
        .select("device_token, user_uuid");

      // Get driver UUIDs
      const { data: drivers } = await supabase
        .schema("muevete")
        .from("choferes")
        .select("uuid")
        .eq("estado", true);

      const driverUuids = new Set((drivers ?? []).map((d: { uuid: string }) => d.uuid));
      const driverTokens = (allTokens ?? [])
        .filter((t: { user_uuid: string }) => driverUuids.has(t.user_uuid))
        .map((t: { device_token: string }) => t.device_token);

      await sendPush(
        driverTokens,
        {
          type: "ride_request",
          solicitud_id: record.id,
        },
        "Nueva solicitud de viaje",
        record.direccion_origen ?? "Un pasajero solicita un viaje",
      );
    }

    // ── 3. ofertas_chofer INSERT → notify the requesting client ──
    if (table === "ofertas_chofer" && type === "INSERT") {
      // Look up the solicitud to get the client's user_uuid
      const { data: solicitud } = await supabase
        .schema("muevete")
        .from("solicitudes_transporte")
        .select("user_uuid")
        .eq("id", record.solicitud_id)
        .single();

      if (solicitud) {
        const tokens = await getTokensForUser(supabase, solicitud.user_uuid);
        await sendPush(
          tokens,
          {
            type: "driver_offer",
            solicitud_id: record.solicitud_id,
            oferta_id: record.id,
          },
          "Nueva oferta de conductor",
          "Un conductor te ha hecho una oferta",
        );
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
