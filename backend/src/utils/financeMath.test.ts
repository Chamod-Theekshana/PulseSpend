import { describe, it, expect } from 'vitest';
import { csvCell, sanitizeImportRows, computeBalances } from './financeMath';

// ── csvCell ──────────────────────────────────────────────────────────────────

describe('csvCell (RFC 4180 escaping)', () => {
  it('passes plain values through untouched', () => {
    expect(csvCell('Groceries')).toBe('Groceries');
    expect(csvCell(1234.5)).toBe('1234.5');
  });

  it('renders null/undefined as empty', () => {
    expect(csvCell(null)).toBe('');
    expect(csvCell(undefined)).toBe('');
  });

  it('quotes cells containing commas', () => {
    expect(csvCell('Rent, June')).toBe('"Rent, June"');
  });

  it('doubles embedded quotes and wraps the cell', () => {
    expect(csvCell('He said "hi"')).toBe('"He said ""hi"""');
  });

  it('quotes cells containing newlines (CR and LF)', () => {
    expect(csvCell('line1\nline2')).toBe('"line1\nline2"');
    expect(csvCell('line1\r\nline2')).toBe('"line1\r\nline2"');
  });

  it('leaves non-ASCII (රු, ₹) unquoted — BOM handles Excel', () => {
    expect(csvCell('රු 1,000')).toBe('"රු 1,000"'); // quoted for the comma only
    expect(csvCell('₹500')).toBe('₹500');
  });
});

// ── sanitizeImportRows ───────────────────────────────────────────────────────

const goodRow = {
  title: 'Coffee',
  amount: -450,
  category: 'Food',
  created_at: '2026-07-01',
  currency: 'lkr',
  client_op_id: 'op-1',
};

describe('sanitizeImportRows', () => {
  it('accepts a valid row and normalizes currency to uppercase', () => {
    const { valid, skipped } = sanitizeImportRows([goodRow]);
    expect(skipped).toBe(0);
    expect(valid).toHaveLength(1);
    expect(valid[0]).toEqual({
      title: 'Coffee',
      amount: -450,
      category: 'Food',
      created_at: '2026-07-01',
      currency: 'LKR',
      client_op_id: 'op-1',
    });
  });

  it('skips rows with missing/blank titles', () => {
    const { valid, skipped } = sanitizeImportRows([
      { ...goodRow, title: '' },
      { ...goodRow, title: '   ' },
      { ...goodRow, title: undefined },
    ]);
    expect(valid).toHaveLength(0);
    expect(skipped).toBe(3);
  });

  it('skips zero, non-finite, and absurd amounts', () => {
    const { valid, skipped } = sanitizeImportRows([
      { ...goodRow, amount: 0 },
      { ...goodRow, amount: 'abc' },
      { ...goodRow, amount: NaN },
      { ...goodRow, amount: Infinity },
      { ...goodRow, amount: 2_000_000_000 },
    ]);
    expect(valid).toHaveLength(0);
    expect(skipped).toBe(5);
  });

  it('skips malformed dates but keeps ISO dates', () => {
    const { valid, skipped } = sanitizeImportRows([
      { ...goodRow, created_at: '01/07/2026' },
      { ...goodRow, created_at: '2026-7-1' },
      { ...goodRow, created_at: '2026-07-01' },
    ]);
    expect(valid).toHaveLength(1);
    expect(skipped).toBe(2);
  });

  it('rounds amounts to 2 decimals', () => {
    const { valid } = sanitizeImportRows([{ ...goodRow, amount: -10.999 }]);
    expect(valid[0].amount).toBe(-11);
  });

  it('defaults category to Imported and currency to LKR', () => {
    const { valid } = sanitizeImportRows([
      { title: 'X', amount: -5, created_at: '2026-01-01' },
    ]);
    expect(valid[0].category).toBe('Imported');
    expect(valid[0].currency).toBe('LKR');
    expect(valid[0].client_op_id).toBeNull();
  });

  it('truncates oversized fields (title 200, category 255, op id 64)', () => {
    const { valid } = sanitizeImportRows([
      {
        ...goodRow,
        title: 'a'.repeat(300),
        category: 'b'.repeat(300),
        client_op_id: 'c'.repeat(100),
      },
    ]);
    expect(valid[0].title).toHaveLength(200);
    expect(valid[0].category).toHaveLength(255);
    expect(valid[0].client_op_id).toHaveLength(64);
  });

  it('processes mixed batches best-effort per row', () => {
    const { valid, skipped } = sanitizeImportRows([goodRow, { bogus: true }, goodRow]);
    expect(valid).toHaveLength(2);
    expect(skipped).toBe(1);
  });
});

// ── computeBalances ──────────────────────────────────────────────────────────

const A = { user_id: '1', name: 'Amara' };
const B = { user_id: '2', name: 'Bimal' };
const C = { user_id: '3', name: 'Chathu' };

describe('computeBalances (equal split)', () => {
  it('returns empty for a group with no members', () => {
    expect(computeBalances([], [{ user_id: '1', amount: 100 }], [])).toEqual({
      members: [],
      suggestions: [],
      total: 0,
    });
  });

  it('splits a single expense equally: payer gets back the others\' shares', () => {
    const { members, suggestions, total } = computeBalances(
      [A, B],
      [{ user_id: '1', amount: 3000 }],
      [],
    );
    expect(total).toBe(3000);
    expect(members.find((m) => m.user_id === '1')!.net).toBe(1500);
    expect(members.find((m) => m.user_id === '2')!.net).toBe(-1500);
    expect(suggestions).toEqual([
      { from: '2', from_name: 'Bimal', to: '1', to_name: 'Amara', amount: 1500 },
    ]);
  });

  it('nets always sum to ~zero', () => {
    const { members } = computeBalances(
      [A, B, C],
      [
        { user_id: '1', amount: 1000 },
        { user_id: '2', amount: 250 },
        { user_id: '1', amount: 500 },
      ],
      [],
    );
    const sum = members.reduce((s, m) => s + m.net, 0);
    expect(Math.abs(sum)).toBeLessThan(0.02); // rounding tolerance
  });

  it('members who paid nothing owe exactly their fair share', () => {
    const { members } = computeBalances(
      [A, B, C],
      [{ user_id: '1', amount: 900 }],
      [],
    );
    expect(members.find((m) => m.user_id === '2')!.net).toBe(-300);
    expect(members.find((m) => m.user_id === '3')!.net).toBe(-300);
  });

  it('settlements shift nets: payer up, receiver down', () => {
    const { members } = computeBalances(
      [A, B],
      [{ user_id: '1', amount: 3000 }],
      [{ from: '2', to: '1', amount: 1500 }],
    );
    expect(members.find((m) => m.user_id === '1')!.net).toBe(0);
    expect(members.find((m) => m.user_id === '2')!.net).toBe(0);
  });

  it('partial settlement leaves the remainder as a suggestion', () => {
    const { members, suggestions } = computeBalances(
      [A, B],
      [{ user_id: '1', amount: 3000 }],
      [{ from: '2', to: '1', amount: 1000 }],
    );
    expect(members.find((m) => m.user_id === '2')!.net).toBe(-500);
    expect(suggestions).toEqual([
      { from: '2', from_name: 'Bimal', to: '1', to_name: 'Amara', amount: 500 },
    ]);
  });

  it('ignores settlements involving non-members', () => {
    const { members } = computeBalances(
      [A, B],
      [{ user_id: '1', amount: 1000 }],
      [{ from: '99', to: '1', amount: 400 }],
    );
    // A's credit shrinks by 400 (received), stranger's debt is off the books.
    expect(members.find((m) => m.user_id === '1')!.net).toBe(100);
    expect(members.find((m) => m.user_id === '2')!.net).toBe(-500);
  });

  it('greedy suggestions cover all debts with minimal transfers', () => {
    // A paid 1200, B paid 0, C paid 300 → shares 500 each.
    // A +700, B −500, C −200 → B pays A 500, C pays A 200.
    const { suggestions } = computeBalances(
      [A, B, C],
      [
        { user_id: '1', amount: 1200 },
        { user_id: '3', amount: 300 },
      ],
      [],
    );
    expect(suggestions).toHaveLength(2);
    const paidToA = suggestions.filter((s) => s.to === '1');
    expect(paidToA.reduce((s, x) => s + x.amount, 0)).toBeCloseTo(700, 2);
    expect(suggestions.find((s) => s.from === '2')!.amount).toBe(500);
    expect(suggestions.find((s) => s.from === '3')!.amount).toBe(200);
  });

  it('suggestion amounts sum to total outstanding debt', () => {
    const { members, suggestions } = computeBalances(
      [A, B, C],
      [
        { user_id: '1', amount: 977.77 },
        { user_id: '2', amount: 123.45 },
      ],
      [{ from: '3', to: '1', amount: 50 }],
    );
    const owed = members.filter((m) => m.net < 0).reduce((s, m) => s - m.net, 0);
    const suggested = suggestions.reduce((s, x) => s + x.amount, 0);
    expect(suggested).toBeCloseTo(owed, 1);
  });

  it('settled-up group produces no suggestions', () => {
    const { suggestions } = computeBalances(
      [A, B],
      [
        { user_id: '1', amount: 500 },
        { user_id: '2', amount: 500 },
      ],
      [],
    );
    expect(suggestions).toHaveLength(0);
  });
});
