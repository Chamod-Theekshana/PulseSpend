import type { Response } from 'express';
import { CategoryModel } from '../models/CategoryModel';
import type { AuthedRequest } from '../middleware/requireAuth';

export async function listCategories(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { limit, offset } = (req as any).pagination || { limit: 50, offset: 0 };
  const [rows, total] = await Promise.all([
    CategoryModel.listByUser(userId, limit, offset),
    CategoryModel.countByUser(userId),
  ]);
  return res.json({ categories: rows, page: { limit, offset, total } });
}

export async function createCategory(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { name, type } = req.body || {};
  try {
    const row = await CategoryModel.create(userId, name, type);
    return res.status(201).json({ category: row });
  } catch (e: any) {
    return res.status(400).json({ message: 'Failed to create category (maybe duplicate?)' });
  }
}

export async function updateCategory(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const { name, type } = req.body || {};
  const row = await CategoryModel.update(userId, id, name, type);
  if (!row) return res.status(404).json({ message: 'Not found' });
  return res.json({ category: row });
}

export async function deleteCategory(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const id = Number(req.params.id);
  const ok = await CategoryModel.delete(userId, id);
  if (!ok) return res.status(404).json({ message: 'Not found' });
  return res.json({ message: 'Deleted' });
}

export async function bulkDeleteCategories(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const ids = (req.body as { ids: number[] }).ids;
  const deletedCount = await CategoryModel.bulkDeleteByUser(userId, ids);
  return res.json({ message: 'Categories deleted', deletedCount });
}
