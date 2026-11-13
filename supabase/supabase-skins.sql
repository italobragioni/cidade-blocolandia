-- ============================================================
-- Cidade Blocolândia — skins (roupas dos bonecos)
-- Cole tudo no SQL Editor do Supabase e clique em "Run".
-- Pra adicionar uma skin nova no futuro, ela precisa existir no site
-- e na lista de skins_validas() abaixo.
-- ============================================================

alter table public.moradores add column if not exists skin text not null default 'casual';

create or replace function public.skins_validas()
returns text[]
language sql immutable
as $$ select array['casual','ninja','bombeiro','policial','medico','astronauta','chef','jogador','heroi','pirata','construtor','rei'] $$;

-- Trocar a skin (só pela função, depois do captcha)
create or replace function public.trocar_skin(p_handle text, p_skin text)
returns text
language plpgsql security definer set search_path = public
as $$
begin
  if not (p_skin = any (skins_validas())) then raise exception 'skin_invalida'; end if;
  update moradores set skin = p_skin where handle = lower(regexp_replace(trim(p_handle), '^@+', ''));
  if not found then raise exception 'nao_morador'; end if;
  return p_skin;
end $$;

-- As funções que devolvem morador passam a devolver a skin também
drop function if exists public.buscar_morador(text);
create function public.buscar_morador(p_handle text)
returns table (numero integer, handle text, criado_em timestamptz, skin text)
language sql stable security definer set search_path = public
as $$
  select m.numero, m.handle, m.criado_em, m.skin from public.moradores m
  where m.handle = lower(regexp_replace(trim(p_handle), '^@+', ''));
$$;

drop function if exists public.morador_por_numero(integer);
create function public.morador_por_numero(p_numero integer)
returns table (numero integer, handle text, criado_em timestamptz, skin text)
language sql stable security definer set search_path = public
as $$
  select m.numero, m.handle, m.criado_em, m.skin from public.moradores m where m.numero = p_numero;
$$;

drop function if exists public.pegar_casa(text);
create function public.pegar_casa(p_handle text)
returns table (numero integer, handle text, criado_em timestamptz, novo boolean, skin text)
language plpgsql
security definer
set search_path = public
as $$
declare
  h text := lower(regexp_replace(trim(p_handle), '^@+', ''));
  r public.moradores;
begin
  if h !~ '^[a-z0-9._]{1,30}$' then
    raise exception 'handle_invalido';
  end if;

  select * into r from public.moradores m where m.handle = h;
  if found then
    return query select r.numero, r.handle, r.criado_em, false, r.skin;
    return;
  end if;

  perform pg_advisory_xact_lock(424242);

  select * into r from public.moradores m where m.handle = h;
  if found then
    return query select r.numero, r.handle, r.criado_em, false, r.skin;
    return;
  end if;

  insert into public.moradores (numero, handle)
  values ((select coalesce(max(m.numero), 0) + 1 from public.moradores m), h)
  returning * into r;

  return query select r.numero, r.handle, r.criado_em, true, r.skin;
end $$;

-- Permissões (pegar_casa e trocar_skin: só pela função com captcha)
revoke all on function public.buscar_morador(text)        from public;
revoke all on function public.morador_por_numero(integer) from public;
revoke all on function public.pegar_casa(text)            from public;
revoke all on function public.trocar_skin(text, text)     from public;
grant execute on function public.buscar_morador(text)        to anon, authenticated, service_role;
grant execute on function public.morador_por_numero(integer) to anon, authenticated, service_role;
grant execute on function public.pegar_casa(text)            to service_role;
grant execute on function public.trocar_skin(text, text)     to service_role;
