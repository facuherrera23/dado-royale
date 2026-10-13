-- =============================================================
-- Fase 14 · Estadísticas personales por juego
--   won  = manos ganadas (dados/póker: is_winner; blackjack: win|blackjack)
--   lost = manos perdidas (cualquier otra terminada sin push)
--   net  = suma de TODOS los movimientos del ledger del juego
--          (bet_lock + payout + refund) → beneficio neto real
-- =============================================================

create or replace function public.get_my_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with my_hands as (
    select t.game, rp.is_winner, rp.result, rp.bet_amount, rp.round_id
      from public.round_players rp
      join public.rounds r on r.id = rp.round_id and r.status = 'finished'
      join public.tables t on t.id = r.table_id
     where rp.user_id = auth.uid()
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'game', g.game,
           'played', g.played,
           'won', g.won,
           'lost', g.lost,
           'pushed', g.pushed,
           'wagered', g.wagered,
           'net', coalesce((
              select sum(l.amount) from public.ledger l
               join public.rounds r on r.id = l.round_id
               join public.tables t on t.id = r.table_id
              where l.user_id = auth.uid() and t.game = g.game), 0)
        ) order by g.game), '[]'::jsonb)
  from (
    select game,
           count(*) as played,
           count(*) filter (where is_winner or result in ('win','blackjack')) as won,
           count(*) filter (where result = 'loss' or (result is null and not is_winner)) as lost,
           count(*) filter (where result = 'push') as pushed,
           coalesce(sum(bet_amount), 0) as wagered
      from my_hands
     group by game
  ) g;
$$;

grant execute on function public.get_my_stats() to authenticated;
revoke all on function public.get_my_stats() from public, anon;
