// Cidade Blocolândia — função "pegar-casa"
// Confere o captcha (Cloudflare Turnstile) e só então cria/devolve o morador.
// Precisa do segredo TURNSTILE_SECRET configurado em Edge Functions → Secrets.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);

  try {
    const { handle, token } = await req.json();
    if (typeof handle !== "string" || typeof token !== "string" || !token) return json({ error: "captcha" }, 400);

    // 1) confere o captcha com a Cloudflare
    const form = new FormData();
    form.append("secret", Deno.env.get("TURNSTILE_SECRET") ?? "");
    form.append("response", token);
    const ip = req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
    if (ip) form.append("remoteip", ip);
    const check = await (await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form })).json();
    if (!check.success) return json({ error: "captcha" }, 403);

    // 2) cria ou devolve o morador (com a chave de serviço, que fica só aqui no servidor)
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data, error } = await sb.rpc("pegar_casa", { p_handle: handle });
    if (error) return json({ error: error.message.includes("handle_invalido") ? "handle_invalido" : "banco" }, 400);
    return json(data[0]);
  } catch (_e) {
    return json({ error: "erro" }, 500);
  }
});
