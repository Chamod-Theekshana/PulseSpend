# PulseSpend — Feature Gap Implementation Plan

> **STATUS: ✅ All 8 gaps implemented** (backend + mobile). Backend `tsc` clean + 14 tests pass;
> `flutter analyze` clean (0 errors / 0 warnings). See "Implementation notes" at the end for what
> shipped per feature. Runtime end-to-end verification still recommended once a device + DB are available.

## Context

A 17-feature idea list (originally written against a different *React Native* "Expenses Tracker"
project) was reviewed against **this** app (`pulsespend` Flutter client + `backend` TypeScript API).

**Result of the audit: 9 of 17 are already fully built.** The list under-estimated how mature this
app already is. Only **8 features have real gaps**, and they range from tiny (one endpoint) to huge
(weeks of work). This document is the plan to close those 8 gaps, ordered quick-wins-first.

---

## Audit summary

### ✅ Already fully implemented (9) — no work needed
| # | Feature | Evidence |
|---|---------|----------|
| 1 | Budgets & spending limits | `budgets` table; `checkBudgetAlert` (80%/100% push) in `backend/src/controllers/transactionsController.ts`; `budgets/` feature folder |
| 2 | Recurring transactions | `recurring_transactions` table; `backend/src/services/recurringScheduler.ts`; `recurring/` UI |
| 5 | Multi-currency + live rates | `backend/src/services/exchangeRateService.ts` (ExchangeRate-API + keyless fallback, 1h cache); per-tx currency |
| 6 | Savings goals | `goals` table; contribute sheet; `backend/src/services/GoalReminderService.ts` |
| 7 | Receipts / attachments | `receipt_url` column + model field + Cloudinary |
| 9 | Split transactions | `transaction_splits` table; `pulsespend/lib/features/transactions/widgets/split_editor.dart` |
| 10 | Notes & tags | `notes` column + `transaction_tags` table + UI |
| 11 | Bill reminders | `reminders` table; `backend/src/services/billReminderScheduler.ts`; `remind_days_before` |
| 14 | Biometric auth | `pulsespend/lib/core/security/biometric_service.dart` + app-lock gate |

### ⚠️ Partial / ❌ Missing (8) — covered by this plan
| # | Feature | Status | Effort |
|---|---------|--------|--------|
| 13 | Account deletion | ❌ Missing (no DELETE route; About screen already promises it) | **S** |
| 4  | CSV / PDF export | ⚠️ JSON backup exists; no CSV/PDF | **S–M** |
| 3  | Search & filters (server-side) | ⚠️ Client-side only, on loaded page | **M** |
| 15 | Onboarding walkthrough | ❌ Missing | **S–M** |
| 8  | Weekly/monthly summary digest | ❌ Scheduler sends only a `test_daily` placeholder | **M** |
| 12 | AI spending insights/tips | ⚠️ Trend data exists; no NL tips | **M** |
| 17 | Offline write queue & sync | ⚠️ Connectivity detected; no queue/sync | **L** |
| 16 | Shared / family accounts | ❌ "Accounts" = device switcher, not groups; no tables | **XL** |

---

## Phase 1 — Quick wins (do these first)

### #13 Account deletion  — effort: S
- **Backend**
  - Add `deleteAccount(req,res)` to `backend/src/controllers/profileController.ts`. Reuse the exact
    model set that `exportUserData` already assembles (transactions, categories, budgets, goals,
    reminders, recurring). `transaction_splits`/`transaction_tags` cascade via existing
    `ON DELETE CASCADE` FKs; explicitly delete `notifications`, `notification_preferences`,
    `feedback`, `user_fcm_tokens`, then the `users` row.
  - Delete the Cloudinary profile photo (`cloudinary` is already imported in that controller).
  - Add `router.delete("/:user_id", validateNumericParam, requireUserMatchParam, asyncHandler(deleteAccount))`
    to `backend/src/routes/profileRoutes.ts` (mirror the existing `/data-export` route).
- **Mobile**
  - `deleteAccount()` in `pulsespend/lib/repositories/profile_repository.dart`.
  - Destructive "Delete account" button in `edit_profile_screen.dart` (or `security_screen.dart`) with a
    confirm dialog — reuse the dialog pattern in `accounts_screen.dart` `_remove`. On success clear
    `secure_storage` and route to sign-in.

### #4 CSV / PDF export  — effort: S–M
- **Backend**: `GET /:user_id/export?format=csv&from=&to=` in `transactionsController.ts`. Build CSV rows
  from a filtered `TransactionModel.listByUser` (or reuse the up-to-5000 pull already in
  `exportUserData`). Set `Content-Type: text/csv` + `Content-Disposition`. PDF is optional (pdfkit) —
  **ship CSV first**.
- **Mobile**: "Export" action on `transactions_screen.dart`; download, save to file, share via
  `share_plus`.

### #3 Search & filters (server-side)  — effort: M
- **Backend**: extend `parsePagination`/`getTransactionByUserId` to accept `q, category, from, to,
  minAmount, maxAmount, type`. Add a `validateTransactionFilters` validator; extend
  `TransactionModel.listByUser` + `countByUser` with `WHERE` (ILIKE on title, category eq, `created_at`
  range, amount range, sign for income/expense).
- **Mobile**: `transactions_screen.dart` already has `_query` + `_filter` (client-side over the loaded
  page). Move filtering server-side by passing params through `transaction_repository.dart`; add a filter
  bottom sheet (date range, category chips, amount) reusing `shared/widgets/selection_sheet.dart`.

### #15 Onboarding walkthrough  — effort: S–M (mobile-only)
- New `pulsespend/lib/features/onboarding/` with a `PageView` of 3–4 slides (add transaction, charts,
  budgets). Gate in `splash_gate.dart` / `app.dart` behind a persisted `onboarding_done` flag
  (`secure_storage` already exists). Show once after first launch/signup. Reuse `primary_button` + theme.
- Backend: none.

---

## Phase 2 — Medium features

### #8 Weekly/monthly summary digest  — effort: M
- **Backend**: replace the `test_daily` push in `backend/src/services/notificationScheduler.ts` with a
  real digest computed via `AnalyticsModel.getSummary` + top categories. Respect
  `notification_preferences` (add a `summary_digest` column or reuse an existing flag), persist to the
  `notifications` table, and send via `pushService.sendPushToUser`. Use weekly/monthly cadence (consider
  `node-cron`). Email is optional via the existing `nodemailer` config.
- **Mobile**: in-app summary card on `dashboard_screen.dart`; opt-in toggle in
  `notification_preferences_screen.dart`.

### #12 AI spending insights / tips  — effort: M
- **Backend**: new insights endpoint building on `AnalyticsModel` trends (`incomeTrend`, `expenseTrend`,
  category deltas) to emit **templated** natural-language strings first (e.g. "You spent 40% more on
  Food vs last month") — no LLM required. Optional richer tips later via the Claude API.
- **Mobile**: Insights card on `dashboard_screen.dart`.
- Reuse: `AnalyticsModel` already computes month-over-month trends.

---

## Phase 3 — Large / architectural (scope carefully before starting)

### #17 Offline write queue & sync  — effort: L
- **Mobile**: local outbox (drift/Isar/sqflite) storing queued create/update/delete ops with a
  client-generated op id; `connectivity_provider` already detects reconnect → flush queue; optimistic
  UI; conflict policy (last-write-wins or server timestamps). Add a `dio_client` interceptor to enqueue
  on network failure.
- **Backend**: idempotency on op id to dedupe retries; optional `updated_at` for conflict detection.
- Reuse: `connectivity_provider`, `connectivity_banner`, `dio_client`, `services/retry.ts` pattern.

### #16 Shared / family accounts  — effort: XL (recommend as a separate initiative)
- **Backend**: new `groups` + `group_members` tables; **every** data query (transactions, budgets,
  goals, reminders, …) becomes group-scoped instead of user-scoped — a large ownership-model refactor;
  invite flow (email/link + token).
- **Mobile**: group create/join screens, group switcher, shared views.
- Note: this is the biggest item and touches nearly the whole app. Do it last, on its own branch.

---

## Suggested order of execution
1. **#13 Account deletion** (closes a promise already shown in the About screen)
2. **#4 CSV export** → PDF later
3. **#3 Server-side search & filters**
4. **#15 Onboarding**
5. **#8 Summary digest** → **#12 Insights** (share the analytics layer)
6. **#17 Offline sync**
7. **#16 Family mode** (separate initiative)

## Verification (per feature)
- **Backend**: run the API locally, exercise the new endpoint with a real user id + JWT (see
  `backend/src/utils/jwt.ts`), confirm DB rows created/deleted; add unit tests alongside existing ones
  (e.g. `validators.pagination.test.ts`, `jwt.test.ts`).
- **Mobile**: run the Flutter app (`pulsespend`), drive each new screen end-to-end against the running
  backend; verify offline/online transitions for #17 by toggling connectivity.

---

## Implementation notes (what shipped)

All DB changes are additive and idempotent (`CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS`),
applied automatically by `initDB()` on server start.

- **#13 Account deletion** — `DELETE /api/profile/:user_id` (password-confirmed) →
  `UserModel.deleteAccount` wipes every table incl. groups + Cloudinary photo. Mobile: "Danger Zone"
  in Manage Profile with a password dialog → `AuthController.deleteAccount` → clears session.
- **#4 CSV export** — `GET /api/transaction/export/:user_id` (RFC-4180 CSV, UTF-8 BOM, honours filters).
  Mobile: share-sheet export action on the Transactions screen.
- **#3 Server-side search & filters** — `TransactionModel.listByUserFiltered` + `parseTransactionFilters`
  (q / category / from / to / min / max / type). Mobile: debounced search, type chips, filter sheet
  (`transaction_filter_sheet.dart`) — all filtering now server-side across full history.
- **#15 Onboarding** — `features/onboarding/` PageView gated once via `SecureStorage.onboardingSeen`
  in `splash_gate.dart` (`_OnboardingGate`).
- **#8 Summary digest** — `SummaryDigestScheduler` (node-cron: weekly Mon 08:00, monthly 1st 08:00) →
  `AnalyticsModel.getDigest` → push (respects new `summary_digest` pref). In-app recap card on the
  dashboard via `GET /api/analytics/digest`; opt-in toggle in notification preferences.
- **#12 Insights** — `AnalyticsModel.getInsights` (templated NL, no LLM) at `GET /api/analytics/insights`;
  dashboard "Insights" card. (LLM upgrade optional later — see [claude-api] reference.)
- **#17 Offline queue & sync** — `OutboxService` (secure-storage queue) + optimistic entries; flush on
  socket reconnect; backend idempotency via `client_op_id` (unique per user). Pending-sync banner on
  the Transactions screen. (Create + delete are queued; offline edit is still online-only.)
- **#16 Shared / family groups** — `groups` + `group_members` tables, invite codes, `GroupModel`
  aggregates a read-only combined feed + merged summary (no ownership refactor). Endpoints under
  `/api/groups`; mobile `features/groups/` (list, create, join, detail) linked from Settings → Account.

### Follow-ups / known limits
- Offline **edit** of an existing transaction isn't queued yet (create/delete are).
- Group view is **read-only aggregation** — members still own their own transactions (deliberate, to
  avoid a full ownership-model rewrite). Shared *editing* would be a separate initiative.
- PDF export not built (CSV only, as recommended).
- Digest/insights currency conversion reuses the live-rate service per transaction; for very large
  histories consider caching.
