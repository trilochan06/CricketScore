// Request-driven data layer: fetch what's needed from the source, with a small in-memory
// cache. Runs in the browser (each visitor reads ESPN's public, CORS-enabled feed directly,
// like ESPN's own site) and in Node.
import * as source from './espn.js';
import { buildScorecard, mergeBallState, compareMatches, COMMENTARY_ITEMS } from './scorecard.js';

const LIST_TTL_MS = 10000;
const STALE_GRACE_MS = 30000;
let listCache = { at: 0, matches: null, pending: null };
const pageCounts = new Map(); // matchId → last known commentary pageCount
// Some live matches (often domestic) have no ball-by-ball feed and only occasional total
// updates. Probe each in-progress match once (cached) so covered matches can be preferred.
const COVERAGE_TTL_MS = 10 * 60000;
const coverage = new Map();   // matchId → { has: boolean, at: ms }
const IN_PROGRESS = new Set(['live', 'inningsBreak', 'rainDelay']);

async function probeCoverage(match) {
  try {
    const page = await source.fetchCommentaryPage(match.leagueId, match.id);
    coverage.set(match.id, { has: page.balls.some((b) => b.text), at: Date.now() });
  } catch { /* unknown: treat as covered */ }
}

function withCoverage(list) {
  return list.map((m) => {
    const c = coverage.get(m.id);
    return c ? { ...m, hasBallByBall: c.has } : m;
  });
}

export async function getMatches() {
  const now = Date.now();
  if (listCache.matches && now - listCache.at < LIST_TTL_MS) return listCache.matches;
  if (!listCache.pending) {
    listCache.pending = source.fetchMatches()
      .then(async (list) => {
        const stale = list.filter((m) => IN_PROGRESS.has(m.status) && !(Date.now() - (coverage.get(m.id)?.at ?? 0) < COVERAGE_TTL_MS));
        await Promise.all(stale.slice(0, 8).map(probeCoverage));
        listCache = { at: Date.now(), matches: withCoverage(list).sort(compareMatches), pending: null };
        return listCache.matches;
      })
      .catch((err) => {
        listCache.pending = null;
        // Ride out a brief hiccup with the last list, but don't hide a real outage:
        // after STALE_GRACE_MS the error surfaces so the UI can say it's reconnecting.
        if (listCache.matches && Date.now() - listCache.at < STALE_GRACE_MS) return listCache.matches;
        throw err;
      });
  }
  return listCache.pending;
}

export async function getScorecard(id) {
  const matches = await getMatches();
  const match = matches.find((m) => m.id === id);
  if (!match) return null;
  if (match.status === 'upcoming') return buildScorecard(match, []);

  const balls = await fetchRecentBalls(match);
  if (balls.length <= 1 && !balls.some((b) => b.text)) {
    coverage.set(match.id, { has: false, at: Date.now() });
    return buildScorecard({ ...match, hasBallByBall: false }, []);
  }
  const merged = mergeBallState(match, balls);
  return buildScorecard(merged, balls);
}

/** Newest ~2 pages of ball-by-ball (usually 1–2 upstream requests). */
async function fetchRecentBalls(match) {
  let pageCount = pageCounts.get(match.id);
  let pages = [];
  if (!pageCount) {
    const first = await source.fetchCommentaryPage(match.leagueId, match.id);
    pageCount = first.pageCount;
    if (pageCount === 1) pages = [first];
    else pages = [await source.fetchCommentaryPage(match.leagueId, match.id, pageCount)];
  } else {
    const last = await source.fetchCommentaryPage(match.leagueId, match.id, pageCount);
    pages = [last];
    if (last.pageCount > pageCount) {
      pageCount = last.pageCount;
      pages.push(await source.fetchCommentaryPage(match.leagueId, match.id, pageCount));
    }
  }
  pageCounts.set(match.id, pageCount);

  // Top up with the previous page when the newest page is nearly empty.
  const have = pages.reduce((n, p) => n + p.balls.length, 0);
  if (have < COMMENTARY_ITEMS && pageCount > 1) {
    pages.push(await source.fetchCommentaryPage(match.leagueId, match.id, pageCount - 1));
  }
  const byId = new Map();
  for (const p of pages) for (const b of p.balls) byId.set(b.id, b);
  return [...byId.values()];
}
