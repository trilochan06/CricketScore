// ESPN (ESPNcricinfo) data source adapter.
//
// Uses ESPN's public, keyless JSON endpoints — the same ones their own site uses.
// They are unofficial and undocumented: fine for a personal / non-commercial project,
// but they may change without notice, and ESPN's terms don't grant reuse rights.
// Swap this adapter for a licensed provider before going commercial — every other
// part of the server only depends on the normalized shapes returned here.

const SCOREPANEL_URL = 'https://site.api.espn.com/apis/site/v2/sports/cricket/scorepanel';
const PLAYBYPLAY_URL = (leagueId, eventId, page) =>
  `https://site.web.api.espn.com/apis/site/v2/sports/cricket/${leagueId}/playbyplay?event=${eventId}` +
  (page ? `&page=${page}` : '');

export const SOURCE_NAME = 'ESPNcricinfo';
export const SOURCE_URL = 'https://www.espncricinfo.com/';

const IS_BROWSER = typeof window !== 'undefined';
// Browsers set their own User-Agent (and a custom one would force a CORS preflight).
const HEADERS = IS_BROWSER ? { accept: 'application/json' } : { accept: 'application/json', 'user-agent': 'CricketLive/1.0 (+personal project; polite polling)' };

async function getJSON(url, { timeoutMs = 12000 } = {}) {
  const res = await fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(timeoutMs) });
  if (!res.ok) throw new Error(`ESPN ${res.status} for ${url}`);
  return res.json();
}

// ───────────────────────── Matches ─────────────────────────

/** All matches ESPN currently lists (live, today's upcoming, recent results). */
export async function fetchMatches() {
  const data = await getJSON(SCOREPANEL_URL);
  const matches = [];
  for (const group of data.scores ?? []) {
    const league = group.leagues?.[0] ?? {};
    for (const event of group.events ?? []) {
      try {
        matches.push(normalizeEvent(event, league));
      } catch (err) {
        console.warn(`skip event ${event?.id}: ${err.message}`);
      }
    }
  }
  return matches;
}

const INTERNATIONAL_FORMATS = new Set(['Test', 'ODI', 'T20I', 'WODI', 'WT20I', 'Women\'s Test']);

export function normalizeEvent(event, league) {
  const comp = event.competitions?.[0] ?? {};
  const competitors = [...(comp.competitors ?? [])].sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
  const teams = competitors.map((c) => ({
    id: String(c.team?.id ?? c.id ?? ''),
    name: c.team?.displayName ?? c.team?.name ?? 'TBC',
    short: c.team?.abbreviation ?? c.team?.shortDisplayName ?? abbreviate(c.team?.displayName ?? 'TBC'),
    color: normalizeColor(c.team?.color),
  }));

  // Innings = linescores where that team was batting, ordered by period.
  const innings = [];
  competitors.forEach((c, i) => {
    for (const ls of c.linescores ?? []) {
      if (!ls.isBatting) continue;
      innings.push({
        period: ls.period ?? innings.length + 1,
        teamId: teams[i].id,
        team: teams[i].short,
        runs: toInt(ls.runs),
        wickets: toInt(ls.wickets),
        balls: oversToBalls(ls.overs),
        overs: ballsToOvers(oversToBalls(ls.overs)),
        isCurrent: ls.isCurrent === 1 || ls.isCurrent === true,
      });
    }
  });
  innings.sort((a, b) => a.period - b.period);

  const cls = comp.class ?? {};
  const format = mapFormat(cls.generalClassCard ?? cls.eventType ?? '');
  const statusType = event.status?.type ?? comp.status?.type ?? {};
  const summary = decodeEntities(comp.status?.summary ?? event.status?.summary ?? '').trim();
  let status = mapStatus(statusType, summary);
  if (status === 'live' && innings.length === 0 && /starts at|yet to begin|scheduled/i.test(summary)) status = 'upcoming';

  let target = null;
  const limited = format === 'odi' || format === 't20' || format === 't10';
  if (limited && innings.length >= 2) target = innings[0].runs + 1;

  const eventLink = (event.links ?? []).find((l) => (l.rel ?? []).includes('summary'))?.href ?? null;

  return {
    id: String(event.id),
    leagueId: String(league.id ?? event.season?.type ?? ''),
    series: league.name ?? '',
    title: comp.description ?? '',
    format,
    formatLabel: cls.generalClassCard ?? '',
    isInternational: INTERNATIONAL_FORMATS.has(cls.generalClassCard) || (cls.internationalClassId && cls.internationalClassId !== '0' && cls.internationalClassId !== ''),
    venue: comp.venue?.fullName ?? '',
    startDate: event.date ? new Date(event.date).toISOString() : null,
    status,
    statusText: summary || statusType.description || '',
    teams,
    innings,
    target,
    result: status === 'completed' || status === 'abandoned' ? (summary || statusType.description || null) : null,
    // ESPN's playByPlayAvailable flag is unreliable; the tracker learns this from the data itself.
    hasBallByBall: true,
    link: eventLink,
  };
}

function mapStatus(type, summary) {
  const state = type.state;
  const desc = `${type.description ?? ''} ${type.detail ?? ''}`.toLowerCase();
  if (state === 'pre') return 'upcoming';
  if (state === 'post') {
    return /abandon|no result|cancel/.test(`${desc} ${summary.toLowerCase()}`) ? 'abandoned' : 'completed';
  }
  if (/rain|delay|bad light|wet|weather/.test(desc)) return 'rainDelay';
  if (/innings break|stumps|lunch|tea|drinks|break/.test(desc)) return 'inningsBreak';
  return 'live';
}

function mapFormat(card) {
  const c = card.toUpperCase();
  if (c.includes('TEST') || c.includes('FIRST-CLASS') || c.includes('FC')) return 'test';
  if (c.includes('T10')) return 't10';
  if (c.includes('T20') || c.includes('HUNDRED')) return 't20';
  if (c.includes('ODI') || c.includes('LIST A') || c.includes('50')) return 'odi';
  return 'other';
}

// ───────────────────────── Ball by ball ─────────────────────────

/**
 * Fetches one page of commentary. Page 1 is the oldest; `pageCount` is the newest.
 * Returns { count, pageCount, balls[] } with balls normalized.
 */
export async function fetchCommentaryPage(leagueId, eventId, page) {
  const data = await getJSON(PLAYBYPLAY_URL(leagueId, eventId, page));
  const c = data.commentary ?? {};
  return {
    count: toInt(c.count),
    pageCount: Math.max(1, toInt(c.pageCount)),
    balls: (c.items ?? []).map(normalizeBall).filter(Boolean),
  };
}

export function normalizeBall(item) {
  if (!item || item.sequence == null) return null;
  const outcome = mapOutcome(item);
  const inn = item.innings ?? {};
  const over = item.over ?? {};
  return {
    id: String(item.sequence),
    sequence: toInt(item.sequence),
    inningsNumber: toInt(inn.number ?? item.period),
    teamShort: item.team?.abbreviation ?? '',
    over: toInt(over.number) - 1, // zero-based over index (used for over separators)
    overText: over.overs != null ? String(over.overs) : '',
    outcome,
    label: labelFor(outcome),
    kind: outcome.type === 'four' || outcome.type === 'six' || outcome.type === 'wicket' ? outcome.type : null,
    text: decodeEntities(item.shortText ?? '').trim(),
    dismissalText: item.dismissal?.dismissal ? decodeEntities(item.dismissal.text ?? '').trim() : '',
    batter: batterFrom(item.batsman, true),
    otherBatter: batterFrom(item.otherBatsman, false),
    bowler: bowlerFrom(item.bowler),
    state: {
      runs: toInt(inn.runs),
      wickets: toInt(inn.wickets),
      balls: toInt(inn.balls),
      target: toIntOrNull(inn.target),
      runRate: toFloatOrNull(inn.runRate),
      requiredRunRate: toFloatOrNull(inn.requiredRunRate),
      remainingRuns: toIntOrNull(inn.remainingRuns),
      remainingBalls: toIntOrNull(inn.remainingBalls),
      ballLimit: toIntOrNull(inn.ballLimit),
    },
  };
}

function mapOutcome(item) {
  const typeId = String(item.playType?.id ?? '');
  const desc = (item.playType?.description ?? '').toLowerCase();
  const runs = toInt(item.scoreValue);
  if (item.dismissal?.dismissal || typeId === '9' || desc === 'out') return { type: 'wicket', runs };
  if (typeId === '4' || desc === 'six') return { type: 'six', runs };
  if (typeId === '3' || desc === 'four') return { type: 'four', runs };
  if (typeId === '6' || desc.includes('wide')) return { type: 'wide', runs: Math.max(runs, 1) };
  if (typeId === '5' || desc.includes('no ball')) return { type: 'noBall', runs: Math.max(runs, 1) };
  if (typeId === '8' || desc.includes('leg bye')) return { type: 'legBye', runs };
  if (typeId === '7' || desc.includes('bye')) return { type: 'bye', runs };
  if (runs === 0) return { type: 'dot', runs: 0 };
  return { type: 'runs', runs };
}

function labelFor({ type, runs }) {
  switch (type) {
    case 'dot': return '•';
    case 'runs': return String(runs);
    case 'four': return '4';
    case 'six': return '6';
    case 'wicket': return 'W';
    case 'wide': return runs > 1 ? `${runs}wd` : 'wd';
    case 'noBall': return runs > 1 ? `${runs}nb` : 'nb';
    case 'bye': return `${runs}b`;
    case 'legBye': return `${runs}lb`;
    default: return '?';
  }
}

function batterFrom(b, faced) {
  if (!b?.athlete) return null;
  return {
    name: decodeEntities(b.athlete.displayName ?? b.athlete.name ?? 'Batter'),
    runs: toInt(b.totalRuns),
    balls: toInt(b.faced),
    fours: toInt(b.fours),
    sixes: toInt(b.sixes),
    faced,
  };
}

function bowlerFrom(b) {
  if (!b?.athlete) return null;
  return {
    name: decodeEntities(b.athlete.displayName ?? b.athlete.name ?? 'Bowler'),
    balls: toInt(b.balls),
    maidens: toInt(b.maidens),
    runs: toInt(b.conceded),
    wickets: toInt(b.wickets),
  };
}

// ───────────────────────── helpers ─────────────────────────

export function oversToBalls(overs) {
  const o = Number(overs);
  if (!Number.isFinite(o) || o <= 0) return 0;
  const whole = Math.trunc(o);
  const part = Math.round((o - whole) * 10);
  return whole * 6 + Math.min(Math.max(part, 0), 5);
}

export function ballsToOvers(balls) {
  const b = Math.max(0, balls | 0);
  return b % 6 === 0 ? String(b / 6) : `${Math.trunc(b / 6)}.${b % 6}`;
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', dagger: '†', Dagger: '‡', ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘' };

/** ESPN text contains HTML entities (e.g. "c &dagger;Cloete" marks the keeper). */
export function decodeEntities(s) {
  return String(s)
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&([a-z]+);/gi, (m, name) => ENTITIES[name] ?? m);
}

function toInt(v) {
  const n = typeof v === 'string' ? parseFloat(v) : v;
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}
function toIntOrNull(v) {
  const n = typeof v === 'string' ? parseFloat(v) : v;
  return Number.isFinite(n) && n > 0 ? Math.trunc(n) : null;
}
function toFloatOrNull(v) {
  const n = typeof v === 'string' ? parseFloat(v) : v;
  return Number.isFinite(n) && n >= 0 ? n : null;
}
function normalizeColor(c) {
  if (!c) return null;
  const hex = c.startsWith('#') ? c : `#${c}`;
  return /^#[0-9a-f]{6}$/i.test(hex) ? hex : null;
}
function abbreviate(name) {
  const words = name.split(/\s+/).filter(Boolean);
  return (words.length > 1 ? words.slice(0, 3).map((w) => w[0]).join('') : name.slice(0, 3)).toUpperCase();
}
