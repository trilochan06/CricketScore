// Cricket Live — browser client.
// Reads ESPNcricinfo's public, CORS-enabled feed directly from the visitor's browser
// (the same way ESPN's own site does), every few seconds, and detects new deliveries
// itself to trigger the FOUR / SIX / WICKET animations. The site is fully static.
import { getMatches, getScorecard } from '/lib/data.js';
import { Favorites, Alerts, MiniScore, Install, diffMatches } from '/features.js';

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

const state = {
  matches: [],
  selectedId: new URLSearchParams(location.hash.slice(1)).get('match') || safeGet('match'),
  card: null,
  showAll: safeGet('showAll') === '1',
  timers: [],
  failures: 0,
  seenBalls: new Set(),   // recent-ball ids already rendered (to animate only new ones)
  seenFeed: new Set(),
  prevScores: new Map(),
  fxQueue: [],
  fxBusy: false,
  userPicked: false,      // the visitor chose a match themselves (don't auto-switch)
};
// Opening a link to a specific match (e.g. one a friend shared) counts as choosing it.
if (new URLSearchParams(location.hash.slice(1)).get('match')) state.userPicked = true;

const IN_PROGRESS = ['live', 'inningsBreak', 'rainDelay'];
const STATUS_RANK = { live: 0, rainDelay: 1, inningsBreak: 1, upcoming: 2, completed: 3, abandoned: 4 };

function safeGet(k) { try { return localStorage.getItem(k); } catch { return null; } }
function safeSet(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } }

// ───────────────────────── Live updates ─────────────────────────

const CARD_INTERVAL_MS = 6000;       // polite: one small request per visitor every 6 s
const HIDDEN_CARD_INTERVAL_MS = 60000;
const LIST_INTERVAL_MS = 45000;

function connect() {
  state.timers.forEach(clearTimeout);
  state.timers = [];
  setConnection('Connecting…', 'muted');
  schedule(pollList, 0);
  if (state.selectedId) schedule(pollCard, 0);
}

function schedule(fn, ms) {
  state.timers.push(setTimeout(fn, ms));
}

async function pollList() {
  try {
    const previous = state.matches;
    state.matches = await getMatches();
    ok();
    if (previous.length) announce(diffMatches(previous, state.matches, { selectedId: state.selectedId }));
    ensureSelection();
    renderRail();
  } catch {
    fail();
  }
  schedule(pollList, LIST_INTERVAL_MS);
}

async function pollCard() {
  const id = state.selectedId;
  try {
    const card = await getScorecard(id);
    if (!card) throw new Error('match not found');
    if (id !== state.selectedId) return; // user switched matches meanwhile
    ok();
    const firstLoad = !state.card;
    // New deliveries since the last poll, oldest first → celebrations.
    const fresh = card.commentary.filter((c) => !state.seenFeed.has(c.id)).reverse();
    render(card);
    MiniScore.update(card);
    if (!firstLoad) {
      for (const c of fresh) {
        if (!c.kind) continue;
        if (!document.hidden) celebrate(c.kind, { text: c.text, dismissalText: c.dismissal });
        MiniScore.flash(c.kind);
        // Tab in the background: a system notification instead (if alerts are on).
        if (document.hidden) {
          const m = card.match;
          const word = { four: 'FOUR', six: 'SIX', wicket: 'WICKET' }[c.kind];
          Alerts.notify(`${word} · ${m.teams[0].short} v ${m.teams[1].short}`, c.dismissal || c.text, `ball-${m.id}`, `/#match=${m.id}`);
        }
      }
    }
  } catch {
    fail();
  }
  if (id === state.selectedId) schedule(pollCard, document.hidden ? HIDDEN_CARD_INTERVAL_MS : CARD_INTERVAL_MS);
}

function ok() {
  state.failures = 0;
  setConnection('Live', 'live');
}

function fail() {
  state.failures += 1;
  setConnection(state.failures > 2 ? 'Offline — retrying' : 'Reconnecting…', 'warn');
  // Nothing loaded yet: say so instead of an endless "Loading…" (keep last scores otherwise).
  if (!state.card && state.failures >= 2) {
    $('#scoreboard').innerHTML = '<div class="empty">Can\'t reach live scores right now — retrying automatically.</div>';
  }
}

// Back online: refresh immediately instead of waiting for the next scheduled check.
window.addEventListener('online', () => connect());

// Catch up immediately when the tab comes back.
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && state.selectedId) connect();
});

function setConnection(text, kind) {
  const el = $('#connection');
  el.textContent = text;
  el.className = `pill pill-${kind}`;
}

function visibleMatches() {
  // Default view: your teams, internationals, and anything in progress (live, break or rain).
  const featured = state.matches.filter((m) => Favorites.follows(m) || m.isInternational || IN_PROGRESS.includes(m.status));
  const list = state.showAll || featured.length === 0 ? state.matches : featured;
  return [...list].sort((a, b) => (STATUS_RANK[a.status] ?? 9) - (STATUS_RANK[b.status] ?? 9)
    || Number(Favorites.follows(b)) - Number(Favorites.follows(a)));
}

/** Live first, then breaks, then soonest upcoming — favorites before everything else. */
function bestMatch(list) {
  return list.find((m) => m.status === 'live') ?? list.find((m) => IN_PROGRESS.includes(m.status)) ?? list.find((m) => m.status === 'upcoming') ?? list[0];
}

function ensureSelection() {
  const list = visibleMatches();
  const current = state.matches.find((m) => m.id === state.selectedId);
  const favLive = state.matches.filter((m) => Favorites.follows(m) && IN_PROGRESS.includes(m.status));
  // A favorite team is playing and the visitor didn't pick something else: go there.
  if (!state.userPicked && favLive.length && !(current && Favorites.follows(current) && IN_PROGRESS.includes(current.status))) {
    const pick = bestMatch(favLive);
    if (pick && pick.id !== state.selectedId) return select(pick.id);
  }
  if (current) return;
  const favs = state.matches.filter((m) => Favorites.follows(m));
  const pick = (favs.length && bestMatch(favs.filter((m) => m.status !== 'completed' && m.status !== 'abandoned'))) || bestMatch(list);
  if (pick) select(pick.id);
}

function select(id) {
  if (id === state.selectedId && state.card) return;
  state.selectedId = id;
  state.card = null;
  state.seenBalls.clear();
  state.seenFeed.clear();
  state.prevScores.clear();
  safeSet('match', id);
  history.replaceState(null, '', `#match=${id}`);
  renderRail();
  $('#scoreboard').innerHTML = '<div class="skeleton">Loading…</div>';
  $('#players').hidden = true;
  $('#balls').hidden = true;
  $('#commentary').innerHTML = '';
  $('#updated').textContent = '';
  connect();
}

// ───────────────────────── Rendering ─────────────────────────

function renderRail() {
  const rail = $('#rail');
  const list = visibleMatches();
  if (!list.length) {
    rail.innerHTML = '';
    if (!state.card) $('#scoreboard').innerHTML = '<div class="empty">No matches right now — we\'ll pick one up automatically.</div>';
    return;
  }
  rail.innerHTML = list.map((m) => {
    const inn = m.innings.at(-1);
    const sub = m.status === 'upcoming' ? startLabel(m.startDate)
      : m.status === 'completed' || m.status === 'abandoned' ? 'Result'
      : inn ? `${inn.team} ${score(inn)} (${inn.overs})` : 'Live';
    return `<button class="chip" data-id="${esc(m.id)}" aria-pressed="${m.id === state.selectedId}">
      <i class="dot ${esc(m.status)}"></i>
      <span class="chip-title">${esc(m.teams[0]?.short)} v ${esc(m.teams[1]?.short)}${Favorites.follows(m) ? '<span class="star" aria-label="Your team">★</span>' : ''}</span>
      <span class="chip-sub">${esc(sub)}</span>
    </button>`;
  }).join('');
}

function render(card) {
  const first = !state.card;
  state.card = card;
  renderScoreboard(card, first);
  renderPlayers(card);
  renderBalls(card, first);
  renderCommentary(card, first);
  $('#updated').textContent = `Updated ${new Date(card.updatedAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })}`;
  $('#footer-link').innerHTML = card.match.link ? `<a href="${esc(card.match.link)}" target="_blank" rel="noopener">Full scorecard ↗</a>` : '';
  document.title = titleFor(card.match);
}

function renderScoreboard(card, first) {
  const m = card.match;
  const battingTeamId = ['live', 'rainDelay'].includes(m.status) ? m.innings.at(-1)?.teamId : null;
  const order = m.innings.length ? [m.innings[0].teamId, ...m.teams.map((t) => t.id).filter((id) => id !== m.innings[0].teamId)] : m.teams.map((t) => t.id);

  const teams = order.map((id) => {
    const team = m.teams.find((t) => t.id === id) ?? m.teams[0];
    const inns = m.innings.filter((i) => i.teamId === id);
    const text = inns.map(score).join(' & ');
    const last = inns.at(-1);
    const changed = !first && state.prevScores.has(id) && state.prevScores.get(id) !== text;
    state.prevScores.set(id, text);
    const dim = battingTeamId && battingTeamId !== id;
    return `<div class="team ${dim ? 'dim' : ''}">
      <span class="badge" style="--c:${esc(team.color ?? teamColor(team.short))}">${esc(badgeText(team.short))}</span>
      <span class="team-name"><span class="tn">${esc(team.name)}</span>${battingTeamId === id ? '<span class="bat-icon" title="Batting">🏏</span>' : ''}<button class="fav" data-team="${esc(team.name)}" aria-pressed="${Favorites.isExactFavorite(team.name) || Favorites.isFavorite(team)}" title="${Favorites.isFavorite(team) ? 'Unfollow' : 'Follow'} ${esc(team.name)}">${Favorites.isFavorite(team) ? '★' : '☆'}</button></span>
      ${last ? `<span class="team-score"><span class="${changed ? 'bump' : ''}">${esc(text)}</span></span>
        <span class="team-overs">${esc(last.overs)} ov</span>` : '<span class="yet">Yet to bat</span>'}
    </div>`;
  }).join('');

  let situation = '';
  if (card.runsRequired != null && card.ballsRemaining != null) {
    const team = m.innings.at(-1)?.team ?? '';
    situation = `<div class="equation">${esc(team)} need <b>${card.runsRequired}</b> run${card.runsRequired === 1 ? '' : 's'} from <b>${card.ballsRemaining}</b> ball${card.ballsRemaining === 1 ? '' : 's'}</div>`;
  } else if (m.status === 'upcoming') {
    situation = `<div class="banner">⏱ ${esc(startLabel(m.startDate, true))}</div>`;
  } else if (m.status === 'completed' || m.status === 'abandoned') {
    situation = `<div class="banner">✅ ${esc(m.result ?? m.statusText)}</div>`;
  } else if (m.status === 'inningsBreak') {
    situation = `<div class="banner">⏸ ${esc(m.statusText || 'Innings break')}</div>`;
  } else if (m.status === 'rainDelay') {
    situation = `<div class="banner">🌧 ${esc(m.statusText || 'Rain delay')}</div>`;
  } else if (m.statusText) {
    situation = `<div class="equation muted">${esc(m.statusText)}</div>`;
  }

  const stats = [
    card.currentRunRate != null && ['live', 'rainDelay'].includes(m.status) ? ['CRR', card.currentRunRate.toFixed(2)] : null,
    card.requiredRunRate != null ? ['RRR', card.requiredRunRate.toFixed(2)] : null,
    card.target ? ['TARGET', card.target] : null,
  ].filter(Boolean);

  const chase = card.target && card.runsRequired != null && ['live', 'rainDelay'].includes(m.status)
    ? `<div class="progress" title="Chase progress"><i style="width:${Math.min(100, ((card.target - card.runsRequired) / card.target) * 100).toFixed(1)}%"></i></div>` : '';

  $('#scoreboard').innerHTML = `
    <div class="sb-top">
      <span class="status ${esc(m.status)}">${statusLabel(m.status)}</span>
      ${m.link ? `<a class="sb-link" href="${esc(m.link)}" target="_blank" rel="noopener">ESPNcricinfo ↗</a>` : ''}
    </div>
    <h1 class="sb-title">${esc(m.teams.map((t) => t.name).join(' v '))}</h1>
    <div class="sb-sub">${esc([m.title, m.series, m.venue].filter(Boolean).join(' · '))}</div>
    <div class="teams">${teams}</div>
    ${situation}
    ${stats.length ? `<div class="chips">${stats.map(([k, v]) => `<span class="stat"><span>${k}</span><b>${esc(v)}</b></span>`).join('')}</div>` : ''}
    ${chase}`;
}

function renderPlayers(card) {
  const el = $('#players');
  if (!card.batters.length && !card.bowler) { el.hidden = true; return; }
  el.hidden = false;
  const bat = card.batters.map((b) => `<tr>
      <td class="${b.isStriker ? 'striker' : ''}">${esc(b.name)}</td>
      <td class="hi">${b.runs}</td><td>${b.balls}</td><td>${b.fours}</td><td>${b.sixes}</td>
      <td>${b.balls ? ((b.runs * 100) / b.balls).toFixed(1) : '–'}</td></tr>`).join('');
  const bw = card.bowler;
  const bowl = bw ? `<tr class="gap"><td colspan="6"></td></tr>
      <tr><th>Bowler</th><th>O</th><th>M</th><th>R</th><th>W</th><th>Econ</th></tr>
      <tr><td>${esc(bw.name)}</td><td>${overs(bw.balls)}</td><td>${bw.maidens}</td><td>${bw.runs}</td><td class="hi">${bw.wickets}</td>
      <td>${bw.balls ? ((bw.runs * 6) / bw.balls).toFixed(2) : '–'}</td></tr>` : '';
  el.innerHTML = `<table class="ptable">
      ${card.batters.length ? '<tr><th>Batter</th><th>R</th><th>B</th><th>4s</th><th>6s</th><th>SR</th></tr>' : ''}
      ${bat}${bowl}</table>
      ${card.lastWicket ? `<div class="lastwkt">Last wicket: ${esc(card.lastWicket)}</div>` : ''}`;
}

function renderBalls(card, first) {
  const el = $('#balls');
  if (!card.recentBalls.length) { el.hidden = true; return; }
  el.hidden = false;
  let prevOver = null;
  const html = card.recentBalls.map((b) => {
    const sep = prevOver !== null && b.over !== prevOver ? '<i class="over-sep"></i>' : '';
    prevOver = b.over;
    const isNew = !first && !state.seenBalls.has(b.id);
    state.seenBalls.add(b.id);
    return `${sep}${ballChip(b, isNew)}`;
  }).join('');
  el.innerHTML = `<h2>Recent balls</h2><div class="ball-row">${html}</div>`;
}

function renderCommentary(card, first) {
  const el = $('#commentary');
  if (!card.commentary.length) {
    el.innerHTML = `<li class="empty">${card.match.status === 'upcoming' ? 'Ball-by-ball starts when the match begins.' : 'No ball-by-ball coverage for this match.'}</li>`;
    return;
  }
  el.innerHTML = card.commentary.map((c) => {
    const isNew = !first && !state.seenFeed.has(c.id);
    state.seenFeed.add(c.id);
    return `<li class="${isNew ? 'new' : ''}">
      <span class="ov">${esc(c.over)}</span>
      ${ballChip({ label: c.label, kind: c.kind, outcome: { type: c.type ?? c.kind ?? guessType(c.label) } })}
      <span class="txt">${esc(c.text)}${c.dismissal ? `<span class="dismissal">${esc(c.dismissal)}</span>` : ''}</span>
    </li>`;
  }).join('');
}

function ballChip(b, isNew = false) {
  const t = b.outcome?.type ?? 'runs';
  const cls = t === 'wicket' ? 'wicket' : t === 'four' ? 'four' : t === 'six' ? 'six' : t === 'dot' ? 'dot'
    : ['wide', 'noBall', 'bye', 'legBye'].includes(t) ? 'extra' : 'runs';
  return `<span class="ball ${cls}${isNew ? ' new' : ''}" title="${esc(b.text ?? '')}">${esc(b.label)}</span>`;
}

function guessType(label) {
  if (label === '•') return 'dot';
  if (/wd|nb|lb|b$/.test(label)) return 'extra';
  return 'runs';
}

// ───────────────────────── Celebrations ─────────────────────────

function celebrate(kind, ball = {}) {
  if (state.fxQueue.length >= 3) state.fxQueue.shift(); // several at once: keep the latest few
  state.fxQueue.push({ kind, ball });
  if (!state.fxBusy) playNext();
}

function playNext() {
  const next = state.fxQueue.shift();
  if (!next) { state.fxBusy = false; return; }
  state.fxBusy = true;
  const { kind, ball } = next;
  const fx = $('#fx');
  const sb = $('#scoreboard');
  const words = { four: 'FOUR', six: 'SIX', wicket: 'WICKET' };
  const detail = ball.text ? esc(ball.text) : '';
  $('#announcer').textContent = `${words[kind]}! ${ball.text ?? ''}`;

  sb.classList.remove('flash-four', 'flash-six', 'flash-wicket');
  void sb.offsetWidth;
  sb.classList.add(`flash-${kind}`);

  fx.className = `fx fx-${kind}`;
  let duration;
  if (reduceMotion.matches) {
    fx.innerHTML = `<div class="toast">${words[kind]}</div>`;
    duration = 2200;
  } else if (kind === 'four') {
    fx.innerHTML = `<div class="veil"></div><div class="ring"></div><div class="ring"></div><div class="ring"></div>
      <div class="burst"><div class="big">4</div><div class="word">FOUR</div><div class="sub">${detail}</div></div>`;
    duration = 1900;
  } else if (kind === 'six') {
    const colors = ['#f0abfc', '#a855f7', '#facc15', '#38bdf8', '#fb7185', '#ffffff'];
    const sparks = Array.from({ length: 42 }, (_, i) => {
      const angle = (i / 42) * Math.PI * 2 + Math.random() * 0.3;
      const dist = 180 + Math.random() * 260;
      return `<i class="spark" style="--dx:${(Math.cos(angle) * dist).toFixed(0)}px;--dy:${(Math.sin(angle) * dist - 60).toFixed(0)}px;--rot:${(Math.random() * 720 - 360).toFixed(0)}deg;--d:${(0.18 + Math.random() * 0.15).toFixed(2)}s;--sc:${colors[i % colors.length]}"></i>`;
    }).join('');
    fx.innerHTML = `<div class="veil"></div>${sparks}
      <div class="burst"><div class="big">6</div><div class="word">SIX!</div><div class="sub">${detail}</div></div>`;
    duration = 2300;
  } else {
    const dismissal = ball.dismissalText || ball.text || '';
    fx.innerHTML = `<div class="veil"></div>
      <div class="burst">
        <svg class="stumps" viewBox="0 0 150 170" aria-hidden="true">
          <rect class="bail l" x="28" y="18" width="42" height="9" rx="4.5"/>
          <rect class="bail r" x="80" y="18" width="42" height="9" rx="4.5"/>
          <rect class="stump" x="30" y="30" width="14" height="140" rx="6"/>
          <rect class="stump mid" x="68" y="30" width="14" height="140" rx="6"/>
          <rect class="stump" x="106" y="30" width="14" height="140" rx="6"/>
        </svg>
        <div class="word">WICKET</div><div class="sub">${esc(dismissal)}</div>
      </div>`;
    duration = 2500;
  }
  setTimeout(() => {
    fx.innerHTML = '';
    fx.className = 'fx';
    setTimeout(playNext, 150);
  }, duration);
}

// ───────────────────────── Helpers ─────────────────────────

function badgeText(short) { return short.replace(/-W$|-A$|U19$|19$/, '').slice(0, 4); }
function score(i) { return i.wickets >= 10 ? `${i.runs}` : `${i.runs}/${i.wickets}`; }
function overs(balls) { return balls % 6 === 0 ? `${balls / 6}` : `${Math.floor(balls / 6)}.${balls % 6}`; }
function statusLabel(s) {
  return { live: 'LIVE', inningsBreak: 'INNINGS BREAK', rainDelay: 'RAIN DELAY', upcoming: 'UPCOMING', completed: 'RESULT', abandoned: 'NO RESULT' }[s] ?? s.toUpperCase();
}
function startLabel(iso, long = false) {
  if (!iso) return 'Upcoming';
  const d = new Date(iso);
  const mins = Math.round((d - Date.now()) / 60000);
  const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (mins <= 0) return long ? 'Starting soon' : 'Soon';
  if (mins < 60) return long ? `Starts in ${mins} min (${time})` : `in ${mins}m`;
  const sameDay = d.toDateString() === new Date().toDateString();
  return long ? `Starts ${sameDay ? 'today' : d.toLocaleDateString([], { weekday: 'short' })} at ${time}` : time;
}
function teamColor(short) {
  let h = 0;
  for (const ch of short) h = (h * 31 + ch.charCodeAt(0)) % 360;
  return `hsl(${h} 55% 45%)`;
}
function titleFor(m) {
  const inn = m.innings.at(-1);
  return inn && ['live', 'rainDelay', 'inningsBreak'].includes(m.status)
    ? `${inn.team} ${score(inn)} (${inn.overs}) · ${m.teams[0].short} v ${m.teams[1].short}`
    : `${m.teams[0].short} v ${m.teams[1].short} · Cricket Live`;
}

// ───────────────────────── Wiring ─────────────────────────

$('#rail').addEventListener('click', (e) => {
  const chip = e.target.closest('.chip');
  if (chip) { state.userPicked = true; select(chip.dataset.id); }
});

const allToggle = $('#show-all');
allToggle.checked = state.showAll;
allToggle.addEventListener('change', () => {
  state.showAll = allToggle.checked;
  safeSet('showAll', state.showAll ? '1' : '0');
  renderRail();
});

window.addEventListener('hashchange', () => {
  const id = new URLSearchParams(location.hash.slice(1)).get('match');
  if (id && id !== state.selectedId) select(id);
});

// ───────────────────────── Favorites, alerts, pop-out, install ─────────────────────────

$('#scoreboard').addEventListener('click', (e) => {
  const star = e.target.closest('.fav');
  if (!star) return;
  const name = star.dataset.team;
  // Unfollowing a variant (e.g. "India A" while following "India") removes the base favorite.
  const base = Favorites.list().find((f) => name.toLowerCase() === f.toLowerCase() || name.toLowerCase().startsWith(f.toLowerCase() + ' '));
  const nowFollowing = Favorites.toggle(base ?? name);
  toast(nowFollowing ? 'info' : 'info', nowFollowing ? `Following ${base ?? name}` : `Unfollowed ${base ?? name}`,
    nowFollowing ? 'Their matches come first' + (Alerts.enabled ? ' and you’ll get alerts.' : ' — turn on Alerts to get notified.') : '');
  if (state.card) render(state.card);
  renderRail();
});

function toast(kind, title, body = '') {
  const el = document.createElement('div');
  el.className = `toast-item ${kind}`;
  el.innerHTML = `<b>${esc(title)}</b>${esc(body)}`;
  $('#toasts').append(el);
  setTimeout(() => el.remove(), 5000);
}

/** Alert events for followed matches: notification if allowed (and in background), toast when visible. */
function announce(events) {
  for (const ev of events) {
    if (!document.hidden) toast(ev.kind, ev.title, ev.body);
    else Alerts.notify(ev.title, ev.body, `${ev.kind}-${ev.match.id}`, `/#match=${ev.match.id}`);
  }
}

const alertsBtn = $('#btn-alerts');
function syncAlertsButton() {
  alertsBtn.setAttribute('aria-pressed', String(Alerts.enabled));
  alertsBtn.querySelector('span').textContent = Alerts.enabled ? 'Alerts on' : 'Alerts';
  if (!Alerts.supported) alertsBtn.hidden = true;
}
alertsBtn.addEventListener('click', async () => {
  if (Alerts.enabled) {
    Alerts.disable();
    toast('info', 'Alerts off');
  } else {
    const result = await Alerts.enable();
    if (result === 'granted') {
      toast('info', 'Alerts on', Favorites.list().length ? 'Wickets, starts and results for your teams — and 4s, 6s and wickets when this tab is in the background.' : 'Tap ☆ next to a team to follow it.');
      Alerts.notify('Cricket Live alerts are on', 'You’ll be notified about your teams’ matches.', 'welcome');
    } else if (result === 'denied') {
      toast('wicket', 'Notifications are blocked', 'Allow notifications for this site in your browser settings, then try again.');
    } else if (result === 'unsupported') {
      toast('wicket', 'Not supported here', 'On iPhone, install the app to your Home Screen first, then turn on alerts.');
    }
  }
  syncAlertsButton();
});
syncAlertsButton();

const popBtn = $('#btn-popout');
if (MiniScore.mode) popBtn.hidden = false;
popBtn.addEventListener('click', async () => {
  if (MiniScore.isOpen) { MiniScore.close(); popBtn.setAttribute('aria-pressed', 'false'); return; }
  if (!state.card) return toast('info', 'Pick a match first');
  try {
    const opened = await MiniScore.open(state.card, () => popBtn.setAttribute('aria-pressed', 'false'));
    popBtn.setAttribute('aria-pressed', String(opened));
  } catch (err) {
    toast('wicket', 'Couldn’t pop out the score', 'Your browser blocked the floating window. Try Chrome or Edge.');
  }
});

const installBtn = $('#btn-install');
function syncInstallButton() { installBtn.hidden = Install.isInstalled; }
Install.init(syncInstallButton);
syncInstallButton();
async function startInstall() {
  const outcome = await Install.prompt();
  if (outcome !== 'manual') return;
  const { title, steps } = Install.instructions();
  $('#install-title').textContent = title;
  $('#install-steps').innerHTML = steps.map((s) => `<li>${s}</li>`).join('');
  $('#install-dialog').showModal();
}
installBtn.addEventListener('click', startInstall);
document.querySelectorAll('[data-action="install"]').forEach((b) => b.addEventListener('click', startInstall));

// Refresh countdowns ("Starts in 12 min") once a minute.
setInterval(() => { if (state.card?.match.status === 'upcoming') render(state.card); renderRail(); }, 60000);

// ?preview → buttons to try the animations without waiting for a boundary.
if (new URLSearchParams(location.search).has('preview')) {
  const p = $('#preview');
  p.hidden = false;
  p.addEventListener('click', (e) => {
    const kind = e.target.dataset?.kind;
    if (kind) celebrate(kind, { text: kind === 'wicket' ? 'Preview — bowled him!' : 'Preview delivery', dismissalText: kind === 'wicket' ? 'Preview batter b Preview bowler 42 (31)' : '' });
  });
}

// Download button: enabled once a release has been published (Scripts/release.sh).
fetch('/version.json', { cache: 'no-cache' })
  .then((r) => (r.ok ? r.json() : null))
  .then((release) => {
    if (!release?.url) return;
    const a = $('#download');
    a.href = release.url;
    a.textContent = 'Download for Mac';
    a.classList.remove('is-disabled');
    a.removeAttribute('aria-disabled');
    const meta = $('#download-meta');
    meta.textContent = `Version ${release.version} · macOS ${release.minimumSystemVersion ?? '14'} or later · Apple Silicon & Intel · `;
    const notes = document.createElement('a');
    notes.href = release.releaseNotes ?? 'https://github.com/trilochan06/CricketScore/releases';
    notes.textContent = "What's new";
    notes.target = '_blank';
    notes.rel = 'noopener';
    meta.append(notes);
    if (!release.notarized) $('#first-open').hidden = false;
  })
  .catch(() => {});


connect();
