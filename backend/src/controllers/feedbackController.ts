import type { Response } from 'express';
import type { AuthedRequest } from '../middleware/requireAuth';
import { FeedbackModel, FEEDBACK_CATEGORIES } from '../models/FeedbackModel';
import { transporter } from '../config/nodemailer';

/** Escape user-controlled values before interpolating them into HTML email. */
function escapeHtml(input: unknown): string {
  return String(input ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * POST /api/feedback
 * Submits a "Report a Problem" / feedback message. Persists it and — if SMTP
 * is configured — emails the support inbox. Email failures are non-fatal.
 */
export async function submitFeedback(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const { category, subject, message, email, app_version, platform } = req.body ?? {};

  const cat = typeof category === 'string' && FEEDBACK_CATEGORIES.includes(category)
    ? category
    : 'problem';

  if (typeof subject !== 'string' || subject.trim().length < 3) {
    return res.status(400).json({ message: 'Subject must be at least 3 characters' });
  }
  if (subject.trim().length > 200) {
    return res.status(400).json({ message: 'Subject must be 200 characters or fewer' });
  }
  if (typeof message !== 'string' || message.trim().length < 10) {
    return res.status(400).json({ message: 'Message must be at least 10 characters' });
  }
  if (message.trim().length > 5000) {
    return res.status(400).json({ message: 'Message must be 5000 characters or fewer' });
  }

  const contactEmail =
    typeof email === 'string' && email.trim() ? email.trim() : (req.user!.email ?? null);

  const feedback = await FeedbackModel.create(userId, {
    category: cat,
    subject: subject.trim(),
    message: message.trim(),
    email: contactEmail,
    app_version: typeof app_version === 'string' ? app_version.slice(0, 40) : null,
    platform: typeof platform === 'string' ? platform.slice(0, 40) : null,
  });

  // Fire-and-forget support email (never blocks the response).
  const supportInbox = process.env.SUPPORT_EMAIL || process.env.SMTP_USER;
  if (supportInbox) {
    transporter
      .sendMail({
        from: process.env.SMTP_FROM || process.env.SMTP_USER,
        to: supportInbox,
        replyTo: contactEmail ?? undefined,
        subject: `[PulseSpend ${cat}] ${feedback.subject}`,
        html: `
          <h2>New ${escapeHtml(cat)} report</h2>
          <p><strong>From user:</strong> ${escapeHtml(userId)} (${escapeHtml(contactEmail ?? 'no email')})</p>
          <p><strong>Subject:</strong> ${escapeHtml(feedback.subject)}</p>
          <p><strong>Platform:</strong> ${escapeHtml(feedback.platform ?? '—')} · <strong>App:</strong> ${escapeHtml(feedback.app_version ?? '—')}</p>
          <hr/>
          <p style="white-space:pre-wrap">${escapeHtml(feedback.message)}</p>
        `,
      })
      .catch((err) => console.error('[Feedback] Support email failed:', err?.message));
  }

  return res.status(201).json({ message: 'Thanks for your feedback!', feedback });
}

/** GET /api/feedback — the signed-in user's own submitted reports. */
export async function listMyFeedback(req: AuthedRequest, res: Response) {
  const userId = String(req.user!.id);
  const feedback = await FeedbackModel.listByUser(userId);
  return res.json({ feedback });
}
