// Vercel serverless function: GET /api/matches
import { getMatches } from '../../src/stateless.js';

export default async function handler(req, res) {
  try {
    const matches = await getMatches();
    res.setHeader('Cache-Control', 'public, s-maxage=10, stale-while-revalidate=30');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.status(200).json(matches);
  } catch (err) {
    console.error('matches failed:', err.message);
    res.setHeader('Cache-Control', 'no-store');
    res.status(502).json({ error: 'Live data source unavailable' });
  }
}
