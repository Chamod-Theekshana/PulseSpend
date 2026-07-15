import 'dotenv/config';
import { transporter } from './nodemailer';

const BREVO_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';
const SEND_TIMEOUT_MS = 15000;

export interface MailOptions {
  to: string;
  subject: string;
  html: string;
  replyTo?: string;
}

/** Parses `Name <email@host>` (or a bare address) into Brevo's sender shape. */
function parseSender(raw: string): { name?: string; email: string } {
  const m = /^\s*(.*?)\s*<\s*([^>]+?)\s*>\s*$/.exec(raw);
  if (m) return { name: m[1] || undefined, email: m[2] };
  return { email: raw.trim() };
}

function senderFromEnv(): { name?: string; email: string } {
  const raw = process.env.SMTP_FROM || process.env.SMTP_USER || '';
  return parseSender(raw);
}

/**
 * Single choke point for every transactional email (signup passkey, password
 * reset OTP, support/feedback).
 *
 * Cloud hosts (Railway, Render, …) block outbound SMTP ports to prevent spam,
 * so a direct nodemailer connection just times out in production. When
 * BREVO_API_KEY is set we send over Brevo's HTTPS API instead — port 443 is
 * never blocked. Without the key we fall back to the SMTP transporter, so
 * local dev keeps working against Gmail unchanged.
 *
 * The sender address must be a *verified sender* in Brevo (Senders & IPs →
 * Senders), otherwise Brevo rejects the request with 400.
 */
export async function sendMail({ to, subject, html, replyTo }: MailOptions): Promise<void> {
  const apiKey = process.env.BREVO_API_KEY?.trim();

  // ── Production path: Brevo HTTPS API ──
  if (apiKey) {
    const sender = senderFromEnv();
    if (!sender.email) {
      throw new Error('SMTP_FROM (or SMTP_USER) must be set to a Brevo-verified sender address');
    }

    const res = await fetch(BREVO_ENDPOINT, {
      method: 'POST',
      headers: {
        'api-key': apiKey,
        'content-type': 'application/json',
        accept: 'application/json',
      },
      body: JSON.stringify({
        sender,
        to: [{ email: to }],
        subject,
        htmlContent: html,
        ...(replyTo ? { replyTo: { email: replyTo } } : {}),
      }),
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    });

    if (!res.ok) {
      // Brevo returns a JSON error body ({code, message}) — surface it so a bad
      // key / unverified sender is obvious in the logs instead of a silent fail.
      const body = await res.text().catch(() => '');
      throw new Error(`Brevo send failed (${res.status}): ${body.slice(0, 300)}`);
    }
    return;
  }

  // ── Local dev fallback: direct SMTP ──
  await transporter.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to,
    subject,
    html,
    ...(replyTo ? { replyTo } : {}),
  });
}
