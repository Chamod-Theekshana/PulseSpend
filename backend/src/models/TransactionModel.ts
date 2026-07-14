import { sql } from '../config/db';

export interface TransactionSplit {
  id: number;
  transaction_id: number;
  user_id: string;
  category: string;
  amount: number;
  percentage: number;
  created_at: Date;
}

export interface TransactionTagRow {
  id: number;
  transaction_id: number;
  user_id: string;
  tag: string;
  created_at: Date;
}

export type TransactionSplitInput = {
  category: string;
  amount: number;
  percentage: number;
};

export interface Transaction {
  id: number;
  user_id: string;
  title: string;
  amount: number;
  currency: string;
  category: string;
  created_at: Date;
  deleted_at?: Date | null;
  notes?: string | null;
  receipt_url?: string | null;
  wallet_id?: number | null;
  tags?: string[];
  splits?: TransactionSplit[];
}

/**
 * Optional server-side filters for the transaction list / export. Any field
 * left null/undefined is ignored (see the null-safe WHERE in the query below),
 * so callers only set what the user actually chose.
 */
export interface TransactionFilters {
  q?: string | null;              // free text over title + category
  category?: string | null;       // exact category match
  from?: string | null;           // ISO date, inclusive lower bound
  to?: string | null;             // ISO date, inclusive upper bound
  minAmount?: number | null;      // amount >= (signed; expenses are negative)
  maxAmount?: number | null;      // amount <=
  type?: 'income' | 'expense' | null;
  walletId?: number | null;       // wallet filter; 0 = the default (NULL) wallet
}

export class TransactionModel {
  private static normalizeTags(tags?: string[]): string[] {
    if (!tags || tags.length === 0) return [];

    const seen = new Set<string>();
    const normalized: string[] = [];

    for (const rawTag of tags) {
      const cleanTag = String(rawTag || '').trim().replace(/^#+/, '').toLowerCase();
      if (!cleanTag || seen.has(cleanTag)) continue;
      seen.add(cleanTag);
      normalized.push(cleanTag);
    }

    return normalized;
  }

  private static async listSplitsByUser(userId: string): Promise<TransactionSplit[]> {
    const rows = await sql`
      SELECT id, transaction_id, user_id, category, amount, percentage, created_at
      FROM transaction_splits
      WHERE user_id = ${userId}
      ORDER BY transaction_id DESC, id ASC
    `;
    return rows as TransactionSplit[];
  }

  private static async listTagsByUser(userId: string): Promise<TransactionTagRow[]> {
    const rows = await sql`
      SELECT id, transaction_id, user_id, tag, created_at
      FROM transaction_tags
      WHERE user_id = ${userId}
      ORDER BY transaction_id DESC, id ASC
    `;
    return rows as TransactionTagRow[];
  }

  private static async listSplitsByTransaction(
    userId: string,
    transactionId: string | number,
  ): Promise<TransactionSplit[]> {
    const rows = await sql`
      SELECT id, transaction_id, user_id, category, amount, percentage, created_at
      FROM transaction_splits
      WHERE user_id = ${userId} AND transaction_id = ${transactionId}
      ORDER BY id ASC
    `;
    return rows as TransactionSplit[];
  }

  private static async listTagsByTransaction(
    userId: string,
    transactionId: string | number,
  ): Promise<string[]> {
    const rows = await sql`
      SELECT tag
      FROM transaction_tags
      WHERE user_id = ${userId} AND transaction_id = ${transactionId}
      ORDER BY id ASC
    `;
    return rows.map((row) => String((row as any).tag));
  }

  private static async insertSplits(
    transactionId: number,
    userId: string,
    splits: TransactionSplitInput[],
  ): Promise<void> {
    for (const split of splits) {
      await sql`
        INSERT INTO transaction_splits (transaction_id, user_id, category, amount, percentage)
        VALUES (${transactionId}, ${userId}, ${split.category}, ${split.amount}, ${split.percentage})
      `;
    }
  }

  private static async replaceTags(
    transactionId: number,
    userId: string,
    tags: string[],
  ): Promise<void> {
    await sql`
      DELETE FROM transaction_tags
      WHERE transaction_id = ${transactionId} AND user_id = ${userId}
    `;

    for (const tag of tags) {
      await sql`
        INSERT INTO transaction_tags (transaction_id, user_id, tag)
        VALUES (${transactionId}, ${userId}, ${tag})
        ON CONFLICT (transaction_id, tag) DO NOTHING
      `;
    }
  }

  /** Attaches each transaction's splits + tags. Bulk-fetches per user (one
   *  query each) then joins in memory — same strategy the list endpoint used. */
  private static async hydrate(txRows: Transaction[], userId: string): Promise<Transaction[]> {
    if (txRows.length === 0) return txRows;

    const splitRows = await this.listSplitsByUser(userId);
    const tagRows = await this.listTagsByUser(userId);
    const splitsByTxId = new Map<number, TransactionSplit[]>();
    const tagsByTxId = new Map<number, string[]>();

    for (const split of splitRows) {
      const txId = Number(split.transaction_id);
      const existing = splitsByTxId.get(txId) || [];
      existing.push(split);
      splitsByTxId.set(txId, existing);
    }

    for (const tagRow of tagRows) {
      const txId = Number(tagRow.transaction_id);
      const existing = tagsByTxId.get(txId) || [];
      existing.push(String(tagRow.tag));
      tagsByTxId.set(txId, existing);
    }

    return txRows.map((tx) => ({
      ...tx,
      notes: tx.notes ?? null,
      tags: tagsByTxId.get(Number(tx.id)) || [],
      splits: splitsByTxId.get(Number(tx.id)) || [],
    }));
  }

  static listByUser(userId: string, limit: number, offset: number): Promise<Transaction[]> {
    return this.listByUserFiltered(userId, {}, limit, offset);
  }

  /**
   * Filtered + paginated list. Every filter clause is written to short-circuit
   * to TRUE when its parameter is null, so passing an empty `filters` behaves
   * exactly like an unfiltered list.
   */
  static async listByUserFiltered(
    userId: string,
    filters: TransactionFilters,
    limit: number,
    offset: number,
  ): Promise<Transaction[]> {
    const { q, category, from, to, minAmount, maxAmount, type, walletId } = filters;
    const like = q && q.trim() ? `%${q.trim()}%` : null;
    const cat = category && category.trim() ? category.trim() : null;
    const fromDate = from || null;
    const toDate = to || null;
    const minAmt = minAmount ?? null;
    const maxAmt = maxAmount ?? null;
    const txType = type || null;
    const wallet = walletId ?? null;

    const transactions = await sql`
      SELECT * FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL
        AND (${like}::text IS NULL OR title ILIKE ${like} OR category ILIKE ${like})
        AND (${cat}::text IS NULL OR category = ${cat})
        AND (${fromDate}::date IS NULL OR created_at >= ${fromDate}::date)
        AND (${toDate}::date IS NULL OR created_at <= ${toDate}::date)
        AND (${minAmt}::numeric IS NULL OR amount >= ${minAmt})
        AND (${maxAmt}::numeric IS NULL OR amount <= ${maxAmt})
        AND (${txType}::text IS NULL
             OR (${txType} = 'income' AND amount >= 0)
             OR (${txType} = 'expense' AND amount < 0))
        AND (${wallet}::int IS NULL
             OR (CASE WHEN ${wallet} = 0 THEN wallet_id IS NULL ELSE wallet_id = ${wallet} END))
      ORDER BY created_at DESC, id DESC
      LIMIT ${limit} OFFSET ${offset}
    `;

    return this.hydrate(transactions as Transaction[], userId);
  }

  static countByUser(userId: string): Promise<number> {
    return this.countByUserFiltered(userId, {});
  }

  static async countByUserFiltered(userId: string, filters: TransactionFilters): Promise<number> {
    const { q, category, from, to, minAmount, maxAmount, type, walletId } = filters;
    const like = q && q.trim() ? `%${q.trim()}%` : null;
    const cat = category && category.trim() ? category.trim() : null;
    const fromDate = from || null;
    const toDate = to || null;
    const minAmt = minAmount ?? null;
    const maxAmt = maxAmount ?? null;
    const txType = type || null;
    const wallet = walletId ?? null;

    const rows = await sql`
      SELECT COUNT(*)::int AS count
      FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL
        AND (${like}::text IS NULL OR title ILIKE ${like} OR category ILIKE ${like})
        AND (${cat}::text IS NULL OR category = ${cat})
        AND (${fromDate}::date IS NULL OR created_at >= ${fromDate}::date)
        AND (${toDate}::date IS NULL OR created_at <= ${toDate}::date)
        AND (${minAmt}::numeric IS NULL OR amount >= ${minAmt})
        AND (${maxAmt}::numeric IS NULL OR amount <= ${maxAmt})
        AND (${txType}::text IS NULL
             OR (${txType} = 'income' AND amount >= 0)
             OR (${txType} = 'expense' AND amount < 0))
        AND (${wallet}::int IS NULL
             OR (CASE WHEN ${wallet} = 0 THEN wallet_id IS NULL ELSE wallet_id = ${wallet} END))
    `;
    return Number((rows[0] as any)?.count || 0);
  }

  static async create(
    userId: string,
    title: string,
    amount: number,
    category: string,
    createdAt?: string,
    currency?: string,
    receiptUrl?: string | null,
    splits?: TransactionSplitInput[],
    notes?: string | null,
    tags?: string[],
    clientOpId?: string | null,
    walletId?: number | null,
  ): Promise<Transaction> {
    const cur = currency || 'LKR';
    const receipt = receiptUrl || null;
    const normalizedNotes = notes && notes.trim().length > 0 ? notes.trim() : null;
    const normalizedTags = this.normalizeTags(tags);
    const opId = clientOpId && clientOpId.trim() ? clientOpId.trim() : null;
    const wallet = walletId && walletId > 0 ? walletId : null;

    // Idempotency: if this op was already applied (e.g. a queued offline create
    // replayed after the response was lost), return the existing row untouched.
    if (opId) {
      const existing = await sql`
        SELECT * FROM transactions
        WHERE user_id = ${userId} AND client_op_id = ${opId} AND deleted_at IS NULL
      `;
      if (existing[0]) {
        return (await this.findByIdAndUser(String((existing[0] as any).id), userId)) as Transaction;
      }
    }

    const result = createdAt
      ? await sql`
          INSERT INTO transactions (user_id, title, amount, category, currency, created_at, receipt_url, notes, client_op_id, wallet_id)
          VALUES (${userId}, ${title}, ${amount}, ${category}, ${cur}, ${createdAt}, ${receipt}, ${normalizedNotes}, ${opId}, ${wallet})
          RETURNING *
        `
      : await sql`
          INSERT INTO transactions (user_id, title, amount, category, currency, receipt_url, notes, client_op_id, wallet_id)
          VALUES (${userId}, ${title}, ${amount}, ${category}, ${cur}, ${receipt}, ${normalizedNotes}, ${opId}, ${wallet})
          RETURNING *
        `;

    const created = result[0] as Transaction;

    if (splits && splits.length > 0) {
      await this.insertSplits(Number(created.id), userId, splits);
    }

    if (normalizedTags.length > 0) {
      await this.replaceTags(Number(created.id), userId, normalizedTags);
    }

    const hydrated = await this.findByIdAndUser(String(created.id), userId);
    return hydrated || created;
  }

  static async deleteByUser(id: string, userId: string): Promise<void> {
    await sql`
      UPDATE transactions
      SET deleted_at = NOW()
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
  }

  static async bulkDeleteByUser(userId: string, ids: number[]): Promise<number> {
    const rows = await sql`
      UPDATE transactions
      SET deleted_at = NOW()
      WHERE user_id = ${userId}
        AND deleted_at IS NULL
        AND id = ANY(${ids}::int[])
      RETURNING id
    `;
    return rows.length;
  }

  static async findByIdAndUser(id: string, userId: string): Promise<Transaction | null> {
    const rows = await sql`
      SELECT * FROM transactions
      WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
    `;
    const tx = (rows?.[0] as Transaction) || null;
    if (!tx) return null;

    const splits = await this.listSplitsByTransaction(userId, id);
    const tags = await this.listTagsByTransaction(userId, id);
    return {
      ...tx,
      notes: tx.notes ?? null,
      tags,
      splits,
    };
  }

  static async updateByUser(
    id: string,
    userId: string,
    title: string,
    amount: number,
    category: string,
    createdAt?: string,
    currency?: string,
    receiptUrl?: string | null,
    splits?: TransactionSplitInput[],
    notes?: string | null,
    tags?: string[],
    walletId?: number | null,
  ): Promise<Transaction | null> {
    const cur = currency || 'LKR';
    const receipt = receiptUrl !== undefined ? receiptUrl : null;
    const normalizedNotes = notes !== undefined
      ? (notes && notes.trim().length > 0 ? notes.trim() : null)
      : undefined;
    const normalizedTags = this.normalizeTags(tags);

    let rows;
    if (createdAt) {
      rows = notes !== undefined
        ? await sql`
            UPDATE transactions
            SET title = ${title}, amount = ${amount}, category = ${category}, currency = ${cur}, created_at = ${createdAt}, receipt_url = ${receipt}, notes = ${normalizedNotes}
            WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
            RETURNING *
          `
        : await sql`
            UPDATE transactions
            SET title = ${title}, amount = ${amount}, category = ${category}, currency = ${cur}, created_at = ${createdAt}, receipt_url = ${receipt}
            WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
            RETURNING *
          `;
    } else {
      rows = notes !== undefined
        ? await sql`
            UPDATE transactions
            SET title = ${title}, amount = ${amount}, category = ${category}, currency = ${cur}, receipt_url = ${receipt}, notes = ${normalizedNotes}
            WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
            RETURNING *
          `
        : await sql`
            UPDATE transactions
            SET title = ${title}, amount = ${amount}, category = ${category}, currency = ${cur}, receipt_url = ${receipt}
            WHERE id = ${id} AND user_id = ${userId} AND deleted_at IS NULL
            RETURNING *
          `;
    }

    const updated = (rows?.[0] as Transaction) || null;
    if (!updated) return null;

    // Wallet assignment (undefined = untouched; 0/null = back to default).
    if (walletId !== undefined) {
      const wallet = walletId && walletId > 0 ? walletId : null;
      await sql`UPDATE transactions SET wallet_id = ${wallet} WHERE id = ${id} AND user_id = ${userId}`;
    }

    if (splits !== undefined) {
      await sql`DELETE FROM transaction_splits WHERE transaction_id = ${id} AND user_id = ${userId}`;
      if (splits.length > 0) {
        await this.insertSplits(Number(updated.id), userId, splits);
      }
    }

    if (tags !== undefined) {
      await this.replaceTags(Number(updated.id), userId, normalizedTags);
    }

    const hydrated = await this.findByIdAndUser(String(updated.id), userId);
    return hydrated || updated;
  }
}
