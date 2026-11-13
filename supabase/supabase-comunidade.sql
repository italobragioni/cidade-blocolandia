-- ============================================================
-- Cidade Blocolândia — comunidade de ideias
-- Cole tudo no SQL Editor do Supabase e clique em "Run".
-- Moderação: no Table Editor → ideias, mude "status" para
--   'feita'  → vai para a aba "Feitas" (virou vídeo)
--   'oculta' → some do site
-- ============================================================

create table if not exists public.ideias (
  id         bigint generated always as identity primary key,
  texto      text not null check (char_length(texto) between 10 and 140),
  autor      integer not null references public.moradores(numero),
  status     text not null default 'nova' check (status in ('nova','feita','oculta')),
  criado_em  timestamptz not null default now(),
  feita_em   timestamptz
);

create table if not exists public.votos (
  ideia_id   bigint  not null references public.ideias(id) on delete cascade,
  morador    integer not null references public.moradores(numero),
  criado_em  timestamptz not null default now(),
  primary key (ideia_id, morador)
);

create index if not exists ideias_status_idx on public.ideias (status, criado_em desc);
create index if not exists votos_ideia_idx  on public.votos (ideia_id, criado_em);

alter table public.ideias enable row level security;
alter table public.votos  enable row level security;
revoke all on public.ideias from anon, authenticated;
revoke all on public.votos  from anon, authenticated;

-- quando você marca como 'feita', guarda a data
create or replace function public.marcar_feita() returns trigger
language plpgsql as $$
begin
  if new.status = 'feita' and old.status is distinct from 'feita' then new.feita_em := now(); end if;
  return new;
end $$;
drop trigger if exists ideias_feita on public.ideias;
create trigger ideias_feita before update on public.ideias for each row execute function public.marcar_feita();

-- Lista pública. p_aba: 'semana' | 'novas' | 'feitas'
create or replace function public.listar_ideias(p_aba text, p_handle text default null)
returns table (id bigint, texto text, autor_handle text, autor_numero integer,
               votos bigint, votos_semana bigint, criado_em timestamptz, status text, votei boolean)
language sql stable security definer set search_path = public
as $$
  with eu as (
    select numero from moradores
    where handle = lower(regexp_replace(trim(coalesce(p_handle, '')), '^@+', ''))
  ),
  base as (
    select i.id, i.texto, m.handle as autor_handle, m.numero as autor_numero,
           (select count(*) from votos v where v.ideia_id = i.id) as votos,
           (select count(*) from votos v where v.ideia_id = i.id and v.criado_em > now() - interval '7 days') as votos_semana,
           i.criado_em, i.status, i.feita_em,
           exists (select 1 from votos v join eu on v.morador = eu.numero where v.ideia_id = i.id) as votei
    from ideias i join moradores m on m.numero = i.autor
    where (p_aba = 'feitas' and i.status = 'feita') or (p_aba <> 'feitas' and i.status = 'nova')
  )
  select b.id, b.texto, b.autor_handle, b.autor_numero, b.votos, b.votos_semana, b.criado_em, b.status, b.votei
  from base b
  order by
    case when p_aba = 'semana' then b.votos_semana end desc nulls last,
    case when p_aba = 'semana' then b.votos end desc nulls last,
    case when p_aba = 'feitas' then b.feita_em end desc nulls last,
    b.criado_em desc
  limit 60;
$$;

-- Envio de ideia (só pela função, depois do captcha). Até 3 ideias por morador por dia.
create or replace function public.enviar_ideia(p_handle text, p_texto text)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
  t text := btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g'));
  novo_id bigint;
begin
  select numero into n from moradores where handle = lower(regexp_replace(trim(p_handle), '^@+', ''));
  if not found then raise exception 'nao_morador'; end if;
  if char_length(t) < 10 or char_length(t) > 140 then raise exception 'texto_invalido'; end if;
  if (select count(*) from ideias where autor = n and criado_em > now() - interval '1 day') >= 3 then
    raise exception 'limite';
  end if;
  insert into ideias (texto, autor) values (t, n) returning id into novo_id;
  return novo_id;
end $$;

-- Voto (só pela função). Votar de novo tira o voto.
create or replace function public.votar(p_handle text, p_ideia bigint)
returns table (votei boolean, votos bigint)
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
  marcou boolean;
begin
  select numero into n from moradores where handle = lower(regexp_replace(trim(p_handle), '^@+', ''));
  if not found then raise exception 'nao_morador'; end if;
  if not exists (select 1 from ideias where id = p_ideia and status = 'nova') then raise exception 'ideia_invalida'; end if;

  delete from votos v where v.ideia_id = p_ideia and v.morador = n;
  if found then
    marcou := false;
  else
    insert into votos (ideia_id, morador) values (p_ideia, n);
    marcou := true;
  end if;
  return query select marcou, (select count(*) from votos v where v.ideia_id = p_ideia);
end $$;

revoke all on function public.listar_ideias(text, text) from public;
revoke all on function public.enviar_ideia(text, text)  from public;
revoke all on function public.votar(text, bigint)       from public;
grant execute on function public.listar_ideias(text, text) to anon, authenticated, service_role;
grant execute on function public.enviar_ideia(text, text)  to service_role;
grant execute on function public.votar(text, bigint)       to service_role;
