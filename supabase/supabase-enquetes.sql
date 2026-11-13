-- ============================================================
-- Cidade Blocolândia — enquetes (votação entre opções)
-- Cole tudo no SQL Editor do Supabase e clique em "Run".
--
-- COMO CRIAR UMA ENQUETE (no SQL Editor):
--   select criar_enquete('Qual vai ser o próximo episódio?',
--                        array['Parque de diversões', 'Dia de chuva', 'Eleição pra prefeito'],
--                        3);   -- dura 3 dias
--
-- COMO ENCERRAR ANTES DO PRAZO:
--   update enquetes set encerra_em = now() where id = 1;
-- ============================================================

create table if not exists public.enquetes (
  id          bigint generated always as identity primary key,
  pergunta    text not null check (char_length(pergunta) between 3 and 140),
  criado_em   timestamptz not null default now(),
  encerra_em  timestamptz not null
);

create table if not exists public.opcoes_enquete (
  id          bigint generated always as identity primary key,
  enquete_id  bigint not null references public.enquetes(id) on delete cascade,
  texto       text not null check (char_length(texto) between 1 and 80),
  ordem       integer not null default 0
);

create table if not exists public.votos_enquete (
  enquete_id  bigint  not null references public.enquetes(id) on delete cascade,
  morador     integer not null references public.moradores(numero),
  opcao_id    bigint  not null references public.opcoes_enquete(id) on delete cascade,
  criado_em   timestamptz not null default now(),
  primary key (enquete_id, morador)            -- 1 voto por morador em cada enquete
);
create index if not exists votos_enquete_opcao_idx on public.votos_enquete (opcao_id);

alter table public.enquetes       enable row level security;
alter table public.opcoes_enquete enable row level security;
alter table public.votos_enquete  enable row level security;
revoke all on public.enquetes, public.opcoes_enquete, public.votos_enquete from anon, authenticated;

-- Criar enquete (só você, pelo SQL Editor)
create or replace function public.criar_enquete(p_pergunta text, p_opcoes text[], p_dias numeric default 3)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  novo bigint;
  i integer;
begin
  if array_length(p_opcoes, 1) is null or array_length(p_opcoes, 1) < 2 or array_length(p_opcoes, 1) > 6 then
    raise exception 'A enquete precisa ter de 2 a 6 opções';
  end if;
  insert into enquetes (pergunta, encerra_em)
  values (btrim(p_pergunta), now() + make_interval(secs => (p_dias * 86400)::double precision))
  returning id into novo;
  for i in 1 .. array_length(p_opcoes, 1) loop
    insert into opcoes_enquete (enquete_id, texto, ordem) values (novo, btrim(p_opcoes[i]), i);
  end loop;
  return novo;
end $$;

-- Lista para o site: enquetes abertas + as 2 últimas encerradas, com contagem e o voto de quem está vendo
create or replace function public.listar_enquetes(p_handle text default null)
returns json
language sql stable security definer set search_path = public
as $$
  with eu as (
    select numero from moradores
    where handle = lower(regexp_replace(trim(coalesce(p_handle, '')), '^@+', ''))
  ),
  e as (
    (select * from enquetes where encerra_em > now())
    union all
    (select * from enquetes where encerra_em <= now() order by encerra_em desc limit 2)
  )
  select coalesce(json_agg(json_build_object(
    'id', e.id,
    'pergunta', e.pergunta,
    'encerra_em', e.encerra_em,
    'aberta', e.encerra_em > now(),
    'meu_voto', (select v.opcao_id from votos_enquete v join eu on v.morador = eu.numero where v.enquete_id = e.id),
    'opcoes', (select json_agg(json_build_object(
                  'id', o.id, 'texto', o.texto,
                  'votos', (select count(*) from votos_enquete v where v.opcao_id = o.id))
                order by o.ordem, o.id)
               from opcoes_enquete o where o.enquete_id = e.id)
  ) order by (e.encerra_em > now()) desc, e.criado_em desc), '[]'::json)
  from e;
$$;

-- Votar (só pela função, depois do captcha). Votar em outra opção troca o voto.
create or replace function public.votar_enquete(p_handle text, p_opcao bigint)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
  enq bigint;
begin
  select numero into n from moradores where handle = lower(regexp_replace(trim(p_handle), '^@+', ''));
  if not found then raise exception 'nao_morador'; end if;

  select o.enquete_id into enq
  from opcoes_enquete o join enquetes e on e.id = o.enquete_id
  where o.id = p_opcao and e.encerra_em > now();
  if not found then raise exception 'enquete_encerrada'; end if;

  insert into votos_enquete (enquete_id, morador, opcao_id) values (enq, n, p_opcao)
  on conflict (enquete_id, morador) do update set opcao_id = excluded.opcao_id, criado_em = now();
  return p_opcao;
end $$;

revoke all on function public.criar_enquete(text, text[], numeric) from public;
revoke all on function public.listar_enquetes(text)                 from public;
revoke all on function public.votar_enquete(text, bigint)           from public;
grant execute on function public.listar_enquetes(text)       to anon, authenticated, service_role;
grant execute on function public.votar_enquete(text, bigint) to service_role;
