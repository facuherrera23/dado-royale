-- =============================================================
-- Fase 12 · get_leaderboard con filtro por juego
-- =============================================================

drop function if exists public.get_leaderboard(int);

create or replace function public.get_leaderboard(p_limit int default 10, p_game text default null)
returns table (username text, rounds_won bigint, total_won bigint)
language sql
stable
security definer
set search_path = public
as $$
  select pr.username,
         (select count(*) from public.round_players rp
                 join public.rounds r on r.id = rp.round_id
                 join public.tables t on t.id = r.table_id
            where rp.user_id = pr.id
              and (rp.is_winner or rp.result in ('win','blackjack'))
              and (p_game is null or t.game = p_game)) as rounds_won,
         coalesce((select sum(l.amount) from public.ledger l
                     left join public.rounds r2 on r2.id = l.round_id
                     left join public.tables t2 on t2.id = r2.table_id
                    where l.user_id = pr.id and l.type = 'payout'
                      and (l.round_id is null or t2.game = p_game)), 0) as total_won
    from public.profiles pr
   order by total_won desc, rounds_won desc, pr.username
   limit greatest(1, least(p_limit, 100));
$$;

grant execute on function public.get_leaderboard(int, text) to authenticated;
