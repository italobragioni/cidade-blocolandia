// Cidade Blocolândia — função "pegar-casa"
// Confere o captcha (Cloudflare Turnstile) e só então mexe no banco.
// Ações (campo "acao" no corpo):
//   "casa"  (padrão) → { handle }                → cria/devolve o morador
//   "ideia"          → { handle, texto }         → envia uma ideia
//   "votar"          → { handle, ideia_id }      → vota / tira o voto
//   "enquete"        → { handle, opcao_id }      → vota numa opção da enquete
//   "skin"           → { handle, skin }          → troca a roupa do boneco
//   "admin_*"        → { senha, ... }            → painel de administração (#admin)
// Precisa dos segredos TURNSTILE_SECRET e ADMIN_SENHA em Edge Functions → Secrets.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const ERROS = ["handle_invalido", "nao_morador", "texto_invalido", "limite", "ideia_invalida", "enquete_encerrada", "skin_invalida"];
const erroDe = (msg: string) => ERROS.find((e) => msg.includes(e)) ?? "banco";

// compara a senha sem vazar pelo tempo de resposta
function senhaConfere(dada: unknown): boolean {
  const certa = Deno.env.get("ADMIN_SENHA") ?? "";
  if (typeof dada !== "string" || certa.length < 6) return false;
  const a = new TextEncoder().encode(dada), b = new TextEncoder().encode(certa);
  let dif = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) dif |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return dif === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "metodo" }, 405);

  try {
    const body = await req.json();
    const { handle, token } = body;
    const acao = body.acao ?? "casa";
    const admin = typeof acao === "string" && acao.startsWith("admin_");
    if (typeof token !== "string" || !token) return json({ error: "captcha" }, 400);
    if (!admin && typeof handle !== "string") return json({ error: "handle_invalido" }, 400);

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

    // ---------- painel de administração ----------
    if (admin) {
      if (!senhaConfere(body.senha)) return json({ error: "senha" }, 401);
      const rodar = async (fn: string, args: Record<string, unknown> = {}) => {
        const { data, error } = await sb.rpc(fn, args);
        if (error) throw new Error(error.message);
        return data;
      };
      try {
        if (acao === "admin_painel") return json(await rodar("admin_painel"));
        if (acao === "admin_criar_enquete") {
          const opcoes = Array.isArray(body.opcoes) ? body.opcoes.map((o: unknown) => String(o).trim()).filter(Boolean) : [];
          const pergunta = String(body.pergunta ?? "").trim();
          const dias = Math.min(30, Math.max(0.04, Number(body.dias) || 3));
          if (pergunta.length < 3 || opcoes.length < 2 || opcoes.length > 6) return json({ error: "enquete_invalida" }, 400);
          return json({ id: await rodar("criar_enquete", { p_pergunta: pergunta, p_opcoes: opcoes, p_dias: dias }) });
        }
        if (acao === "admin_encerrar_enquete") { await rodar("admin_encerrar_enquete", { p_id: Number(body.id) }); return json({ ok: true }); }
        if (acao === "admin_apagar_enquete")   { await rodar("admin_apagar_enquete",   { p_id: Number(body.id) }); return json({ ok: true }); }
        if (acao === "admin_status_ideia")     { await rodar("admin_status_ideia",     { p_id: Number(body.id), p_status: String(body.status) }); return json({ ok: true }); }
      } catch (_e) {
        return json({ error: "banco" }, 400);
      }
      return json({ error: "acao" }, 400);
    }

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
    if (acao === "skin") {
      const { error } = await sb.rpc("trocar_skin", { p_handle: handle, p_skin: String(body.skin ?? "") });
      if (error) return json({ error: erroDe(error.message) }, 400);
      return json({ ok: true, skin: body.skin });
    }
    if (acao === "enquete") {
      const opcao = Number(body.opcao_id);
      if (!Number.isInteger(opcao)) return json({ error: "enquete_encerrada" }, 400);
      const { error } = await sb.rpc("votar_enquete", { p_handle: handle, p_opcao: opcao });
      if (error) return json({ error: erroDe(error.message) }, 400);
      return json({ ok: true });
    }
    return json({ error: "acao" }, 400);
  } catch (_e) {
    return json({ error: "erro" }, 500);
  }
});
