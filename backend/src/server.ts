import express from 'express';
import dotenv from 'dotenv';
import cors from 'cors';
import http from 'http';
import helmet from 'helmet';

// Load env FIRST before any module that reads process.env
dotenv.config();

import { validateEnv } from './config/env';
import { initDB } from './config/db';
import rateLimiter from './middleware/RateLimiter';
import { requestLogger } from './middleware/requestLogger';
import { errorHandler } from './middleware/errorHandler';
import transactionsRoutes from './routes/transactionsRoutes';
import authRoutes from './routes/authRoutes';
import signupRoutes from './routes/signupRoutes';
import profileRoutes from './routes/profileRoutes';
import notificationRoutes from './routes/notificationRoutes';
import categoriesRoutes from './routes/categoriesRoutes';
import budgetsRoutes from './routes/budgetsRoutes';
import recurringRoutes from './routes/recurringRoutes';
import remindersRoutes from './routes/remindersRoutes';
import goalsRoutes from './routes/goalsRoutes';
import exchangeRateRoutes from './routes/exchangeRateRoutes';
import otpRoutes from './routes/otpRoutes';
import analyticsRoutes from './routes/analyticsRoutes';
import feedbackRoutes from './routes/feedbackRoutes';
import groupsRoutes from './routes/groupsRoutes';
import walletsRoutes from './routes/walletsRoutes';
import debtsRoutes from './routes/debtsRoutes';
import { initSocket } from './socket';
import { startRecurringScheduler } from './services/recurringScheduler';
import { GoalReminderService } from './services/GoalReminderService';
import { BillReminderScheduler } from './services/billReminderScheduler';
import { SummaryDigestScheduler } from './services/summaryDigestScheduler';
import { ReengagementScheduler } from './services/reengagementScheduler';
import { SubscriptionDetector } from './services/subscriptionDetector';
import { GoalAutoContributeScheduler } from './services/goalAutoContributeScheduler';
import { AccountPurgeScheduler } from './services/accountPurgeScheduler';
import { RecurringReminderScheduler } from './services/recurringReminderScheduler';
import { BudgetPacingScheduler } from './services/budgetPacingScheduler';

// Parse TRUST_PROXY into the value Express expects (boolean | number | subnet).
function parseTrustProxy(v?: string): boolean | number | string {
  if (!v) return false;
  const t = v.trim();
  if (t === 'true') return true;
  if (t === 'false') return false;
  const n = Number(t);
  return Number.isNaN(n) ? t : n;
}

// Abort immediately if a required secret is missing/weak.
validateEnv();

const app = express();
const PORT = process.env.PORT || 5001;

// Trust proxy — controls how Express derives req.ip from X-Forwarded-For.
// MUST reflect the number of proxies/load-balancers in front of the app; a
// wrong value re-opens IP-based rate-limit spoofing. Default: don't trust any.
//   TRUST_PROXY=1        → one reverse proxy (typical PaaS / Nginx)
//   TRUST_PROXY=false    → direct connections (local dev)
app.set('trust proxy', parseTrustProxy(process.env.TRUST_PROXY));

// Security headers
app.disable('x-powered-by');
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
}));

// CORS
const allowedOrigins = process.env.CORS_ORIGIN
  ? process.env.CORS_ORIGIN.split(',').map((s) => s.trim()).filter(Boolean)
  : [];
const allowAll = allowedOrigins.includes('*') && process.env.NODE_ENV !== 'production';

app.use(
  cors({
    origin: allowAll ? '*' : (origin, callback) => {
      if (!origin) return callback(null, true);
      if (allowedOrigins.includes(origin)) return callback(null, true);
      return callback(new Error('Not allowed by CORS'));
    },
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  }),
);

app.use(requestLogger);
app.use(rateLimiter);
app.use(express.json({ limit: '2mb' }));

// Health check (no auth, no rate limit logging noise)
app.get('/health', (_req, res) => res.json({ status: 'ok', timestamp: new Date().toISOString() }));

app.use('/api/auth', authRoutes);
app.use('/api/auth', signupRoutes);
app.use('/api/auth', otpRoutes);
app.use('/api/transaction', transactionsRoutes);
app.use('/api/profile', profileRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/categories', categoriesRoutes);
app.use('/api/budgets', budgetsRoutes);
app.use('/api/recurring', recurringRoutes);
app.use('/api/reminders', remindersRoutes);
app.use('/api/goals', goalsRoutes);
app.use('/api/exchange-rates', exchangeRateRoutes);
app.use('/api/analytics', analyticsRoutes);
app.use('/api/feedback', feedbackRoutes);
app.use('/api/groups', groupsRoutes);
app.use('/api/wallets', walletsRoutes);
app.use('/api/debts', debtsRoutes);

// 404 handler
app.use((_req, res) => res.status(404).json({ message: 'Not found' }));

app.use(errorHandler);

const server = http.createServer(app);
initSocket(server);

initDB()
  .then(async () => {
    await startRecurringScheduler();
    GoalReminderService.startDailyReminders();
    BillReminderScheduler.startDailyReminders();
    await BillReminderScheduler.checkAndSendReminders();
    SummaryDigestScheduler.start();
    ReengagementScheduler.start();
    SubscriptionDetector.start();
    GoalAutoContributeScheduler.start();
    AccountPurgeScheduler.start();
    RecurringReminderScheduler.start();
    BudgetPacingScheduler.start();
    server.listen(PORT, () => {
      console.log(`[Server] Running on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error('[Server] Failed to initialize:', err);
    process.exit(1);
  });

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[Server] SIGTERM received, shutting down gracefully...');
  server.close(() => {
    console.log('[Server] Closed.');
    process.exit(0);
  });
});
