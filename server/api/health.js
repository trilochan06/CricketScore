// Vercel serverless function: GET /api/health
import { getMatches } from '../src/stateless.js';

export default async function handler(req, res) {
  try {
    const matches = await getMatches();
    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json({ ok: true, source: 'ESPNcricinfo', matches: matches.length, live: matches.filter((m) => m.status === 'live').length });
  } catch (err) {
    res.status(503).json({ ok: false, error: err.message });
  }
}
