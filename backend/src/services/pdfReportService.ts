import PDFDocument from 'pdfkit';
import { sql } from '../config/db';
import { convert } from './exchangeRateService';
import { WalletModel } from '../models/WalletModel';

interface MonthlyReportData {
  monthLabel: string;
  currency: string;
  income: number;
  expense: number;
  net: number;
  categories: Array<{ name: string; amount: number; pct: number }>;
  budgets: Array<{ category: string; budget: number; spent: number }>;
  netWorth: { assets: number; liabilities: number; netWorth: number };
  transactionCount: number;
}

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'];

/** Gathers everything the monthly report needs, converted to the display currency. */
export async function collectMonthlyReportData(
  userId: string,
  year: number,
  month: number, // 1-12
): Promise<MonthlyReportData> {
  const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
  const currency = ((userRows[0] as any)?.currency as string) || 'LKR';

  const from = new Date(year, month - 1, 1);
  const to = new Date(year, month, 1);

  const rows = await sql`
    SELECT amount, currency, category
    FROM transactions
    WHERE user_id = ${userId} AND deleted_at IS NULL AND transfer_id IS NULL
      AND created_at >= ${from} AND created_at < ${to}
  `;

  let income = 0;
  let expense = 0;
  const catTotals = new Map<string, number>();
  for (const r of rows) {
    const amt = Number((r as any).amount);
    const cur = ((r as any).currency as string) || 'LKR';
    let converted = amt;
    try {
      converted = await convert(amt, cur, currency);
    } catch {
      converted = amt;
    }
    if (converted >= 0) {
      income += converted;
    } else {
      const abs = Math.abs(converted);
      expense += abs;
      const cat = String((r as any).category || 'Other');
      catTotals.set(cat, (catTotals.get(cat) ?? 0) + abs);
    }
  }

  const categories = [...catTotals.entries()]
    .map(([name, amount]) => ({ name, amount, pct: expense > 0 ? (amount / expense) * 100 : 0 }))
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 12);

  // Budget vs actual for the same month (budget amounts converted too).
  const budgetRows = await sql`
    SELECT category, amount, currency FROM budgets
    WHERE user_id = ${userId} AND deleted_at IS NULL
  `;
  const budgets: MonthlyReportData['budgets'] = [];
  for (const b of budgetRows) {
    const cat = String((b as any).category);
    let budgetAmt = Number((b as any).amount);
    try {
      budgetAmt = await convert(budgetAmt, ((b as any).currency as string) || 'LKR', currency);
    } catch { /* keep raw */ }
    budgets.push({ category: cat, budget: budgetAmt, spent: catTotals.get(cat) ?? 0 });
  }
  budgets.sort((a, b) => b.spent - a.spent);

  const nw = await WalletModel.netWorth(userId, currency);

  return {
    monthLabel: `${MONTHS[month - 1]} ${year}`,
    currency,
    income,
    expense,
    net: income - expense,
    categories,
    budgets: budgets.slice(0, 12),
    netWorth: { assets: nw.assets, liabilities: nw.liabilities, netWorth: nw.netWorth },
    transactionCount: rows.length,
  };
}

/** Renders the report to a PDF stream (the caller pipes it into the response). */
export function renderMonthlyReportPdf(data: MonthlyReportData): PDFKit.PDFDocument {
  const doc = new PDFDocument({ size: 'A4', margin: 48 });
  const money = (n: number) => `${n.toLocaleString('en-US', { maximumFractionDigits: 2 })} ${data.currency}`;
  const left = 48;
  const width = doc.page.width - 96;

  // ── Header ──
  doc.fontSize(22).fillColor('#5B5FEF').text('PulseSpend', left, 48, { continued: false });
  doc.fontSize(13).fillColor('#333333').text(`Monthly Report — ${data.monthLabel}`);
  doc.moveDown(0.3);
  doc.fontSize(9).fillColor('#888888')
    .text(`${data.transactionCount} transactions · amounts in ${data.currency} · transfers excluded`);
  doc.moveTo(left, doc.y + 8).lineTo(left + width, doc.y + 8).strokeColor('#DDDDDD').stroke();
  doc.moveDown(1.2);

  // ── Summary ──
  const summaryY = doc.y;
  const colW = width / 3;
  const stat = (x: number, label: string, value: string, color: string) => {
    doc.fontSize(9).fillColor('#888888').text(label, x, summaryY, { width: colW });
    doc.fontSize(14).fillColor(color).text(value, x, summaryY + 14, { width: colW });
  };
  stat(left, 'Income', money(data.income), '#1DB954');
  stat(left + colW, 'Expenses', money(data.expense), '#E5484D');
  stat(left + colW * 2, 'Net', money(data.net), data.net >= 0 ? '#1DB954' : '#E5484D');
  doc.y = summaryY + 44;

  // ── Category table ──
  const tableHeader = (title: string, cols: Array<[string, number]>) => {
    doc.moveDown(0.8);
    doc.fontSize(12).fillColor('#333333').text(title, left);
    doc.moveDown(0.4);
    const y = doc.y;
    let x = left;
    for (const [label, w] of cols) {
      doc.fontSize(9).fillColor('#888888').text(label, x, y, { width: w });
      x += w;
    }
    doc.moveTo(left, doc.y + 3).lineTo(left + width, doc.y + 3).strokeColor('#EEEEEE').stroke();
    doc.moveDown(0.4);
  };

  if (data.categories.length > 0) {
    tableHeader('Spending by category', [['Category', width - 200], ['Amount', 120], ['%', 80]]);
    for (const c of data.categories) {
      const y = doc.y;
      doc.fontSize(10).fillColor('#333333')
        .text(c.name, left, y, { width: width - 200, ellipsis: true });
      doc.text(money(c.amount), left + width - 200, y, { width: 120 });
      doc.text(`${c.pct.toFixed(0)}%`, left + width - 80, y, { width: 80 });
      doc.moveDown(0.25);
    }
  }

  // ── Budget vs actual ──
  if (data.budgets.length > 0) {
    tableHeader('Budgets vs actual', [['Category', width - 260], ['Budget', 130], ['Spent', 130]]);
    for (const b of data.budgets) {
      const y = doc.y;
      const over = b.spent > b.budget;
      doc.fontSize(10).fillColor('#333333')
        .text(b.category, left, y, { width: width - 260, ellipsis: true });
      doc.text(money(b.budget), left + width - 260, y, { width: 130 });
      doc.fillColor(over ? '#E5484D' : '#1DB954')
        .text(money(b.spent), left + width - 130, y, { width: 130 });
      doc.moveDown(0.25);
    }
  }

  // ── Net worth snapshot ──
  doc.moveDown(0.8);
  doc.fontSize(12).fillColor('#333333').text('Net worth snapshot', left);
  doc.moveDown(0.4);
  doc.fontSize(10).fillColor('#333333')
    .text(`Assets: ${money(data.netWorth.assets)}`, left)
    .text(`Liabilities: ${money(data.netWorth.liabilities)}`, left)
    .fillColor(data.netWorth.netWorth >= 0 ? '#1DB954' : '#E5484D')
    .text(`Net worth: ${money(data.netWorth.netWorth)}`, left);

  // ── Footer ──
  doc.fontSize(8).fillColor('#AAAAAA')
    .text(`Generated by PulseSpend on ${new Date().toISOString().slice(0, 10)}`,
      left, doc.page.height - 60, { width, align: 'center' });

  doc.end();
  return doc;
}
