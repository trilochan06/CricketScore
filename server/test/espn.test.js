import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeBall, normalizeEvent, oversToBalls, ballsToOvers } from '../src/espn.js';

// Shapes copied from real ESPN responses (trimmed).
const ball = (over) => ({
  sequence: 200105,
  period: 2,
  playType: { id: '2', description: 'no run' },
  scoreValue: 0,
  shortText: 'Williams to Marsh, no run',
  team: { abbreviation: 'AUS' },
  batsman: { athlete: { displayName: 'Mitchell Marsh' }, totalRuns: 5, faced: 7, fours: 1, sixes: 0 },
  otherBatsman: { athlete: { displayName: 'Travis Head' }, totalRuns: 4, faced: 4, fours: 1, sixes: 0 },
  bowler: { athlete: { displayName: 'Lizaad Williams' }, balls: 5, maidens: 0, wickets: 0, conceded: 4 },
  innings: { number: 2, runs: 9, wickets: 0, balls: 11, target: 366, runRate: 4.9, requiredRunRate: 7.41, remainingRuns: 357, remainingBalls: 289, ballLimit: 300 },
  over: { number: 2, overs: 1.5, ...over },
  dismissal: { dismissal: false },
});

test('maps play types to outcomes', () => {
  const cases = [
    [{ id: '1', description: 'run' }, 1, 'runs', '1', null],
    [{ id: '2', description: 'no run' }, 0, 'dot', '•', null],
    [{ id: '3', description: 'four' }, 4, 'four', '4', 'four'],
    [{ id: '3', description: 'four' }, 5, 'four', '4', 'four'], // four off a no-ball
    [{ id: '4', description: 'six' }, 6, 'six', '6', 'six'],
    [{ id: '5', description: 'no ball' }, 1, 'noBall', 'nb', null],
    [{ id: '6', description: 'wide' }, 1, 'wide', 'wd', null],
    [{ id: '8', description: 'leg bye' }, 1, 'legBye', '1lb', null],
  ];
  for (const [playType, scoreValue, type, label, kind] of cases) {
    const b = normalizeBall({ ...ball(), playType, scoreValue });
    assert.equal(b.outcome.type, type, playType.description);
    assert.equal(b.label, label);
    assert.equal(b.kind, kind);
  }
});

test('wickets use the dismissal flag and keep the dismissal text', () => {
  const b = normalizeBall({
    ...ball(),
    playType: { id: '9', description: 'out' },
    dismissal: { dismissal: true, text: 'JD Campbell c Prasidh Krishna b Kuldeep Yadav 62 (88m 60b 6x4 3x6) SR: 103.33' },
  });
  assert.equal(b.outcome.type, 'wicket');
  assert.equal(b.kind, 'wicket');
  assert.match(b.dismissalText, /^JD Campbell/);
});

test('ball carries chase state and player stats', () => {
  const b = normalizeBall(ball());
  assert.equal(b.over, 1); // zero-based
  assert.equal(b.state.remainingRuns, 357);
  assert.equal(b.state.remainingBalls, 289);
  assert.equal(b.batter.name, 'Mitchell Marsh');
  assert.equal(b.bowler.balls, 5);
});

test('normalizes a scorepanel event with innings from linescores', () => {
  const event = {
    id: '1525656', date: '2026-09-27T08:00Z',
    status: { type: { state: 'in', description: 'Live', detail: 'Live' }, summary: 'Australia require 357 runs' },
    competitions: [{
      description: '2nd ODI',
      class: { generalClassCard: 'ODI', internationalClassId: '2' },
      venue: { fullName: 'The Wanderers Stadium, Johannesburg' },
      status: { summary: 'Australia require 357 runs' },
      competitors: [
        { order: 1, team: { id: '3', displayName: 'South Africa', abbreviation: 'SA', color: 'ace411' },
          linescores: [{ period: 1, runs: 365, wickets: 9, overs: 50, isBatting: true }, { period: 2, runs: 0, wickets: 0, overs: 1.5, isBatting: false }] },
        { order: 2, team: { id: '2', displayName: 'Australia', abbreviation: 'AUS' },
          linescores: [{ period: 1, runs: 0, wickets: 0, overs: 50, isBatting: false }, { period: 2, runs: 9, wickets: 0, overs: 1.5, isBatting: true }] },
      ],
    }],
  };
  const m = normalizeEvent(event, { id: '24203', name: 'Australia tour of South Africa' });
  assert.equal(m.status, 'live');
  assert.equal(m.format, 'odi');
  assert.equal(m.isInternational, true);
  assert.deepEqual(m.innings.map((i) => [i.team, i.runs, i.wickets, i.overs]), [['SA', 365, 9, '50'], ['AUS', 9, 0, '1.5']]);
  assert.equal(m.target, 366);
  assert.equal(m.teams[0].color, '#ace411');
});

test('statuses: breaks, rain, not started, results', () => {
  const mk = (type, summary = '', innings = true) => normalizeEvent({
    id: '1', status: { type, summary },
    competitions: [{ class: {}, competitors: [
      { team: { id: 'a', displayName: 'A' }, linescores: innings ? [{ period: 1, runs: 10, wickets: 1, overs: 2, isBatting: true }] : [] },
      { team: { id: 'b', displayName: 'B' }, linescores: [] }] }],
  }, {}).status;
  assert.equal(mk({ state: 'in', description: 'Innings break' }), 'inningsBreak');
  assert.equal(mk({ state: 'in', description: 'Stumps' }), 'inningsBreak');
  assert.equal(mk({ state: 'in', description: 'Match delayed by rain' }), 'rainDelay');
  assert.equal(mk({ state: 'in', description: 'Live' }, 'Starts at 09:00 local time', false), 'upcoming');
  assert.equal(mk({ state: 'post', description: 'Result' }, 'India won by 6 wickets'), 'completed');
  assert.equal(mk({ state: 'post', description: 'Abandoned' }, 'Match abandoned without a ball bowled'), 'abandoned');
});

test('overs conversion', () => {
  assert.equal(oversToBalls(32.2), 194);
  assert.equal(oversToBalls(50), 300);
  assert.equal(ballsToOvers(194), '32.2');
  assert.equal(ballsToOvers(300), '50');
  assert.equal(oversToBalls('x'), 0);
});
