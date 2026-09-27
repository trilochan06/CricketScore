// Request-driven (serverless) version of the tracker for hosts like Vercel.
//
// There's no always-on poller: each request fetches what it needs from ESPN, and the
// HTTP responses are cached at the CDN edge for a few seconds (see api/). So no matter
// how many people are watching, ESPN sees roughly one request per match per few seconds.
// Warm function instances also keep a tiny in-memory cache.
import * as source from './espn.js';
import { buildScorecard, mergeBallState, compareMatches, COMMENTARY_ITEMS } from './scorecard.js';

const LIST_TTL_MS = 10000;
let listCache = { at: 0, matches: null, pending: null };
const pageCounts = new Map(); // matchId → last known commentary pageCount

export async function getMatches() {
  const now = Date.now();
  if (listCache.matches && now - listCache.at < LIST_TTL_MS) return listCache.matches;
  if (!listCache.pending) {
    listCache.pending = source.fetchMatches()
      .then((list) => {
        listCache = { at: Date.now(), matches: list.sort(compareMatches), pending: null };
        return listCache.matches;
      })
      .catch((err) => {
        listCache.pending = null;
        if (listCache.matches) return listCache.matches; // serve stale on upstream hiccups
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
