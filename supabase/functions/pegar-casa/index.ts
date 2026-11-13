// Cidade Blocolândia — função "pegar-casa"
// Confere o captcha (Cloudflare Turnstile) e só então mexe no banco.
// Ações (campo "acao" no corpo):
//   "casa"  (padrão) → { handle }                → cria/devolve o morador
//   "ideia"          → { handle, texto }         → envia uma ideia
//   "votar"          → { handle, ideia_id }      → vota / tira o voto
// Precisa do segredo TURNSTILE_SECRET configurado em Edge Functions → Secrets.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const ERROS = ["handle_invalido", "nao_morador", "texto_invalido", "limite", "ideia_invalida"];
const erroDe = (msg: string) => ERROS.find((e) => msg.includes(e)) ?? "banco";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);

  try {
    const body = await req.json();
    const { handle, token } = body;
    const acao = body.acao ?? "casa";
    if (typeof handle !== "string" || typeof token !== "string" || !token) return json({ error: "captcha" }, 400);

    // 1) confere o captcha com a Cloudflare
    const form = new FormData();
    form.append("secret", Deno.env.get("TURNSTILE_SECRET") ?? "");
    form.append("response", token);
    const ip = req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
    if (ip) form.append("remoteip", ip);
    const check = await (await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form })).json();
    if (!check.success) return json({ error: "captcha" }, 403);

    // 2) executa a ação com a chave de serviço (que fica só aqui no servidor)
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    if (acao === "casa") {
      const { data, error } = await sb.rpc("pegar_casa", { p_handle: handle });
      if (error) return json({ error: erroDe(error.message) }, 400);
      return json(data[0]);
    }
    if (acao === "ideia") {
      if (typeof body.texto !== "string") return json({ error: "texto_invalido" }, 400);
      const { data, error } = await sb.rpc("enviar_ideia", { p_handle: handle, p_texto: body.texto });
      if (error) return json({ error: erroDe(error.message) }, 400);
      return json({ id: data });
    }
    if (acao === "votar") {
      const ideia = Number(body.ideia_id);
      if (!Number.isInteger(ideia)) return json({ error: "ideia_invalida" }, 400);
      const { data, error } = await sb.rpc("votar", { p_handle: handle, p_ideia: ideia });
      if (error) return json({ error: erroDe(error.message) }, 400);
      return json(data[0]);
    }
    return json({ error: "acao" }, 400);
  } catch (_e) {
    return json({ error: "erro" }, 500);
  }
});
