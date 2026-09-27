// Vercel serverless function: GET /api/matches/:id
import { getScorecard } from '../../src/stateless.js';

export default async function handler(req, res) {
  const id = String(req.query.id ?? '');
  if (!/^[\w-]{1,32}$/.test(id)) return res.status(400).json({ error: 'bad match id' });
  try {
    const card = await getScorecard(id);
    if (!card) {
      res.setHeader('Cache-Control', 'public, s-maxage=30');
      return res.status(404).json({ error: 'match not found' });
    }
    // Shared edge cache: one upstream fetch per ~4 s per match, however many viewers.
    res.setHeader('Cache-Control', 'public, s-maxage=4, stale-while-revalidate=8');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.status(200).json(card);
  } catch (err) {
    console.error(`scorecard ${id} failed:`, err.message);
    res.setHeader('Cache-Control', 'no-store');
    res.status(502).json({ error: 'Live data source unavailable' });
  }
}
