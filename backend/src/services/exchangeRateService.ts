import 'dotenv/config';

type RatesCache = {
  base: string;
  rates: Record<string, number>;
  fetchedAt: number;
};

const CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour
const cache: Map<string, RatesCache> = new Map();

// Authenticated ExchangeRate-API v6
const API_KEY = process.env.EXCHANGE_RATE_API_KEY || '';
const API_BASE = `https://v6.exchangerate-api.com/v6/${API_KEY}/latest`;

/**
 * Fetch exchange rates for a base currency with 1-hour cache.
 */
async function fetchRates(base: string): Promise<Record<string, number>> {
  const upperBase = base.toUpperCase();
  const cached = cache.get(upperBase);

  if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS) {
    return cached.rates;
  }

  try {
    const res = await fetch(`${API_BASE}/${upperBase}`);
    if (!res.ok) throw new Error(`ExchangeRate API returned ${res.status}`);

    const data = (await res.json()) as { result: string; conversion_rates: Record<string, number> };
    if (data.result !== 'success') throw new Error('ExchangeRate API failed');

    const rates = data.conversion_rates;

    cache.set(upperBase, {
      base: upperBase,
      rates,
      fetchedAt: Date.now(),
    });

    console.log(`[ExchangeRate] Fetched ${Object.keys(rates).length} rates for ${upperBase}`);
    return rates;
  } catch (err) {
    console.error('[ExchangeRate] Failed to fetch rates:', err);
    // Return cached even if stale
    if (cached) return cached.rates;
    throw err;
  }
}

/**
 * Get the conversion rate from one currency to another.
 */
export async function getRate(from: string, to: string): Promise<number> {
  if (from.toUpperCase() === to.toUpperCase()) return 1;
  const rates = await fetchRates(from);
  const rate = rates[to.toUpperCase()];
  if (!rate) throw new Error(`No rate found for ${from} → ${to}`);
  return rate;
}

/**
 * Convert an amount from one currency to another.
 */
export async function convert(amount: number, from: string, to: string): Promise<number> {
  const rate = await getRate(from, to);
  return Math.round(amount * rate * 100) / 100;
}

/**
 * Get all rates for a base currency.
 */
export async function getAllRates(base: string): Promise<Record<string, number>> {
  return fetchRates(base);
}
