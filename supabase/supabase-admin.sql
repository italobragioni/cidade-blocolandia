-- ============================================================
-- Cidade Blocolândia — painel de administração (#admin no site)
-- Cole tudo no SQL Editor do Supabase e clique em "Run".
-- Estas funções só podem ser chamadas pela função "pegar-casa",
-- e ela só aceita com a senha ADMIN_SENHA (Edge Functions → Secrets).
-- ============================================================

-- Tudo que o painel mostra, de uma vez
create or replace function public.admin_painel()
returns json
language sql stable security definer set search_path = public
as $$
  select json_build_object(
    'moradores',      (select coalesce(max(numero), 0) from moradores),
    'moradores_hoje', (select count(*) from moradores where criado_em > now() - interval '1 day'),
    'ideias_novas',   (select count(*) from ideias where status = 'nova'),
    'votos_hoje',     (select count(*) from votos where criado_em > now() - interval '1 day')
                    + (select count(*) from votos_enquete where criado_em > now() - interval '1 day'),
    'enquetes', (select coalesce(json_agg(x order by x.aberta desc, x.criado_em desc), '[]'::json) from (
        select e.id, e.pergunta, e.criado_em, e.encerra_em, e.encerra_em > now() as aberta,
               (select json_agg(json_build_object('id', o.id, 'texto', o.texto,
                        'votos', (select count(*) from votos_enquete v where v.opcao_id = o.id)) order by o.ordem, o.id)
                from opcoes_enquete o where o.enquete_id = e.id) as opcoes
        from enquetes e order by e.criado_em desc limit 30) x),
    'ideias', (select coalesce(json_agg(x order by x.criado_em desc), '[]'::json) from (
        select i.id, i.texto, i.status, i.criado_em, m.handle, m.numero,
               (select count(*) from votos v where v.ideia_id = i.id) as votos
        from ideias i join moradores m on m.numero = i.autor
        order by i.criado_em desc limit 200) x)
  );
$$;

-- Moderar ideia: 'nova' | 'feita' (virou vídeo) | 'oculta' (some do site)
create or replace function public.admin_status_ideia(p_id bigint, p_status text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_status not in ('nova', 'feita', 'oculta') then raise exception 'status_invalido'; end if;
  update ideias set status = p_status, feita_em = case when p_status = 'feita' then coalesce(feita_em, now()) else null end
  where id = p_id;
end $$;

create or replace function public.admin_encerrar_enquete(p_id bigint)
returns void
language sql security definer set search_path = public
as $$ update enquetes set encerra_em = now() where id = p_id and encerra_em > now(); $$;

create or replace function public.admin_apagar_enquete(p_id bigint)
returns void
language sql security definer set search_path = public
as $$ delete from enquetes where id = p_id; $$;

revoke all on function public.admin_painel()                     from public;
revoke all on function public.admin_status_ideia(bigint, text)   from public;
revoke all on function public.admin_encerrar_enquete(bigint)     from public;
revoke all on function public.admin_apagar_enquete(bigint)       from public;
grant execute on function public.admin_painel()                   to service_role;
grant execute on function public.admin_status_ideia(bigint, text) to service_role;
grant execute on function public.admin_encerrar_enquete(bigint)   to service_role;
grant execute on function public.admin_apagar_enquete(bigint)     to service_role;
grant execute on function public.criar_enquete(text, text[], numeric) to service_role;
