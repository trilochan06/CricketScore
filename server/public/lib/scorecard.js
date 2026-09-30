// Pure functions that turn normalized matches + balls into the public scorecard shape.
// Shared by the always-on server (tracker.js) and the serverless API (stateless.js).
import { ballsToOvers } from './espn.js';

export const RECENT_BALLS = 12;
export const COMMENTARY_ITEMS = 18;

export function latestOf(balls) {
  let latest = null;
  for (const b of balls) if (!latest || b.sequence > latest.sequence) latest = b;
  return latest;
}

/** Overlay the newest ball's score onto the (slower) match list so both agree. */
export function mergeBallState(match, balls, { lastBallAt = 0 } = {}) {
  if (!balls.length) return match;
  const latest = latestOf(balls);
  const m = structuredClone(match);
  const s = latest.state;
  let inn = m.innings.find((i) => i.period === latest.inningsNumber);
  if (!inn) {
    const team = m.teams.find((t) => t.short === latest.teamShort) ?? m.teams[0];
    inn = { period: latest.inningsNumber, teamId: team?.id ?? '', team: latest.teamShort || team?.short, runs: 0, wickets: 0, balls: 0, overs: '0', isCurrent: true };
    m.innings.push(inn);
    m.innings.sort((a, b) => a.period - b.period);
  }
  // ESPN's match list lags the ball feed (it can say "innings break" / "stumps" for a while
  // after play resumes). A ball beyond the list's score in an unfinished match means play is on.
  const aheadOfList = s.balls > inn.balls;
  if (aheadOfList && (m.status === 'inningsBreak' || m.status === 'rainDelay')) m.status = 'live';
  if (s.balls >= inn.balls) {
    inn.runs = s.runs;
    inn.wickets = s.wickets;
    inn.balls = s.balls;
    inn.overs = ballsToOvers(s.balls);
  }
  if (s.target) m.target = s.target;
  // A ball within the last 90 s means play is on, whatever the (slower) list says.
  if (lastBallAt && m.status !== 'completed' && m.status !== 'abandoned' && Date.now() - lastBallAt < 90000) {
    m.status = 'live';
  }
  if (m.status === 'live' && /won toss|elected to|chose to/i.test(m.statusText) && s.runRate != null) {
    m.statusText = `${latest.teamShort} ${s.runs}/${s.wickets} · run rate ${s.runRate.toFixed(2)}`;
  }
  if (m.status === 'live' && s.remainingRuns != null && s.remainingBalls != null && s.target) {
    const need = s.remainingRuns, left = s.remainingBalls;
    m.statusText = `${latest.teamShort} need ${need} run${need === 1 ? '' : 's'} from ${left} ball${left === 1 ? '' : 's'}`;
  }
  return m;
}

export function buildScorecard(match, balls) {
  const base = {
    match, batters: [], bowler: null, recentBalls: [], commentary: [], partnership: null, lastWicket: null,
    currentRunRate: null, requiredRunRate: null, target: match.target, runsRequired: null, ballsRemaining: null,
    updatedAt: new Date().toISOString(),
  };
  if (!balls.length) return base;

  const all = [...balls].sort((a, b) => a.sequence - b.sequence);
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
  const hasTarget = !!s.target && !!s.ballLimit && match.status !== 'completed' && match.status !== 'abandoned';

  return {
    ...base,
    batters,
    bowler: atCrease ? latest.bowler : null,
    recentBalls: sameInnings.slice(-RECENT_BALLS).map(publicBall),
    commentary: all.slice(-COMMENTARY_ITEMS).reverse().map((b) => ({
      id: b.id, over: b.overText, text: b.text, kind: b.kind, label: b.label, type: b.outcome.type, dismissal: b.dismissalText || null,
    })),
    lastWicket: lastWicketBall ? shortenDismissal(lastWicketBall.dismissalText) : null,
    currentRunRate: s.runRate,
    requiredRunRate: hasTarget ? s.requiredRunRate : null,
    target: s.target ?? match.target,
    runsRequired: hasTarget ? s.remainingRuns : null,
    ballsRemaining: hasTarget ? s.remainingBalls : null,
  };
}

/** Runs physically run by the batters (decides whether they crossed). */
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
  // "JD Campbell c Prasidh Krishna b Kuldeep Yadav 62 (88m 60b 6x4 3x6) SR: 103.33" → "… 62 (60)"
  const m = text.match(/^(.*?\d+)\s*\((?:\d+m\s*)?(\d+)b/);
  return m ? `${m[1]} (${m[2]})` : text.split(' (')[0];
}

const STATUS_RANK = { live: 0, rainDelay: 1, inningsBreak: 1, upcoming: 2, completed: 3, abandoned: 4 };

export function compareMatches(a, b) {
  const r = (STATUS_RANK[a.status] ?? 9) - (STATUS_RANK[b.status] ?? 9);
  if (r) return r;
  if (a.isInternational !== b.isInternational) return a.isInternational ? -1 : 1;
  return (a.startDate ?? '').localeCompare(b.startDate ?? '');
}
