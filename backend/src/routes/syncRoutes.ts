import express from 'express';
import { requireAuth } from '../middleware/requireAuth';
import { syncAll } from '../controllers/syncController';

const router = express.Router();

router.get('/', requireAuth, syncAll);

export default router;
