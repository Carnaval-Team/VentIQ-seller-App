// CORS headers compartidos por todas las Edge Functions WAPI
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function handleOptions(): Response {
  return new Response("ok", { headers: corsHeaders });
}

export function jsonResponse(
  payload: unknown,
  init: ResponseInit = {},
): Response {
  return new Response(JSON.stringify(payload), {
    ...init,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

export function okResponse(data: unknown): Response {
  return jsonResponse({ success: true, data });
}

export function errorResponse(
  message: string,
  status = 400,
  code?: string,
): Response {
  return jsonResponse(
    { success: false, error: { message, code: code ?? "ERROR" } },
    { status },
  );
}
