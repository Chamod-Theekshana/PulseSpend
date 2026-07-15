import { sql } from '../config/db';
import { convert } from '../services/exchangeRateService';

export interface IncomeExpenseTrend {
  incomeData: number[];
  expenseData: number[];
  labels: string[];
  totalIncome: number;
  totalExpense: number;
  incomeTrend: number;
  expenseTrend: number;
}

export interface CategorySpending {
  name: string;
  amount: number;
  percentage: number;
}

export interface AnalyticsSummary {
  period: string;
  trend: IncomeExpenseTrend;
  savingsRate: number;
  topCategories: CategorySpending[];
  currency: string;
}

export interface DigestSummary {
  range: 'week' | 'month';
  from: string;      // ISO date (inclusive)
  to: string;        // ISO date (exclusive)
  income: number;
  expense: number;
  net: number;
  savingsRate: number;
  transactionCount: number;
  topCategory: { name: string; amount: number } | null;
  currency: string;
}

export interface DailyTotal {
  date: string;    // yyyy-MM-dd
  income: number;
  expense: number;
}

export type InsightTone = 'positive' | 'warning' | 'neutral';

export interface Insight {
  id: string;
  tone: InsightTone;
  title: string;
  body: string;
}

export class AnalyticsModel {
  /**
   * Compact spending summary over a completed period — the trailing 7 days for
   * 'week', or the previous calendar month for 'month'. Used by the digest
   * scheduler (push) and the in-app "recap" card. Amounts are converted to the
   * user's preferred currency, mirroring getSummary.
   */
  static async getDigest(userId: string, range: 'week' | 'month'): Promise<DigestSummary> {
    const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
    const preferredCurrency = ((userRows[0] as any)?.currency as string) || 'LKR';

    const now = new Date();
    let from: Date;
    let to: Date;
    if (range === 'week') {
      to = new Date(now.getFullYear(), now.getMonth(), now.getDate()); // today 00:00 (exclusive)
      from = new Date(to.getTime() - 7 * 24 * 60 * 60 * 1000);
    } else {
      from = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      to = new Date(now.getFullYear(), now.getMonth(), 1);
    }

    const rows = await sql`
      SELECT amount, currency, category FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL AND transfer_id IS NULL
        AND created_at >= ${from} AND created_at < ${to}
    `;

    let income = 0;
    let expense = 0;
    const categoryTotals: Record<string, number> = {};

    for (const tx of rows) {
      const amt = Number((tx as any).amount);
      const txCurrency = ((tx as any).currency as string) || 'LKR';
      let converted = amt;
      try {
        converted = await convert(amt, txCurrency, preferredCurrency);
      } catch {
        converted = amt;
      }
      if (converted > 0) {
        income += converted;
      } else {
        const abs = Math.abs(converted);
        expense += abs;
        const cat = (tx as any).category as string;
        categoryTotals[cat] = (categoryTotals[cat] || 0) + abs;
      }
    }

    const topEntry = Object.entries(categoryTotals).sort((a, b) => b[1] - a[1])[0];
    const net = income - expense;
    const savingsRate = income > 0 ? Math.max(0, (net / income) * 100) : 0;

    const toISO = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

    return {
      range,
      from: toISO(from),
      to: toISO(to),
      income,
      expense,
      net,
      savingsRate,
      transactionCount: rows.length,
      topCategory: topEntry ? { name: topEntry[0], amount: topEntry[1] } : null,
      currency: preferredCurrency,
    };
  }

  /**
   * Per-day income/expense totals for one calendar month (the spending
   * heatmap). Amounts converted to the user's preferred currency, mirroring
   * getDigest. Days with no activity are omitted — the client fills the grid.
   */
  static async getDaily(userId: string, year: number, month: number): Promise<DailyTotal[]> {
    const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
    const preferredCurrency = ((userRows[0] as any)?.currency as string) || 'LKR';

    const from = new Date(year, month - 1, 1);
    const to = new Date(year, month, 1);
    const rows = await sql`
      SELECT amount, currency, created_at::date AS day
      FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL AND transfer_id IS NULL
        AND created_at >= ${from} AND created_at < ${to}
    `;

    const byDay = new Map<string, DailyTotal>();
    for (const r of rows) {
      const amt = Number((r as any).amount);
      const cur = ((r as any).currency as string) || 'LKR';
      // Neon parses DATE columns into JS Date objects — String(date) yields
      // "Sun Jun 21 2026 ...", which is NOT ISO. Format explicitly.
      const rawDay = (r as any).day;
      const day =
        rawDay instanceof Date
          ? `${rawDay.getFullYear()}-${String(rawDay.getMonth() + 1).padStart(2, '0')}-${String(rawDay.getDate()).padStart(2, '0')}`
          : String(rawDay).slice(0, 10);
      let converted = amt;
      try {
        converted = await convert(amt, cur, preferredCurrency);
      } catch {
        converted = amt;
      }
      const entry = byDay.get(day) ?? { date: day, income: 0, expense: 0 };
      if (converted >= 0) entry.income += converted;
      else entry.expense += Math.abs(converted);
      byDay.set(day, entry);
    }
    return [...byDay.values()].sort((a, b) => a.date.localeCompare(b.date));
  }

  /**
   * Human-readable spending insights derived from this month vs last month
   * (see getSummary). Templated natural language — no LLM required — covering
   * spend trend, top category, savings rate and income trend. Returns a
   * friendly "add more data" nudge when there's nothing to compare yet.
   */
  static async getInsights(userId: string): Promise<Insight[]> {
    const s = await AnalyticsModel.getSummary(userId, 'month');
    const cur = s.currency;
    const money = (n: number) => `${Math.round(n).toLocaleString('en-US')} ${cur}`;
    const insights: Insight[] = [];

    const { totalExpense, totalIncome, expenseTrend, incomeTrend } = s.trend;

    if (totalExpense === 0 && totalIncome === 0) {
      insights.push({
        id: 'empty',
        tone: 'neutral',
        title: 'Start tracking to unlock insights',
        body: 'Add a few transactions this month and we\'ll show trends, top categories and savings tips here.',
      });
      return insights;
    }

    // Spend trend vs last month
    if (Number.isFinite(expenseTrend) && Math.abs(expenseTrend) >= 10) {
      if (expenseTrend > 0) {
        insights.push({
          id: 'spend-up',
          tone: 'warning',
          title: `Spending up ${Math.round(expenseTrend)}%`,
          body: `You've spent ${Math.round(expenseTrend)}% more this month than the same point last month.`,
        });
      } else {
        insights.push({
          id: 'spend-down',
          tone: 'positive',
          title: `Spending down ${Math.round(Math.abs(expenseTrend))}%`,
          body: `Nice — you're spending ${Math.round(Math.abs(expenseTrend))}% less than last month. Keep it up!`,
        });
      }
    }

    // Top category
    const top = s.topCategories[0];
    if (top && top.amount > 0) {
      const base: Insight = {
        id: 'top-category',
        tone: top.percentage >= 40 ? 'warning' : 'neutral',
        title: `${top.name} is your biggest expense`,
        body: `${top.name} is ${Math.round(top.percentage)}% of your spending (${money(top.amount)}) this month.`,
      };
      if (top.percentage >= 40) {
        const saving = top.amount * 0.1;
        base.body += ` Trimming it by 10% would save about ${money(saving)}.`;
      }
      insights.push(base);
    }

    // Savings rate
    if (totalIncome > 0) {
      if (s.savingsRate >= 20) {
        insights.push({
          id: 'savings-good',
          tone: 'positive',
          title: `You saved ${Math.round(s.savingsRate)}% this month`,
          body: `Great discipline — you kept ${Math.round(s.savingsRate)}% of your income (${money(totalIncome - totalExpense)}).`,
        });
      } else if (s.savingsRate < 5) {
        insights.push({
          id: 'savings-low',
          tone: 'warning',
          title: 'Low savings this month',
          body: `You've saved under 5% of your income so far. Setting a category budget can help you keep more.`,
        });
      }
    }

    // Income trend
    if (Number.isFinite(incomeTrend) && incomeTrend >= 15 && totalIncome > 0) {
      insights.push({
        id: 'income-up',
        tone: 'positive',
        title: `Income up ${Math.round(incomeTrend)}%`,
        body: `Your income is ${Math.round(incomeTrend)}% higher than last month — a good time to boost savings.`,
      });
    }

    if (insights.length === 0) {
      insights.push({
        id: 'steady',
        tone: 'neutral',
        title: 'Steady month',
        body: `You've spent ${money(totalExpense)} so far this month, in line with last month.`,
      });
    }

    return insights;
  }

  static async getSummary(userId: string, period: string): Promise<AnalyticsSummary> {
    const userRows = await sql`SELECT currency FROM users WHERE id = ${userId}`;
    const preferredCurrency = (userRows[0] as any)?.currency as string || 'LKR';

    // Current period bounds
    const now = new Date();
    let startDate = new Date();
    let previousStartDate = new Date();
    
    // Logic for labels and bounds
    let labels: string[] = [];
    let buckets: number = 0;
    
    if (period === 'day') {
      startDate.setHours(0, 0, 0, 0);
      previousStartDate = new Date(startDate.getTime() - 24 * 60 * 60 * 1000);
      labels = ['6A', '9A', '12P', '3P', '6P', '9P'];
      buckets = 6;
    } else if (period === 'week') {
      // Start of week (Monday)
      const day = startDate.getDay() || 7; // Get current day number, converting Sun. to 7
      startDate.setHours(0, 0, 0, 0);
      startDate.setDate(startDate.getDate() - day + 1);
      previousStartDate = new Date(startDate.getTime() - 7 * 24 * 60 * 60 * 1000);
      labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      buckets = 7;
    } else if (period === 'month') {
      startDate = new Date(now.getFullYear(), now.getMonth(), 1);
      previousStartDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      labels = ['W1', 'W2', 'W3', 'W4', 'W5'];
      buckets = 5;
    } else { // year
      startDate = new Date(now.getFullYear(), 0, 1);
      previousStartDate = new Date(now.getFullYear() - 1, 0, 1);
      labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      buckets = 12;
    }

    const transactions = await sql`
      SELECT amount, currency, created_at, category FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL AND transfer_id IS NULL
        AND created_at >= ${previousStartDate}
    `;

    let currentIncome = 0;
    let currentExpense = 0;
    let previousIncome = 0;
    let previousExpense = 0;

    const incomeData = new Array(buckets).fill(0);
    const expenseData = new Array(buckets).fill(0);
    
    const categoryTotals: Record<string, number> = {};

    for (const tx of transactions) {
      const txDate = new Date(tx.created_at as string);
      const isCurrent = txDate >= startDate;
      
      const amt = Number((tx as any).amount);
      const txCurrency = ((tx as any).currency as string) || 'LKR';
      
      let converted = amt;
      try {
        converted = await convert(amt, txCurrency, preferredCurrency);
      } catch {
        converted = amt;
      }
      
      if (isCurrent) {
        if (converted > 0) {
          currentIncome += converted;
        } else {
          currentExpense += Math.abs(converted);
          
          // category spending
          const cat = (tx as any).category as string;
          categoryTotals[cat] = (categoryTotals[cat] || 0) + Math.abs(converted);
        }
        
        // bucket logic
        let bucketIndex = 0;
        if (period === 'day') {
           const hour = txDate.getHours();
           if (hour < 6) bucketIndex = 0;
           else if (hour < 9) bucketIndex = 1;
           else if (hour < 12) bucketIndex = 2;
           else if (hour < 15) bucketIndex = 3;
           else if (hour < 18) bucketIndex = 4;
           else bucketIndex = 5;
        } else if (period === 'week') {
           const day = txDate.getDay() || 7;
           bucketIndex = day - 1;
        } else if (period === 'month') {
           const date = txDate.getDate();
           bucketIndex = Math.min(Math.floor((date - 1) / 7), 4);
        } else { // year
           bucketIndex = txDate.getMonth();
        }
        
        if (converted > 0) {
          incomeData[bucketIndex] += converted;
        } else {
          expenseData[bucketIndex] += Math.abs(converted);
        }

      } else {
        // Previous period
        if (converted > 0) {
          previousIncome += converted;
        } else {
          previousExpense += Math.abs(converted);
        }
      }
    }

    const incomeTrend = previousIncome === 0 ? (currentIncome > 0 ? 100 : 0) : ((currentIncome - previousIncome) / previousIncome) * 100;
    const expenseTrend = previousExpense === 0 ? (currentExpense > 0 ? 100 : 0) : ((currentExpense - previousExpense) / previousExpense) * 100;

    let savingsRate = 0;
    if (currentIncome > 0) {
      savingsRate = Math.max(0, ((currentIncome - currentExpense) / currentIncome) * 100);
    } else if (currentExpense > 0) {
      savingsRate = -100; // or 0? 0 is better when no income
    }

    const topCategories: CategorySpending[] = Object.entries(categoryTotals)
      .map(([name, amount]) => ({
        name,
        amount,
        percentage: currentExpense > 0 ? (amount / currentExpense) * 100 : 0
      }))
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 20); // full-ish breakdown; the client shows the top 5 and lists the rest under "View all"

    return {
      period,
      trend: {
        incomeData,
        expenseData,
        labels,
        totalIncome: currentIncome,
        totalExpense: currentExpense,
        incomeTrend,
        expenseTrend
      },
      savingsRate,
      topCategories,
      currency: preferredCurrency
    };
  }
}
