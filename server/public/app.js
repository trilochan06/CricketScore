// Cricket Live — browser client.
// Polls our own API every few seconds (responses are edge-cached, so the upstream
// source sees ~1 request per match no matter how many people are watching) and
// detects new deliveries itself to trigger the FOUR / SIX / WICKET animations.

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
};

function safeGet(k) { try { return localStorage.getItem(k); } catch { return null; } }
function safeSet(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } }

// ───────────────────────── Live updates ─────────────────────────

const CARD_INTERVAL_MS = 4000;       // matches the API's edge-cache lifetime
const HIDDEN_CARD_INTERVAL_MS = 30000;
const LIST_INTERVAL_MS = 30000;

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

async function getJSON(url) {
  const res = await fetch(url, { headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`${res.status}`);
  return res.json();
}

async function pollList() {
  try {
    state.matches = await getJSON('/api/matches');
    ok();
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
    const card = await getJSON(`/api/matches/${encodeURIComponent(id)}`);
    if (id !== state.selectedId) return; // user switched matches meanwhile
    ok();
    const firstLoad = !state.card;
    // New deliveries since the last poll, oldest first → celebrations.
    const fresh = card.commentary.filter((c) => !state.seenFeed.has(c.id)).reverse();
    render(card);
    if (!firstLoad && !document.hidden) {
      for (const c of fresh) if (c.kind) celebrate(c.kind, { text: c.text, dismissalText: c.dismissal });
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
}

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
  // Default view: internationals plus anything that's live right now.
  const featured = state.matches.filter((m) => m.isInternational || m.status === 'live');
  return state.showAll || featured.length === 0 ? state.matches : featured;
}

function ensureSelection() {
  const list = visibleMatches();
  const current = state.matches.find((m) => m.id === state.selectedId);
  if (current) return;
  const pick = list.find((m) => m.status === 'live') ?? list[0];
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
      <span class="chip-title">${esc(m.teams[0]?.short)} v ${esc(m.teams[1]?.short)}</span>
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
      <span class="team-name">${esc(team.name)}${battingTeamId === id ? '<span class="bat-icon" title="Batting">🏏</span>' : ''}</span>
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
  if (chip) select(chip.dataset.id);
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

connect();
