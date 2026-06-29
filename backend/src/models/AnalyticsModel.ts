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

export class AnalyticsModel {
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
      WHERE user_id = ${userId} AND deleted_at IS NULL AND created_at >= ${previousStartDate}
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
      .slice(0, 5); // top 5

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
