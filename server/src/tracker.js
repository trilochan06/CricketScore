import { EventEmitter } from 'node:events';
import * as source from './espn.js';

const cfg = {
  ballIntervalMs: Number(process.env.BALL_POLL_MS ?? 8000),        // per live match, while someone is watching
  listIntervalMs: Number(process.env.LIST_POLL_MS ?? 30000),       // match list
  idleBallIntervalMs: Number(process.env.IDLE_BALL_POLL_MS ?? 60000),
  idleListIntervalMs: Number(process.env.IDLE_LIST_POLL_MS ?? 180000),
  idleAfterMs: Number(process.env.IDLE_AFTER_MS ?? 5 * 60000),
  maxTracked: Number(process.env.MAX_TRACKED_MATCHES ?? 12),
  recentBalls: 12,
  commentaryItems: 18,
  keepBalls: 60,
};

const STATUS_RANK = { live: 0, rainDelay: 1, inningsBreak: 1, upcoming: 2, completed: 3, abandoned: 4 };

/**
 * Polls the data source (one request per live match per interval, regardless of how
 * many viewers there are), detects new deliveries, and emits:
 *   'matches' (list)                – the match list changed
 *   'update'  ({ match, scorecard }) – a match's score/details changed
 *   'ball'    ({ matchId, ball })    – a new delivery was bowled (drives the 4 / 6 / W animations)
 */
export class Tracker extends EventEmitter {
  constructor() {
    super();
    this.setMaxListeners(0);
    this.matches = new Map();   // id → normalized match
    this.states = new Map();    // id → ball-by-ball state
    this.scorecards = new Map(); // id → last built scorecard
    this.lastActivity = Date.now();
    this.viewers = 0;
    this.lastListError = null;
    this.stopped = false;
  }

  // ── lifecycle ──

  async start() {
    await this.#refreshList().catch((e) => console.error('initial list failed:', e.message));
    this.#loop('list', () => this.#refreshList(), () => (this.#isIdle() ? cfg.idleListIntervalMs : cfg.listIntervalMs));
    this.#loop('balls', () => this.#pollAllBalls(), () => (this.#isIdle() ? cfg.idleBallIntervalMs : cfg.ballIntervalMs));
  }

  stop() { this.stopped = true; }

  /** Call on every API request / SSE connection so polling speeds up for viewers. */
  touch() { this.lastActivity = Date.now(); }

  #isIdle() {
    return this.viewers === 0 && Date.now() - this.lastActivity > cfg.idleAfterMs;
  }

  #loop(name, fn, interval) {
    const tick = async () => {
      if (this.stopped) return;
      try { await fn(); } catch (e) { console.error(`${name} poll failed:`, e.message); }
      setTimeout(tick, interval()).unref?.();
    };
    setTimeout(tick, interval()).unref?.();
  }

  // ── public reads ──

  list() {
    return [...this.matches.values()].sort(compareMatches);
  }

  health() {
    return {
      ok: !this.lastListError,
      source: source.SOURCE_NAME,
      matches: this.matches.size,
      tracked: [...this.states.keys()].length,
      viewers: this.viewers,
      idle: this.#isIdle(),
      lastListError: this.lastListError,
    };
  }

  /** Scorecard for a match; fetches on demand for matches we aren't actively polling. */
  async scorecard(id) {
    const match = this.matches.get(id);
    if (!match) return null;
    const cached = this.scorecards.get(id);
    const state = this.states.get(id);
    const fresh = state && Date.now() - state.polledAt < Math.max(cfg.ballIntervalMs * 2, 20000);
    if (cached && (fresh || match.status === 'upcoming')) return cached;
    if (match.status === 'upcoming' || !match.hasBallByBall) return this.#buildScorecard(match, null);
    await this.#pollBalls(match).catch((e) => console.warn(`on-demand ${id}:`, e.message));
    return this.scorecards.get(id) ?? this.#buildScorecard(match, null);
  }

  // ── polling ──

  async #refreshList() {
    let list;
    try {
      list = await source.fetchMatches();
      this.lastListError = null;
    } catch (e) {
      this.lastListError = e.message;
      throw e;
    }
    const seen = new Set();
    let changed = false;
    for (const m of list) {
      seen.add(m.id);
      let merged = this.#mergeBallState(m);
      if (this.states.get(m.id)?.noData) merged = { ...merged, hasBallByBall: false };
      const prev = this.matches.get(m.id);
      if (!prev || JSON.stringify(prev) !== JSON.stringify(merged)) {
        this.matches.set(m.id, merged);
        changed = true;
        if (prev) this.#rebuild(m.id);
      }
    }
    for (const id of [...this.matches.keys()]) {
      if (!seen.has(id)) {
        this.matches.delete(id);
        this.states.delete(id);
        this.scorecards.delete(id);
        changed = true;
      }
    }
    if (changed) this.emit('matches', this.list());
  }

  async #pollAllBalls() {
    const live = this.list()
      .filter((m) => m.hasBallByBall && (m.status === 'live' || m.status === 'rainDelay' || m.status === 'inningsBreak'))
      .slice(0, cfg.maxTracked);
    // Breaks and rain change slowly: poll them at the list cadence instead.
    const due = live.filter((m) => {
      const known = this.states.get(m.id);
      if (known?.noData && Date.now() - known.polledAt < 5 * 60000) return false; // recheck every 5 min
      if (m.status === 'live') return true;
      const st = this.states.get(m.id);
      return !st || Date.now() - st.polledAt > cfg.listIntervalMs;
    });
    await Promise.allSettled(due.map((m) => this.#pollBalls(m)));
  }

  async #pollBalls(match) {
    let st = this.states.get(match.id);
    if (!st) {
      st = { balls: new Map(), maxSeq: 0, pageCount: 0, count: 0, initialized: false, polledAt: 0, lastBallAt: 0 };
      this.states.set(match.id, st);
    }

    // Normally one request: the newest page. On first load, also the page before it
    // so there are enough balls for "recent balls" and the commentary feed.
    const pages = [];
    if (!st.pageCount) {
      const first = await source.fetchCommentaryPage(match.leagueId, match.id);
      if (first.pageCount > 1) {
        pages.push(await source.fetchCommentaryPage(match.leagueId, match.id, first.pageCount));
        if (pages[0].balls.length < cfg.commentaryItems && first.pageCount > 2) {
          pages.push(await source.fetchCommentaryPage(match.leagueId, match.id, first.pageCount - 1));
        } else if (first.pageCount === 2) {
          pages.push(first);
        }
      } else {
        pages.push(first);
      }
    } else {
      const latest = await source.fetchCommentaryPage(match.leagueId, match.id, st.pageCount);
      pages.push(latest);
      // A new page started since the last poll: fetch the new pages too.
      for (let p = st.pageCount + 1; p <= latest.pageCount; p++) {
        pages.push(await source.fetchCommentaryPage(match.leagueId, match.id, p));
      }
    }

    st.polledAt = Date.now();
    // Minor matches return a single empty placeholder item: no ball-by-ball coverage.
    const allBalls = pages.flatMap((p) => p.balls);
    st.noData = allBalls.length <= 1 && !allBalls.some((b) => b.text);
    if (st.noData) {
      st.balls.clear();
      const m = this.matches.get(match.id);
      if (m && m.hasBallByBall) this.matches.set(match.id, { ...m, hasBallByBall: false });
      return;
    }
    const newest = pages.reduce((a, p) => Math.max(a, p.pageCount), 0);
    st.pageCount = newest || st.pageCount;

    const fresh = [];
    for (const page of pages) {
      for (const ball of page.balls) {
        const prev = st.balls.get(ball.id);
        st.balls.set(ball.id, ball); // corrections overwrite silently
        if (!prev && ball.sequence > st.maxSeq) fresh.push(ball);
      }
    }
    fresh.sort((a, b) => a.sequence - b.sequence);
    if (fresh.length) {
      st.maxSeq = fresh[fresh.length - 1].sequence;
      // Only balls that arrive while we're watching prove play is on (not the history on first load).
      if (st.initialized) st.lastBallAt = Date.now();
    }
    // Trim memory.
    if (st.balls.size > cfg.keepBalls) {
      const keep = [...st.balls.values()].sort((a, b) => b.sequence - a.sequence).slice(0, cfg.keepBalls);
      st.balls = new Map(keep.map((b) => [b.id, b]));
    }

    const wasInitialized = st.initialized;
    st.initialized = true;

    const current = this.matches.get(match.id) ?? match;
    this.matches.set(match.id, this.#mergeBallState(current));
    const changed = this.#rebuild(match.id);

    // Only announce balls that happened after we started watching (no replay of history).
    if (wasInitialized) {
      for (const ball of fresh) this.emit('ball', { matchId: match.id, ball });
    }
    if (changed && fresh.length) this.emit('matches', this.list());
  }

  // ── state building ──

  /** Overlay the newest ball's score onto the (slower) match list so both stay in sync. */
  #mergeBallState(match) {
    const st = this.states.get(match.id);
    if (!st || !st.balls.size) return match;
    const latest = latestBall(st);
    const m = structuredClone(match);
    const s = latest.state;
    let inn = m.innings.find((i) => i.period === latest.inningsNumber);
    if (!inn) {
      const team = m.teams.find((t) => t.short === latest.teamShort) ?? m.teams[0];
      inn = { period: latest.inningsNumber, teamId: team?.id ?? '', team: latest.teamShort || team?.short, runs: 0, wickets: 0, balls: 0, overs: '0', isCurrent: true };
      m.innings.push(inn);
      m.innings.sort((a, b) => a.period - b.period);
    }
    if (s.balls >= inn.balls) {
      inn.runs = s.runs;
      inn.wickets = s.wickets;
      inn.balls = s.balls;
      inn.overs = source.ballsToOvers(s.balls);
    }
    if (s.target) m.target = s.target;
    // A ball in the last 90 s means play is on, whatever the (slower) list says.
    if (m.status !== 'completed' && m.status !== 'abandoned' && Date.now() - st.lastBallAt < 90000 && st.lastBallAt) {
      m.status = 'live';
    }
    if (m.status === 'live' && s.remainingRuns != null && s.remainingBalls != null && s.target) {
      const need = s.remainingRuns, left = s.remainingBalls;
      m.statusText = `${latest.teamShort} need ${need} run${need === 1 ? '' : 's'} from ${left} ball${left === 1 ? '' : 's'}`;
    }
    return m;
  }

  /** Rebuilds a match's scorecard; emits 'update' and returns true if anything changed. */
  #rebuild(id) {
    const match = this.matches.get(id);
    if (!match) return false;
    const card = this.#buildScorecard(match, this.states.get(id));
    const prev = this.scorecards.get(id);
    const strip = (c) => JSON.stringify({ ...c, updatedAt: 0 });
    if (prev && strip(prev) === strip(card)) return false;
    this.scorecards.set(id, card);
    this.emit('update', { match, scorecard: card });
    return true;
  }

  #buildScorecard(match, st) {
    const empty = {
      match, batters: [], bowler: null, recentBalls: [], commentary: [], partnership: null, lastWicket: null,
      currentRunRate: null, requiredRunRate: null, target: match.target, runsRequired: null, ballsRemaining: null,
      updatedAt: new Date().toISOString(),
    };
    if (!st || !st.balls.size) return empty;

    const all = [...st.balls.values()].sort((a, b) => a.sequence - b.sequence);
    const latest = all[all.length - 1];
    const sameInnings = all.filter((b) => b.inningsNumber === latest.inningsNumber);
    const s = latest.state;
    const atCrease = match.status === 'live' || match.status === 'rainDelay';

    // Who is on strike for the next ball.
    let batters = [];
    if (atCrease) {
      const out = latest.outcome.type === 'wicket';
      const crossed = runsRun(latest.outcome) % 2 === 1;
      const legal = latest.outcome.type !== 'wide' && latest.outcome.type !== 'noBall';
      const overEnded = legal && s.balls > 0 && s.balls % 6 === 0;
      const facerKeepsStrike = crossed === overEnded;
      const facer = latest.batter && { ...latest.batter, isStriker: !out && facerKeepsStrike };
      const other = latest.otherBatter && { ...latest.otherBatter, isStriker: out ? false : !facerKeepsStrike };
      batters = [facer, other].filter((b) => b && !(out && b === facer)).map(({ faced, ...b }) => b);
      batters.sort((a, b) => Number(b.isStriker) - Number(a.isStriker));
    }

    const lastWicketBall = [...sameInnings].reverse().find((b) => b.outcome.type === 'wicket');
    const hasTarget = !!s.target && !!s.ballLimit;

    return {
      match,
      batters,
      bowler: atCrease ? latest.bowler : null,
      recentBalls: sameInnings.slice(-cfg.recentBalls).map(publicBall),
      commentary: all.slice(-cfg.commentaryItems).reverse().map((b) => ({
        id: b.id, over: b.overText, text: b.text, kind: b.kind, label: b.label, dismissal: b.dismissalText || null,
      })),
      partnership: null,
      lastWicket: lastWicketBall ? shortenDismissal(lastWicketBall.dismissalText) : null,
      currentRunRate: s.runRate,
      requiredRunRate: hasTarget ? s.requiredRunRate : null,
      target: s.target ?? match.target,
      runsRequired: hasTarget ? s.remainingRuns : null,
      ballsRemaining: hasTarget ? s.remainingBalls : null,
      updatedAt: new Date().toISOString(),
    };
  }
}

function latestBall(st) {
  let latest = null;
  for (const b of st.balls.values()) if (!latest || b.sequence > latest.sequence) latest = b;
  return latest;
}

/** Runs physically run by the batters (determines whether they crossed). */
function runsRun({ type, runs }) {
  switch (type) {
    case 'runs': case 'bye': case 'legBye': return runs;
    case 'wide': case 'noBall': return Math.max(0, runs - 1);
    default: return 0;
  }
}

export function publicBall(b) {
  return { id: b.id, outcome: b.outcome, over: b.over, label: b.label, kind: b.kind, text: b.text };
}

function shortenDismissal(text) {
  if (!text) return null;
  // "JD Campbell c Prasidh Krishna b Kuldeep Yadav 62 (88m 60b 6x4 3x6) SR: 103.33" → up to the score + balls
  const m = text.match(/^(.*?\d+)\s*\((?:\d+m\s*)?(\d+)b/);
  return m ? `${m[1]} (${m[2]})` : text.split(' (')[0];
}

function compareMatches(a, b) {
  const r = (STATUS_RANK[a.status] ?? 9) - (STATUS_RANK[b.status] ?? 9);
  if (r) return r;
  if (a.isInternational !== b.isInternational) return a.isInternational ? -1 : 1;
  return (a.startDate ?? '').localeCompare(b.startDate ?? '');
}
