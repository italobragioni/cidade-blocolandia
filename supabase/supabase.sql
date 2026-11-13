-- ============================================================
-- Cidade Blocolândia — banco de dados (Supabase / Postgres)
-- Cole tudo no SQL Editor do Supabase e clique em "Run".
-- ============================================================

-- 1) Tabela de moradores
create table if not exists public.moradores (
  numero     integer primary key,                 -- nº do morador (sem buracos)
  handle     text not null unique,                -- @ em minúsculas, sem o "@"
  criado_em  timestamptz not null default now(),
  constraint handle_valido check (handle ~ '^[a-z0-9._]{1,30}$')
);

-- Ninguém lê nem escreve na tabela diretamente: só pelas funções abaixo.
alter table public.moradores enable row level security;
revoke all on public.moradores from anon, authenticated;

-- 2) Pegar casa: devolve o morador existente ou cria o próximo número
create or replace function public.pegar_casa(p_handle text)
returns table (numero integer, handle text, criado_em timestamptz, novo boolean)
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
    return query select r.numero, r.handle, r.criado_em, false;
    return;
  end if;

  -- trava curta para dois cadastros simultâneos não pegarem o mesmo número
  perform pg_advisory_xact_lock(424242);

  select * into r from public.moradores m where m.handle = h;   -- confere de novo
  if found then
    return query select r.numero, r.handle, r.criado_em, false;
    return;
  end if;

  insert into public.moradores (numero, handle)
  values ((select coalesce(max(m.numero), 0) + 1 from public.moradores m), h)
  returning * into r;

  return query select r.numero, r.handle, r.criado_em, true;
end $$;

-- 3) Buscar por @ (não cria nada)
create or replace function public.buscar_morador(p_handle text)
returns table (numero integer, handle text, criado_em timestamptz)
language sql stable security definer set search_path = public
as $$
  select m.numero, m.handle, m.criado_em from public.moradores m
  where m.handle = lower(regexp_replace(trim(p_handle), '^@+', ''));
$$;

-- 4) Buscar por número (usado quando tocam numa casa no mapa)
create or replace function public.morador_por_numero(p_numero integer)
returns table (numero integer, handle text, criado_em timestamptz)
language sql stable security definer set search_path = public
as $$
  select m.numero, m.handle, m.criado_em from public.moradores m where m.numero = p_numero;
$$;

-- 5) Total de moradores (contador da página e casas do mapa)
create or replace function public.total_moradores()
returns integer
language sql stable security definer set search_path = public
as $$ select coalesce(max(numero), 0) from public.moradores; $$;

-- Libera só as funções para o site (chave pública "anon")
revoke all on function public.pegar_casa(text)          from public;
revoke all on function public.buscar_morador(text)      from public;
revoke all on function public.morador_por_numero(integer) from public;
revoke all on function public.total_moradores()         from public;
grant execute on function public.pegar_casa(text)            to anon, authenticated, service_role;
grant execute on function public.buscar_morador(text)        to anon, authenticated;
grant execute on function public.morador_por_numero(integer) to anon, authenticated;
grant execute on function public.total_moradores()           to anon, authenticated;

-- 6) O prefeito é o morador nº 1
insert into public.moradores (numero, handle) values (1, 'cidadeblocolandia')
on conflict do nothing;
