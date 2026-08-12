import { describe, expect, it } from 'vitest';
import {
  isLocalHour,
  isValidTimeZone,
  localDayOfMonth,
  localHour,
  localISODate,
  localISODateOffset,
  localWeekday,
  offsetFor,
  sanitizeOffsetMinutes,
  toISODateUTC,
  zoneOffsetMinutes,
} from './time';

const COLOMBO = { timezone: 'Asia/Colombo', tz_offset_minutes: null };
const NEW_YORK = { timezone: 'America/New_York', tz_offset_minutes: null };
const KATHMANDU = { timezone: 'Asia/Kathmandu', tz_offset_minutes: null };

describe('zoneOffsetMinutes', () => {
  it('handles whole-hour zones', () => {
    expect(zoneOffsetMinutes('UTC', new Date('2026-01-15T12:00:00Z'))).toBe(0);
    expect(zoneOffsetMinutes('Asia/Tokyo', new Date('2026-01-15T12:00:00Z'))).toBe(540);
  });

  it('handles half- and quarter-hour zones', () => {
    expect(zoneOffsetMinutes('Asia/Colombo', new Date('2026-01-15T12:00:00Z'))).toBe(330);
    expect(zoneOffsetMinutes('Asia/Kathmandu', new Date('2026-01-15T12:00:00Z'))).toBe(345);
    expect(zoneOffsetMinutes('Australia/Eucla', new Date('2026-01-15T12:00:00Z'))).toBe(525);
  });

  it('follows DST rather than using a fixed offset', () => {
    // The whole reason `timezone` is preferred over `tz_offset_minutes`.
    expect(zoneOffsetMinutes('America/New_York', new Date('2026-01-15T12:00:00Z'))).toBe(-300);
    expect(zoneOffsetMinutes('America/New_York', new Date('2026-07-15T12:00:00Z'))).toBe(-240);
    expect(zoneOffsetMinutes('Europe/London', new Date('2026-01-15T12:00:00Z'))).toBe(0);
    expect(zoneOffsetMinutes('Europe/London', new Date('2026-07-15T12:00:00Z'))).toBe(60);
  });

  it('returns 0 for an unknown zone instead of throwing', () => {
    expect(zoneOffsetMinutes('Mars/Olympus_Mons')).toBe(0);
  });
});

describe('isValidTimeZone', () => {
  it('accepts real IANA ids and rejects junk', () => {
    expect(isValidTimeZone('Asia/Colombo')).toBe(true);
    expect(isValidTimeZone('UTC')).toBe(true);
    expect(isValidTimeZone('Not/AZone')).toBe(false);
    expect(isValidTimeZone('')).toBe(false);
  });
});

describe('offsetFor fallback chain', () => {
  it('prefers the IANA zone', () => {
    expect(offsetFor({ timezone: 'Asia/Colombo', tz_offset_minutes: 999 })).toBe(330);
  });

  it('falls back to the reported offset when the zone is missing or bogus', () => {
    expect(offsetFor({ timezone: null, tz_offset_minutes: 330 })).toBe(330);
    expect(offsetFor({ timezone: 'Mars/Olympus', tz_offset_minutes: 60 })).toBe(60);
  });

  it('accepts a numeric string, as Postgres SMALLINT sometimes arrives', () => {
    expect(offsetFor({ tz_offset_minutes: '-300' })).toBe(-300);
  });

  it('defaults to UTC when nothing is known — the pre-migration behaviour', () => {
    expect(offsetFor({})).toBe(0);
    expect(offsetFor({ timezone: null, tz_offset_minutes: null })).toBe(0);
    expect(offsetFor({ tz_offset_minutes: 5000 })).toBe(0);
  });
});

describe('local calendar fields', () => {
  // 18:45Z on 10 Aug is already 00:15 on 11 Aug in Colombo, and still
  // 14:45 on 10 Aug in New York. This is precisely the case that made
  // `new Date().toISOString().slice(0, 10)` file transactions on the wrong day.
  const late = new Date('2026-08-10T18:45:00Z');

  it('rolls the date forward for zones east of UTC', () => {
    expect(localISODate(COLOMBO, late)).toBe('2026-08-11');
    expect(localHour(COLOMBO, late)).toBe(0);
  });

  it('keeps the earlier date for zones west of UTC', () => {
    expect(localISODate(NEW_YORK, late)).toBe('2026-08-10');
    expect(localHour(NEW_YORK, late)).toBe(14);
  });

  it('handles the exact midnight boundary', () => {
    const midnight = new Date('2026-08-10T18:30:00Z'); // 00:00 Aug 11 Colombo
    expect(localISODate(COLOMBO, midnight)).toBe('2026-08-11');
    expect(localHour(COLOMBO, midnight)).toBe(0);
  });

  it('reports weekday and day-of-month in the user local frame', () => {
    // 2026-08-11 is a Tuesday.
    expect(localWeekday(COLOMBO, late)).toBe(2);
    expect(localDayOfMonth(COLOMBO, late)).toBe(11);
    // Still Monday the 10th in New York.
    expect(localWeekday(NEW_YORK, late)).toBe(1);
    expect(localDayOfMonth(NEW_YORK, late)).toBe(10);
  });

  it('offsets across a month boundary correctly', () => {
    const eom = new Date('2026-08-31T20:00:00Z'); // 01:30 Sep 1 in Colombo
    expect(localISODate(COLOMBO, eom)).toBe('2026-09-01');
    expect(localISODateOffset(COLOMBO, -1, eom)).toBe('2026-08-31');
    expect(localISODateOffset(COLOMBO, 1, eom)).toBe('2026-09-02');
  });
});

describe('isLocalHour', () => {
  const ticks = Array.from(
    { length: 24 },
    (_, h) => new Date(Date.UTC(2026, 7, 10, h, 0, 0)),
  );

  const hits = (user: Parameters<typeof isLocalHour>[0], hour: number) =>
    ticks.filter((t) => isLocalHour(user, hour, t)).length;

  it('fires exactly once per day for a whole-hour zone', () => {
    expect(hits(NEW_YORK, 9)).toBe(1);
  });

  it('fires exactly once per day for a 45-minute zone', () => {
    // Nepal is +05:45. Matching on the hour field rather than on elapsed
    // minutes is what keeps this from either double-firing or never firing.
    expect(hits(KATHMANDU, 9)).toBe(1);
  });

  it('fires exactly once per day for a 30-minute zone', () => {
    expect(hits(COLOMBO, 9)).toBe(1);
  });

  it('lands on the intended local hour, not the server hour', () => {
    // 03:30Z is 09:00 in Colombo.
    expect(isLocalHour(COLOMBO, 9, new Date('2026-08-10T03:30:00Z'))).toBe(true);
    // 09:00Z is 14:30 in Colombo — the old buggy behaviour.
    expect(isLocalHour(COLOMBO, 9, new Date('2026-08-10T09:00:00Z'))).toBe(false);
  });

  it('treats a UTC user as before the migration', () => {
    expect(isLocalHour({}, 9, new Date('2026-08-10T09:00:00Z'))).toBe(true);
  });
});

describe('sanitizeOffsetMinutes', () => {
  it('accepts valid offsets including strings', () => {
    expect(sanitizeOffsetMinutes(330)).toBe(330);
    expect(sanitizeOffsetMinutes('-300')).toBe(-300);
    expect(sanitizeOffsetMinutes(0)).toBe(0);
    expect(sanitizeOffsetMinutes(825)).toBe(825);
  });

  it('rejects out-of-range and non-numeric input', () => {
    expect(sanitizeOffsetMinutes(901)).toBeNull();
    expect(sanitizeOffsetMinutes(-901)).toBeNull();
    expect(sanitizeOffsetMinutes('abc')).toBeNull();
    expect(sanitizeOffsetMinutes(null)).toBeNull();
    expect(sanitizeOffsetMinutes(undefined)).toBeNull();
    expect(sanitizeOffsetMinutes(NaN)).toBeNull();
  });
});

describe('toISODateUTC', () => {
  it('zero-pads month and day', () => {
    expect(toISODateUTC(new Date('2026-01-05T00:00:00Z'))).toBe('2026-01-05');
  });
});
