// Cross-platform extras for the website: favorite teams, alerts, a floating
// "pop-out" scoreboard, and app installation. Works on Windows, macOS, Android and iOS
// (each feature degrades gracefully where a browser doesn't support it).

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function safeGet(k) { try { return localStorage.getItem(k); } catch { return null; } }
function safeSet(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } }

// ───────────────────────── Favorite teams ─────────────────────────

let favorites = (() => { try { return JSON.parse(safeGet('favorites') ?? '[]'); } catch { return []; } })();

export const Favorites = {
  list: () => [...favorites],
  /** "India" also follows India A, India Women and India Under-19s. */
  isFavorite(team) {
    if (!team) return false;
    const name = (team.name ?? '').toLowerCase();
    return favorites.some((f) => {
      const fav = f.toLowerCase();
      return name === fav || name.startsWith(fav + ' ');
    });
  },
  follows(match) { return match.teams.some((t) => Favorites.isFavorite(t)); },
  toggle(teamName) {
    const exists = favorites.some((f) => f.toLowerCase() === teamName.toLowerCase());
    favorites = exists ? favorites.filter((f) => f.toLowerCase() !== teamName.toLowerCase()) : [...favorites, teamName];
    safeSet('favorites', JSON.stringify(favorites));
    return !exists;
  },
  /** Replace the whole list (My teams panel). */
  set(list) {
    favorites = [...new Set(list.map((s) => s.trim()).filter(Boolean))];
    safeSet('favorites', JSON.stringify(favorites));
  },
  /** The base name to store when starring a team ("India A" → still store exactly what was clicked). */
  isExactFavorite(teamName) { return favorites.some((f) => f.toLowerCase() === teamName.toLowerCase()); },
};

// ───────────────────────── Alerts ─────────────────────────

export const Alerts = {
  get enabled() { return safeGet('alerts') === '1' && Alerts.permission === 'granted'; },
  get supported() { return 'Notification' in window; },
  get permission() { return Alerts.supported ? Notification.permission : 'unsupported'; },

  async enable() {
    if (!Alerts.supported) return 'unsupported';
    const result = Notification.permission === 'granted' ? 'granted' : await Notification.requestPermission();
    safeSet('alerts', result === 'granted' ? '1' : '0');
    return result;
  },
  disable() { safeSet('alerts', '0'); },

  /** Shows a system notification (via the service worker where required, e.g. Android). */
  async notify(title, body, tag, url = location.href) {
    if (!Alerts.enabled) return false;
    const options = { body, tag, icon: '/icons/icon-192.png', badge: '/icons/icon-192.png', data: { url }, renotify: true };
    try {
      const reg = await navigator.serviceWorker?.getRegistration();
      if (reg) { await reg.showNotification(title, options); return true; }
      new Notification(title, options);
      return true;
    } catch { return false; }
  },
};

/** Compares two match lists and returns alert events for followed matches. */
export function diffMatches(oldList, newList, { selectedId }) {
  const events = [];
  const before = new Map(oldList.map((m) => [m.id, m]));
  for (const m of newList) {
    const o = before.get(m.id);
    if (!o) continue;
    const followed = Favorites.follows(m);
    if (!followed) continue;
    const title = `${m.teams[0].short} v ${m.teams[1].short}`;
    if (o.status === 'upcoming' && ['live', 'inningsBreak', 'rainDelay'].includes(m.status)) {
      events.push({ kind: 'started', match: m, title: `Match started · ${title}`, body: m.statusText || m.title || '' });
    }
    if (['live', 'inningsBreak', 'rainDelay'].includes(o.status) && (m.status === 'completed' || m.status === 'abandoned')) {
      events.push({ kind: 'result', match: m, title: `Result · ${title}`, body: m.result || m.statusText });
    }
    const a = o.innings.at(-1), b = m.innings.at(-1);
    if (m.id !== selectedId && a && b && a.teamId === b.teamId && b.wickets > a.wickets) {
      events.push({ kind: 'wicket', match: m, title: `WICKET · ${title}`, body: `${b.team} ${b.runs}/${b.wickets} (${b.overs})` });
    }
  }
  return events;
}

// ───────────────────────── Pop-out mini scoreboard ─────────────────────────
// Chrome/Edge (Windows, macOS, ChromeOS): Document Picture-in-Picture — a real always-on-top
// mini page. Safari: fallback to video Picture-in-Picture fed by a canvas.

const PIP_CSS = `
  :root { color-scheme: dark; }
  * { box-sizing: border-box; margin: 0; }
  body { font-family: Inter, -apple-system, "Segoe UI", system-ui, sans-serif; background: #0b0d12; color: #f2f4f8;
         height: 100vh; display: flex; flex-direction: column; justify-content: center; padding: 10px 14px; gap: 6px; overflow: hidden;
         -webkit-font-smoothing: antialiased; transition: box-shadow .3s; }
  .row { display: flex; align-items: baseline; gap: 8px; min-width: 0; }
  .st { font-size: 10px; font-weight: 800; letter-spacing: .12em; color: #a4abb8; display: flex; align-items: center; gap: 5px; }
  .st.live { color: #ff453a; } .st.live::before { content: ""; width: 7px; height: 7px; border-radius: 50%; background: #ff453a; box-shadow: 0 0 8px #ff453a; }
  .team { font-weight: 700; font-size: 15px; } .score { font: 700 26px "JetBrains Mono", ui-monospace, Menlo, monospace; letter-spacing: -.02em; }
  .ov { font: 500 13px "JetBrains Mono", ui-monospace, Menlo, monospace; color: #a4abb8; }
  .other { margin-left: auto; font-size: 12.5px; color: #a4abb8; white-space: nowrap; }
  .eq { font-size: 12.5px; color: #d6dbe4; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .balls { display: flex; gap: 4px; } .b { width: 20px; height: 20px; border-radius: 50%; display: grid; place-items: center;
     font: 700 10px "JetBrains Mono", ui-monospace, monospace; background: rgba(255,255,255,.1); }
  .b.dot { background: transparent; box-shadow: inset 0 0 0 1.2px rgba(255,255,255,.2); color: #6b7280; }
  .b.four { background: #1f7cff; } .b.six { background: #a855f7; } .b.wicket { background: #f0352b; }
  .b.extra { background: rgba(245,158,11,.2); color: #f59e0b; font-size: 8.5px; }
  .flash { position: fixed; inset: 0; display: grid; place-items: center; font: 900 64px Inter, system-ui, sans-serif; letter-spacing: -.04em;
           pointer-events: none; opacity: 0; }
  .flash.on { animation: pop 1.6s cubic-bezier(.2,1.2,.3,1) forwards; }
  @keyframes pop { 0% { opacity: 0; transform: scale(.4); } 15% { opacity: 1; transform: scale(1.1); } 30% { transform: scale(1); } 80% { opacity: 1; } 100% { opacity: 0; } }
  body.four { box-shadow: inset 0 0 0 3px #1f7cff; } body.six { box-shadow: inset 0 0 0 3px #a855f7; } body.wicket { box-shadow: inset 0 0 0 3px #f0352b; }
  .foot { font-size: 10px; color: #6b7280; }
`;

function miniModel(card) {
  if (!card) return null;
  const m = card.match;
  const inn = m.innings.at(-1);
  const other = inn ? m.innings.filter((i) => i.teamId !== inn.teamId).at(-1) : null;
  const score = (i) => (i.wickets >= 10 ? `${i.runs}` : `${i.runs}/${i.wickets}`);
  const statusText = { live: 'LIVE', inningsBreak: 'BREAK', rainDelay: 'RAIN', upcoming: 'UPCOMING', completed: 'RESULT', abandoned: 'NO RESULT' }[m.status] ?? '';
  let eq = m.statusText || '';
  if (card.runsRequired != null && card.ballsRemaining != null) eq = `${inn?.team ?? ''} need ${card.runsRequired} from ${card.ballsRemaining}`;
  if (m.status === 'completed' || m.status === 'abandoned') eq = m.result || m.statusText;
  return {
    status: m.status, statusText,
    team: inn?.team ?? m.teams[0].short, score: inn ? score(inn) : '—', overs: inn ? inn.overs : '',
    other: other ? `${other.team} ${score(other)}` : `v ${m.teams.find((t) => t.id !== inn?.teamId)?.short ?? ''}`,
    eq, balls: card.recentBalls.slice(-6),
  };
}

function ballClass(b) {
  const t = b.outcome?.type;
  return t === 'four' ? 'four' : t === 'six' ? 'six' : t === 'wicket' ? 'wicket' : t === 'dot' ? 'dot'
    : ['wide', 'noBall', 'bye', 'legBye'].includes(t) ? 'extra' : '';
}

export const MiniScore = {
  pipWindow: null,
  video: null,
  canvas: null,
  last: null,

  get mode() {
    const touchOnly = !matchMedia('(any-pointer: fine)').matches;
    if ('documentPictureInPicture' in window && !touchOnly) return 'document';
    const canStream = 'captureStream' in HTMLCanvasElement.prototype;
    const v = document.createElement('video');
    const canPip = document.pictureInPictureEnabled || typeof v.webkitSupportsPresentationMode === 'function';
    return canStream && canPip ? 'video' : null;
  },
  get isOpen() {
    return !!(MiniScore.pipWindow && !MiniScore.pipWindow.closed)
      || !!(MiniScore.video && (document.pictureInPictureElement === MiniScore.video || MiniScore.video.webkitPresentationMode === 'picture-in-picture'));
  },

  async open(card, onClose) {
    MiniScore.last = card;
    if (MiniScore.mode === 'document') {
      const pip = await window.documentPictureInPicture.requestWindow({ width: 340, height: 132 });
      MiniScore.pipWindow = pip;
      const style = pip.document.createElement('style');
      style.textContent = PIP_CSS;
      pip.document.head.append(style);
      pip.document.title = 'Cricket Live';
      pip.addEventListener('pagehide', () => { MiniScore.pipWindow = null; onClose?.(); });
      MiniScore.update(card);
      return true;
    }
    if (MiniScore.mode === 'video') {
      const canvas = MiniScore.canvas ?? Object.assign(document.createElement('canvas'), { width: 640, height: 240 });
      MiniScore.canvas = canvas;
      MiniScore.drawCanvas(card);
      let video = MiniScore.video;
      if (!video) {
        video = Object.assign(document.createElement('video'), { muted: true, playsInline: true, autoplay: true });
        video.setAttribute('playsinline', '');
        video.setAttribute('muted', '');
        // In the page (some phones refuse picture-in-picture for detached videos), but invisible.
        video.style.cssText = 'position:fixed;width:2px;height:2px;opacity:0.01;pointer-events:none;bottom:0;left:0';
        document.body.append(video);
        MiniScore.video = video;
      }
      video.srcObject = canvas.captureStream(4);
      await video.play();
      if (video.requestPictureInPicture && document.pictureInPictureEnabled) {
        await video.requestPictureInPicture();
        video.addEventListener('leavepictureinpicture', () => onClose?.(), { once: true });
      } else if (video.webkitSupportsPresentationMode?.('picture-in-picture')) {
        video.webkitSetPresentationMode('picture-in-picture');   // iPhone / iPad Safari
        video.addEventListener('webkitpresentationmodechanged', () => {
          if (video.webkitPresentationMode !== 'picture-in-picture') onClose?.();
        });
      } else {
        throw new Error('picture-in-picture unavailable');
      }
      return true;
    }
    return false;
  },

  close() {
    if (MiniScore.pipWindow && !MiniScore.pipWindow.closed) MiniScore.pipWindow.close();
    if (document.pictureInPictureElement) document.exitPictureInPicture().catch(() => {});
    if (MiniScore.video?.webkitPresentationMode === 'picture-in-picture') MiniScore.video.webkitSetPresentationMode('inline');
    MiniScore.pipWindow = null;
  },

  update(card) {
    MiniScore.last = card;
    if (MiniScore.pipWindow && !MiniScore.pipWindow.closed) {
      const v = miniModel(card);
      if (!v) return;
      const body = MiniScore.pipWindow.document.body;
      const flash = body.querySelector('.flash')?.outerHTML ?? '<div class="flash"></div>';
      body.innerHTML = `
        <div class="row"><span class="st ${esc(v.status)}">${esc(v.statusText)}</span><span class="other">${esc(v.other)}</span></div>
        <div class="row"><span class="team">${esc(v.team)}</span><span class="score">${esc(v.score)}</span><span class="ov">${esc(v.overs)}${v.overs ? ' ov' : ''}</span></div>
        <div class="eq">${esc(v.eq)}</div>
        ${v.balls.length ? `<div class="balls">${v.balls.map((b) => `<span class="b ${ballClass(b)}">${esc(b.label)}</span>`).join('')}</div>` : ''}
        ${flash}`;
    } else if (MiniScore.canvas && MiniScore.isOpen) {
      MiniScore.drawCanvas(card);
    }
  },

  flash(kind) {
    const words = { four: '4', six: '6', wicket: 'W' };
    const colors = { four: '#1f7cff', six: '#a855f7', wicket: '#f0352b' };
    if (MiniScore.pipWindow && !MiniScore.pipWindow.closed) {
      const doc = MiniScore.pipWindow.document;
      let f = doc.querySelector('.flash');
      if (!f) { f = doc.createElement('div'); f.className = 'flash'; doc.body.append(f); }
      f.textContent = kind === 'wicket' ? 'WICKET' : words[kind];
      f.style.color = colors[kind];
      f.classList.remove('on'); void f.offsetWidth; f.classList.add('on');
      doc.body.className = kind;
      setTimeout(() => { doc.body.className = ''; }, 1600);
    } else if (MiniScore.canvas && MiniScore.isOpen) {
      MiniScore.drawCanvas(MiniScore.last, { kind, color: colors[kind], word: kind === 'wicket' ? 'WICKET' : words[kind] });
      setTimeout(() => MiniScore.drawCanvas(MiniScore.last), 1800);
    }
  },

  drawCanvas(card, flash = null) {
    const c = MiniScore.canvas, ctx = c.getContext('2d');
    const v = miniModel(card);
    ctx.fillStyle = '#0b0d12'; ctx.fillRect(0, 0, c.width, c.height);
    if (flash) { ctx.strokeStyle = flash.color; ctx.lineWidth = 10; ctx.strokeRect(5, 5, c.width - 10, c.height - 10); }
    if (!v) return;
    ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = v.status === 'live' ? '#ff453a' : '#a4abb8';
    ctx.font = '800 20px system-ui, sans-serif'; ctx.fillText(v.statusText, 28, 46);
    ctx.fillStyle = '#a4abb8'; ctx.textAlign = 'right'; ctx.font = '500 22px system-ui, sans-serif'; ctx.fillText(v.other, c.width - 28, 46); ctx.textAlign = 'left';
    ctx.fillStyle = '#f2f4f8'; ctx.font = '700 34px system-ui, sans-serif'; ctx.fillText(v.team, 28, 110);
    const tw = ctx.measureText(v.team).width;
    ctx.font = '700 58px ui-monospace, Menlo, monospace'; ctx.fillText(v.score, 44 + tw, 112);
    const sw = ctx.measureText(v.score).width;
    ctx.fillStyle = '#a4abb8'; ctx.font = '500 26px ui-monospace, Menlo, monospace'; if (v.overs) ctx.fillText(`${v.overs} ov`, 60 + tw + sw, 110);
    ctx.fillStyle = '#d6dbe4'; ctx.font = '500 24px system-ui, sans-serif'; ctx.fillText(v.eq.slice(0, 44), 28, 158);
    v.balls.forEach((b, i) => {
      const x = 46 + i * 50, y = 205, cls = ballClass(b);
      ctx.beginPath(); ctx.arc(x, y, 20, 0, Math.PI * 2);
      ctx.fillStyle = { four: '#1f7cff', six: '#a855f7', wicket: '#f0352b', extra: 'rgba(245,158,11,.25)', dot: '#0b0d12' }[cls] ?? 'rgba(255,255,255,.14)';
      ctx.fill(); if (cls === 'dot') { ctx.strokeStyle = 'rgba(255,255,255,.25)'; ctx.lineWidth = 2; ctx.stroke(); }
      ctx.fillStyle = cls === 'extra' ? '#f59e0b' : '#fff'; ctx.font = '700 18px ui-monospace, monospace'; ctx.textAlign = 'center';
      ctx.fillText(b.label, x, y + 6); ctx.textAlign = 'left';
    });
    if (flash) {
      ctx.fillStyle = 'rgba(11,13,18,.72)'; ctx.fillRect(10, 10, c.width - 20, c.height - 20);
      ctx.fillStyle = flash.color; ctx.font = '900 110px system-ui, sans-serif'; ctx.textAlign = 'center';
      ctx.fillText(flash.word, c.width / 2, c.height / 2 + 38); ctx.textAlign = 'left';
    }
  },
};

// ───────────────────────── Install as an app ─────────────────────────

let deferredPrompt = null;

export const Install = {
  get isInstalled() {
    return matchMedia('(display-mode: standalone)').matches || matchMedia('(display-mode: window-controls-overlay)').matches || navigator.standalone === true;
  },
  get canPrompt() { return !!deferredPrompt; },

  init(onChange) {
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
    window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferredPrompt = e; onChange?.(); });
    window.addEventListener('appinstalled', () => { deferredPrompt = null; onChange?.(); });
  },

  async prompt() {
    if (!deferredPrompt) return 'manual';
    deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    deferredPrompt = null;
    return outcome;
  },

  /** Step-by-step instructions for browsers without a one-click install. */
  instructions() {
    const ua = navigator.userAgent;
    const iOS = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    const android = /Android/.test(ua);
    const safari = /Safari/.test(ua) && !/Chrome|Chromium|Edg|OPR|Firefox/.test(ua);
    const firefox = /Firefox/.test(ua);
    if (iOS) return { title: 'Add to your Home Screen', steps: ['Tap the <b>Share</b> button (the square with an arrow).', 'Scroll and tap <b>Add to Home Screen</b>.', 'Tap <b>Add</b>. Cricket Live opens like an app.'] };
    if (android) return { title: 'Install on Android', steps: ['Tap the browser <b>⋮ menu</b>.', 'Tap <b>Install app</b> or <b>Add to Home screen</b>.'] };
    if (safari) return { title: 'Add to your Dock (Safari)', steps: ['In the menu bar choose <b>File → Add to Dock…</b>', 'Click <b>Add</b>. Cricket Live opens in its own window.'] };
    if (firefox) return { title: 'Install with Chrome or Edge', steps: ['Firefox on desktop can’t install web apps yet.', 'Open this page in <b>Chrome</b> or <b>Microsoft Edge</b> and click the <b>install icon</b> in the address bar.', 'Or just bookmark it — everything works in Firefox too.'] };
    return { title: 'Install the app', steps: ['Click the <b>install icon</b> at the right of the address bar (a screen with an arrow).', 'Or open the browser menu → <b>Cast, save and share → Install page as app</b> (Chrome) / <b>Apps → Install this site as an app</b> (Edge).'] };
  },
};

// ───────────────────────── Sharing ─────────────────────────
// The shared *text* carries the live score (link previews are built by WhatsApp's servers,
// which can't read live data), plus an optional score-card image on phones.

const SITE = 'https://cricketscore-server.vercel.app';
const MOMENT = { four: { emoji: '🔥', word: 'FOUR!' }, six: { emoji: '💥', word: 'SIX!' }, wicket: { emoji: '☝️', word: 'WICKET!' } };

function scoreLine(i) { return i ? `${i.team} ${i.wickets >= 10 ? i.runs : `${i.runs}/${i.wickets}`} (${i.overs} ov)` : ''; }

export function matchUrl(id) { return `${SITE}/#match=${encodeURIComponent(id)}`; }

export function shareText(card, moment) {
  const m = card.match;
  const inn = m.innings.at(-1);
  const sc = (i) => (i.wickets >= 10 ? `${i.runs}` : `${i.runs}/${i.wickets}`);
  // Each team's innings in batting order: "AUS-A 358 & 173/4 · IND-A 167 & 75/2 (33 ov)"
  const order = [...new Set(m.innings.map((i) => i.teamId))];
  const scores = order.map((id) => {
    const inns = m.innings.filter((i) => i.teamId === id);
    const last = inns.at(-1);
    const live = inn && last === inn && ['live', 'rainDelay', 'inningsBreak'].includes(m.status);
    return `${last.team} ${inns.map(sc).join(' & ')}${live ? ` (${last.overs} ov)` : ''}`;
  }).join(' · ');
  const lines = [];
  if (moment) lines.push(`${MOMENT[moment.kind].emoji} ${MOMENT[moment.kind].word} ${moment.text ?? ''}`.trim());
  lines.push(`🏏 ${m.teams[0].name} v ${m.teams[1].name}${m.title ? ` · ${m.title}` : ''}`);
  if (scores) lines.push(scores);
  if (card.runsRequired != null && card.ballsRemaining != null) lines.push(`${inn?.team} need ${card.runsRequired} from ${card.ballsRemaining} balls`);
  else if (m.status === 'completed' || m.status === 'abandoned') lines.push(m.result || m.statusText);
  else if (m.statusText && !/won toss|chose to|elected to/i.test(m.statusText)) lines.push(m.statusText);
  lines.push('Live ball by ball:');
  return lines.join('\n');
}

/** A 1200×630 score card (PNG) for sharing as an image. */
export async function scoreImage(card, moment) {
  const c = document.createElement('canvas');
  c.width = 1200; c.height = 630;
  const ctx = c.getContext('2d');
  const m = card.match;
  const inn = m.innings.at(-1);
  const g = ctx.createLinearGradient(0, 0, 1200, 630);
  g.addColorStop(0, '#141821'); g.addColorStop(1, '#0b0d12');
  ctx.fillStyle = g; ctx.fillRect(0, 0, 1200, 630);
  const accent = moment ? { four: '#1f7cff', six: '#a855f7', wicket: '#f0352b' }[moment.kind] : '#ff453a';
  ctx.fillStyle = accent; ctx.fillRect(0, 0, 1200, 10);
  const font = (w, s) => `${w} ${s}px Inter, -apple-system, "Segoe UI", system-ui, sans-serif`;
  const mono = (w, s) => `${w} ${s}px "JetBrains Mono", ui-monospace, Menlo, monospace`;
  // header
  ctx.fillStyle = '#ff453a'; ctx.beginPath(); ctx.arc(70, 70, 16, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#f2f4f8'; ctx.font = font(800, 30); ctx.fillText('Cricket Live', 100, 81);
  const status = { live: '● LIVE', inningsBreak: 'INNINGS BREAK', rainDelay: 'RAIN DELAY', upcoming: 'UPCOMING', completed: 'RESULT', abandoned: 'NO RESULT' }[m.status] ?? '';
  ctx.fillStyle = m.status === 'live' ? '#ff453a' : '#a4abb8'; ctx.font = font(800, 26); ctx.textAlign = 'right'; ctx.fillText(status, 1130, 81); ctx.textAlign = 'left';
  // title
  ctx.fillStyle = '#f2f4f8'; ctx.font = font(800, 46);
  ctx.fillText(`${m.teams[0].name} v ${m.teams[1].name}`.slice(0, 44), 70, 170);
  ctx.fillStyle = '#a4abb8'; ctx.font = font(500, 26);
  ctx.fillText([m.title, m.series].filter(Boolean).join(' · ').slice(0, 70), 70, 212);
  // scores
  let y = 310;
  const order = m.innings.length ? [...new Set(m.innings.map((i) => i.teamId))] : m.teams.map((t) => t.id);
  for (const teamId of order.slice(0, 2)) {
    const team = m.teams.find((t) => t.id === teamId) ?? m.teams[0];
    const inns = m.innings.filter((i) => i.teamId === teamId);
    const batting = inn && inn.teamId === teamId && m.status === 'live';
    ctx.fillStyle = batting ? '#f2f4f8' : '#8b93a1'; ctx.font = font(700, 40); ctx.fillText(team.short, 70, y);
    ctx.font = mono(700, batting ? 74 : 54);
    const text = inns.map((i) => (i.wickets >= 10 ? `${i.runs}` : `${i.runs}/${i.wickets}`)).join(' & ') || 'Yet to bat';
    ctx.fillText(text, 240, y + 6);
    const last = inns.at(-1);
    if (last) { const w = ctx.measureText(text).width; ctx.fillStyle = '#8b93a1'; ctx.font = mono(500, 30); ctx.fillText(`${last.overs} ov`, 270 + w, y); }
    y += 100;
  }
  // situation / moment
  let line = '';
  if (moment) line = `${MOMENT[moment.kind].word} ${moment.text ?? ''}`;
  else if (card.runsRequired != null && card.ballsRemaining != null) line = `${inn?.team} need ${card.runsRequired} from ${card.ballsRemaining} balls`;
  else line = m.result || m.statusText || '';
  ctx.fillStyle = moment ? accent : '#d6dbe4'; ctx.font = font(moment ? 800 : 600, 34);
  ctx.fillText(line.slice(0, 60), 70, 535);
  ctx.fillStyle = '#6b7280'; ctx.font = font(500, 24);
  ctx.fillText('Live ball by ball · cricketscore-server.vercel.app', 70, 590);
  return new Promise((resolve) => c.toBlob((b) => resolve(b ? new File([b], 'cricket-score.jpg', { type: 'image/jpeg' }) : null), 'image/jpeg', 0.9));
}

/** Native share sheet where available (phones, some desktops). Returns 'shared' | 'cancelled' | 'menu'. */
export async function shareNative(card, moment) {
  if (!navigator.share) return 'menu';
  const text = shareText(card, moment);
  const url = matchUrl(card.match.id);
  try {
    const file = await scoreImage(card, moment).catch(() => null);
    if (file && navigator.canShare?.({ files: [file] }) && matchMedia('(pointer: coarse)').matches) {
      await navigator.share({ files: [file], text: `${text}\n${url}` });
    } else {
      await navigator.share({ text, url });
    }
    return 'shared';
  } catch (err) {
    return err?.name === 'AbortError' ? 'cancelled' : 'menu';
  }
}

export function shareLinks(card, moment) {
  const text = shareText(card, moment);
  const url = matchUrl(card.match.id);
  return {
    whatsapp: `https://wa.me/?text=${encodeURIComponent(`${text}\n${url}`)}`,
    x: `https://twitter.com/intent/tweet?text=${encodeURIComponent(text)}&url=${encodeURIComponent(url)}`,
    copy: `${text}\n${url}`,
  };
}

// ───────────────────────── Onboarding ─────────────────────────

export const POPULAR_TEAMS = [
  ['India', 'IND', '#1f6fe0'], ['Australia', 'AUS', '#e6b10b'], ['England', 'ENG', '#2a4aa8'], ['Pakistan', 'PAK', '#0b8a4b'],
  ['South Africa', 'SA', '#11905e'], ['New Zealand', 'NZ', '#3c3f45'], ['Sri Lanka', 'SL', '#2d47b5'], ['Bangladesh', 'BAN', '#008c5a'],
  ['West Indies', 'WI', '#8a1530'], ['Afghanistan', 'AFG', '#1a63c9'], ['Ireland', 'IRE', '#169a55'], ['Zimbabwe', 'ZIM', '#c93030'],
];

export const Onboarding = {
  get done() { return safeGet('onboarded') === '1' || Favorites.list().length > 0; },
  finish() { safeSet('onboarded', '1'); },
};

// ───────────────────────── Pop-out availability ─────────────────────────

/** Pop-out is a laptop/desktop feature: Document PiP, or video PiP on non-touch Safari. */
export function popOutAvailable() { return MiniScore.mode !== null; }

/** Phones/tablets (no mouse or trackpad) "pin" via a floating video window. */
export function isTouchOnly() { return !matchMedia('(any-pointer: fine)').matches; }
