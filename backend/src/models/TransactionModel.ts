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
  tags?: string[];
  splits?: TransactionSplit[];
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

  static async listByUser(userId: string, limit: number, offset: number): Promise<Transaction[]> {
    const transactions = await sql`
      SELECT * FROM transactions 
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY created_at DESC, id DESC
      LIMIT ${limit} OFFSET ${offset}
    `;

    const txRows = transactions as Transaction[];
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

  static async countByUser(userId: string): Promise<number> {
    const rows = await sql`
      SELECT COUNT(*)::int AS count
      FROM transactions
      WHERE user_id = ${userId} AND deleted_at IS NULL
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
  ): Promise<Transaction> {
    const cur = currency || 'LKR';
    const receipt = receiptUrl || null;
    const normalizedNotes = notes && notes.trim().length > 0 ? notes.trim() : null;
    const normalizedTags = this.normalizeTags(tags);
    const result = createdAt
      ? await sql`
          INSERT INTO transactions (user_id, title, amount, category, currency, created_at, receipt_url, notes)
          VALUES (${userId}, ${title}, ${amount}, ${category}, ${cur}, ${createdAt}, ${receipt}, ${normalizedNotes})
          RETURNING *
        `
      : await sql`
          INSERT INTO transactions (user_id, title, amount, category, currency, receipt_url, notes)
          VALUES (${userId}, ${title}, ${amount}, ${category}, ${cur}, ${receipt}, ${normalizedNotes})
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
