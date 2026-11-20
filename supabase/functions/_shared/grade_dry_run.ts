import { gradeBet, isDeferredMarket, leaveOpen, type EventScores } from './grading.ts';
import { decideParlay } from './parlay_settle.ts';
import { gradeProp, resolvePropTarget, type Statline } from './prop_stats.ts';
import { settlementAmount, type GradeResult } from './settlement_math.ts';

/**
 * What the grader would do, with no place to write.
 *
 * The client type has selects only. runGradeDryRun never calls insert,
 * update, upsert, delete, or rpc, and it never stores an idempotency key.
 * Callers that need a box score pass loadStatline; that callback is a read.
 */

export interface ReadResult<T> {
  data: T | null;
  error: { message: string } | null;
}

export interface ReadBuilder extends PromiseLike<ReadResult<Record<string, unknown>[]>> {
  select(columns: string): ReadBuilder;
  eq(column: string, value: unknown): ReadBuilder;
  in(column: string, values: unknown[]): ReadBuilder;
  limit(count: number): ReadBuilder;
  maybeSingle(): Promise<ReadResult<Record<string, unknown>>>;
}

export interface ReadClient {
  from(table: string): ReadBuilder;
}

export interface StatlineLoad {
  statline: Statline | null;
  statsFinal: boolean;
  note?: string;
}

export interface DryRunLeg {
  bet_id: string;
  market: string | null;
  result: string;
  detail: string;
  source?: string;
  stat_key?: string | null;
  actual?: number | null;
  line?: number | null;
  subject_player_id?: number | null;
  odds?: number;
}

export interface DryRunReport {
  dry_run: true;
  writes: 0;
  kind: 'single' | 'parlay';
  result: string;
  payout: number | null;
  profit: number | null;
  decimal_odds: number | null;
  detail: string;
  legs: DryRunLeg[];
}

type LoadStatline = (
  event: Record<string, unknown>,
  subjectPlayerId: number,
) => Promise<StatlineLoad>;

function num(value: unknown): number {
  const n = typeof value === 'number' ? value : parseFloat(String(value));
  return Number.isFinite(n) ? n : 0;
}

async function one(
  client: ReadClient,
  table: string,
  column: string,
  value: unknown,
): Promise<Record<string, unknown> | null> {
  const { data, error } = await client.from(table).select('*').eq(column, value).maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

async function many(
  client: ReadClient,
  table: string,
  column: string,
  value: unknown,
): Promise<Record<string, unknown>[]> {
  const { data, error } = await client.from(table).select('*').eq(column, value);
  if (error) throw new Error(error.message);
  return data ?? [];
}

async function gradeOneLeg(
  client: ReadClient,
  bet: Record<string, unknown>,
  loadStatline: LoadStatline,
): Promise<DryRunLeg> {
  const marketName = (bet.market as string | null) ?? null;
  const betId = String(bet.id);

  if (marketName === 'player_prop' || bet.stat_key) {
    const market = bet.market_id
      ? await one(client, 'markets', 'id', bet.market_id)
      : null;
    const target = resolvePropTarget(
      {
        stat_key: bet.stat_key as string | null,
        subject_player_id: bet.subject_player_id as number | null,
        side: bet.side as string | null,
      },
      market
        ? {
          stat_key: market.stat_key as string | null,
          subject_player_id: market.subject_player_id as number | null,
        }
        : null,
    );
    if ('error' in target) {
      return { bet_id: betId, market: marketName, result: 'pending', detail: target.error };
    }
    const event = bet.event_id ? await one(client, 'events', 'id', bet.event_id) : null;
    if (!event) {
      return { bet_id: betId, market: marketName, result: 'pending', detail: 'event not found; left pending' };
    }
    const loaded = await loadStatline(event, target.subjectPlayerId);
    if (loaded.note && !loaded.statsFinal) {
      return {
        bet_id: betId,
        market: marketName,
        result: 'pending',
        detail: loaded.note,
        source: target.source,
        stat_key: target.statKey,
        subject_player_id: target.subjectPlayerId,
      };
    }
    const outcome = gradeProp(target.statKey, target.side, loaded.statline, { statsFinal: loaded.statsFinal });
    return {
      bet_id: betId,
      market: marketName,
      result: outcome.result,
      detail: outcome.detail,
      source: target.source,
      stat_key: outcome.stat_key ?? target.statKey,
      actual: outcome.actual ?? null,
      line: outcome.line ?? null,
      subject_player_id: target.subjectPlayerId,
      odds: num(bet.odds),
    };
  }

  if (isDeferredMarket(marketName)) {
    return {
      bet_id: betId,
      market: marketName,
      result: 'pending',
      detail: 'futures are not auto-graded; left pending',
    };
  }

  const event = bet.event_id ? await one(client, 'events', 'id', bet.event_id) : null;
  if (
    event &&
    event.status === 'final' &&
    event.home_score != null &&
    event.away_score != null &&
    marketName
  ) {
    const scores: EventScores = {
      homeScore: num(event.home_score),
      awayScore: num(event.away_score),
      homeTeam: String(event.home_team ?? ''),
      awayTeam: String(event.away_team ?? ''),
    };
    const graded = gradeBet({ id: betId, market: marketName, side: String(bet.side ?? '') }, scores);
    if (leaveOpen(graded.result)) {
      return { bet_id: betId, market: marketName, result: 'pending', detail: graded.gradeDetails };
    }
    return {
      bet_id: betId,
      market: marketName,
      result: graded.result,
      detail: graded.gradeDetails,
      odds: num(bet.odds),
    };
  }

  if (bet.grade_result) {
    return {
      bet_id: betId,
      market: marketName,
      result: String(bet.grade_result),
      detail: 'using the grade already stored on the leg',
      odds: num(bet.odds),
    };
  }

  return { bet_id: betId, market: marketName, result: 'pending', detail: 'not final yet; left pending' };
}

export async function runGradeDryRun(
  client: ReadClient,
  args: { bet_id?: string; ticket_id?: string },
  loadStatline: LoadStatline,
): Promise<DryRunReport | { error: string }> {
  let legs: Record<string, unknown>[] = [];

  if (args.ticket_id) {
    legs = await many(client, 'bets', 'ticket_id', args.ticket_id);
    if (legs.length === 0) return { error: 'No bets for that parlay' };
  } else if (args.bet_id) {
    const bet = await one(client, 'bets', 'id', args.bet_id);
    if (!bet) return { error: 'Bet not found' };
    if (bet.is_parlay && bet.ticket_id) {
      legs = await many(client, 'bets', 'ticket_id', bet.ticket_id);
    } else {
      legs = [bet];
    }
  } else {
    return { error: 'Provide bet_id or ticket_id' };
  }

  const graded = [];
  for (const leg of legs) graded.push(await gradeOneLeg(client, leg, loadStatline));

  if (legs.length === 1 && !legs[0].is_parlay) {
    const leg = graded[0];
    const payable = leg.result === 'win' || leg.result === 'loss' || leg.result === 'push' || leg.result === 'void';
    const payout = payable
      ? settlementAmount(leg.result as GradeResult, num(legs[0].stake), num(legs[0].odds))
      : null;
    const profit = leg.result === 'win' && payout != null ? Math.round(-payout * 100) / 100 : leg.result === 'win' ? null : 0;
    return {
      dry_run: true,
      writes: 0,
      kind: 'single',
      result: leg.result,
      payout,
      profit: payable ? profit : null,
      decimal_odds: null,
      detail: leg.detail,
      legs: graded,
    };
  }

  const decision = decideParlay(
    num(legs[0].stake),
    graded.map((leg, i) => ({
      status: leg.result === 'void' ? 'void' : String(legs[i].status ?? ''),
      grade_result: leg.result === 'pending' ? null : leg.result,
      odds: num(legs[i].odds),
    })),
  );

  return {
    dry_run: true,
    writes: 0,
    kind: 'parlay',
    result: decision.action === 'settle' ? (decision.outcome ?? 'pending') : 'pending',
    payout: decision.action === 'settle' ? (decision.amount ?? null) : null,
    profit: decision.action === 'settle' ? (decision.profit ?? null) : null,
    decimal_odds: decision.decimalOdds ?? null,
    detail: decision.detail,
    legs: graded,
  };
}
