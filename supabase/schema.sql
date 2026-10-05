-- ラマダッシュ ランキング用テーブルと関数
-- Supabase の SQL Editor に貼り付けて「Run」してください。

create table if not exists public.scores (
  player_id  uuid primary key,                         -- 書き込み用の秘密ID（各端末で生成）
  pub_id     text not null unique,                     -- 表示用の公開ID（自分の行の判別用）
  name       text not null check (char_length(name) between 1 and 12),
  best       integer not null check (best >= 0 and best <= 10000000),
  updated_at timestamptz not null default now()
);

create index if not exists scores_best_idx on public.scores (best desc, updated_at asc);

-- テーブルへの直接アクセスは禁止し、下の関数経由だけにする
alter table public.scores enable row level security;
revoke all on table public.scores from anon, authenticated;

-- 自己ベストの送信：今より高いときだけ更新（オフライン中の記録を後から送っても安全）
create or replace function public.submit_score(p_player_id uuid, p_pub_id text, p_name text, p_best integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]<>]', '', 'g'));
begin
  if p_best is null or p_best < 0 or p_best > 10000000 then
    raise exception 'invalid score';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 12 then
    raise exception 'invalid name';
  end if;
  if p_pub_id is null or p_pub_id !~ '^[0-9a-f]{12}$' then
    raise exception 'invalid id';
  end if;

  insert into public.scores (player_id, pub_id, name, best, updated_at)
  values (p_player_id, p_pub_id, v_name, p_best, now())
  on conflict (player_id) do update
    set name       = excluded.name,
        best       = greatest(public.scores.best, excluded.best),
        updated_at = case when excluded.best > public.scores.best then now() else public.scores.updated_at end;
end;
$$;

-- ランキング上位（同点は先に出した人が上）
create or replace function public.get_leaderboard(p_limit integer default 50)
returns table (pub_id text, name text, best integer, updated_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select s.pub_id, s.name, s.best, s.updated_at
  from public.scores s
  order by s.best desc, s.updated_at asc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

-- 指定スコアの順位
create or replace function public.get_rank(p_best integer)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select (count(*) + 1)::integer from public.scores where best > p_best;
$$;

revoke all on function public.submit_score(uuid, text, text, integer) from public;
revoke all on function public.get_leaderboard(integer) from public;
revoke all on function public.get_rank(integer) from public;
grant execute on function public.submit_score(uuid, text, text, integer) to anon, authenticated;
grant execute on function public.get_leaderboard(integer) to anon, authenticated;
grant execute on function public.get_rank(integer) to anon, authenticated;
