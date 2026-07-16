import 'dotenv/config';
import { transporter } from './nodemailer';

const BREVO_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';
const GMAIL_SEND_ENDPOINT = 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send';
const GOOGLE_TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const SEND_TIMEOUT_MS = 15000;

export interface MailOptions {
  to: string;
  subject: string;
  html: string;
  replyTo?: string;
}

export interface Sender {
  name?: string;
  email: string;
}

const EMAIL_RE = /[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+/;

/**
 * Parses a `from` value into a `{name, email}` sender.
 *
 * Accepts the RFC form `Name <email@host>`, a bare `email@host`, and also the
 * bracket-less `Name email@host` — nodemailer's parser tolerated that, so
 * existing .env files use it, but the JSON/MIME senders need the bare address.
 * Surrounding quotes (a common dashboard-paste mistake) are stripped too.
 */
export function parseSender(raw: string): Sender {
  const cleaned = raw.trim().replace(/^["']|["']$/g, '').trim();

  // `Name <email@host>`
  const bracketed = /^(.*?)\s*<\s*([^>]+?)\s*>$/.exec(cleaned);
  if (bracketed) {
    return { name: bracketed[1].trim() || undefined, email: bracketed[2].trim() };
  }

  // `Name email@host` or a bare `email@host`
  const m = EMAIL_RE.exec(cleaned);
  if (m) {
    const name = cleaned.replace(m[0], '').trim();
    return { name: name || undefined, email: m[0] };
  }

  return { email: cleaned };
}

/** Resolves + validates the configured sender, failing with a clear message. */
function senderFromEnv(): Sender {
  const raw = process.env.SMTP_FROM || process.env.SMTP_USER || '';
  const sender = parseSender(raw);
  if (!EMAIL_RE.test(sender.email)) {
    // Fail loudly and locally — the providers' own errors ("valid sender email
    // required") are too vague to debug from.
    throw new Error(
      `SMTP_FROM must contain a valid sender address (parsed "${sender.email}" from ` +
        `"${raw}"). Expected e.g. PulseSpend <you@example.com>`,
    );
  }
  return sender;
}

// ── MIME helpers (pure — unit tested) ────────────────────────────────────────

/** RFC 2047 encodes a header value when it isn't plain ASCII. */
export function encodeHeaderWord(value: string): string {
  if (/^[\x20-\x7E]*$/.test(value)) return value;
  return `=?UTF-8?B?${Buffer.from(value, 'utf8').toString('base64')}?=`;
}

/** Renders a sender as a `From:` header value. */
export function formatAddress({ name, email }: Sender): string {
  if (!name) return email;
  const encoded = encodeHeaderWord(name);
  // A plain-ASCII display name containing specials must be quoted; an RFC 2047
  // encoded-word must NOT be.
  const needsQuote = encoded === name && /["(),:;<>@[\\\]]/.test(name);
  return `${needsQuote ? `"${name.replace(/(["\\])/g, '\\$1')}"` : encoded} <${email}>`;
}

/** Builds an RFC 2822 message with a base64 UTF-8 HTML body. */
export function buildMimeMessage(opts: {
  from: Sender;
  to: string;
  subject: string;
  html: string;
  replyTo?: string;
}): string {
  const headers = [
    `From: ${formatAddress(opts.from)}`,
    `To: ${opts.to}`,
    ...(opts.replyTo ? [`Reply-To: ${opts.replyTo}`] : []),
    `Subject: ${encodeHeaderWord(opts.subject)}`,
    'MIME-Version: 1.0',
    'Content-Type: text/html; charset="UTF-8"',
    'Content-Transfer-Encoding: base64',
  ];
  // base64 bodies must be wrapped at <= 76 chars per RFC 2045.
  const body = (Buffer.from(opts.html, 'utf8').toString('base64').match(/.{1,76}/g) ?? []).join('\r\n');
  return `${headers.join('\r\n')}\r\n\r\n${body}`;
}

function toBase64Url(value: string): string {
  return Buffer.from(value, 'utf8')
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

// ── Gmail API transport ──────────────────────────────────────────────────────

/** Cached OAuth access token — they live ~1h, so don't re-mint one per email. */
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function gmailAccessToken(): Promise<string> {
  if (cachedAccessToken && Date.now() < cachedAccessToken.expiresAt - 60_000) {
    return cachedAccessToken.token;
  }

  const clientId = process.env.GMAIL_CLIENT_ID?.trim();
  const clientSecret = process.env.GMAIL_CLIENT_SECRET?.trim();
  const refreshToken = process.env.GMAIL_REFRESH_TOKEN?.trim();
  if (!clientId || !clientSecret || !refreshToken) {
    throw new Error('GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET and GMAIL_REFRESH_TOKEN must all be set');
  }

  const res = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
    signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    // `invalid_grant` here almost always means the OAuth consent screen is still
    // in "Testing" mode (Google expires those refresh tokens after 7 days) or
    // access was revoked — re-run scripts/gmail-oauth.ts after publishing it.
    throw new Error(`Gmail OAuth token refresh failed (${res.status}): ${body.slice(0, 300)}`);
  }

  const data = (await res.json()) as { access_token: string; expires_in: number };
  cachedAccessToken = {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000,
  };
  return cachedAccessToken.token;
}

async function sendViaGmail({ to, subject, html, replyTo }: MailOptions): Promise<void> {
  const from = senderFromEnv();
  const accessToken = await gmailAccessToken();
  const raw = toBase64Url(buildMimeMessage({ from, to, subject, html, replyTo }));

  const res = await fetch(GMAIL_SEND_ENDPOINT, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ raw }),
    signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Gmail send failed (${res.status}): ${body.slice(0, 300)}`);
  }

  const { id } = (await res.json().catch(() => ({}))) as { id?: string };
  console.log(`[Mail] Gmail accepted → ${to} (id: ${id ?? 'n/a'})`);
}

// ── Brevo transport ──────────────────────────────────────────────────────────

async function sendViaBrevo({ to, subject, html, replyTo }: MailOptions, apiKey: string): Promise<void> {
  const sender = senderFromEnv();

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

  // Log the messageId so a "sent but never arrived" report can be traced in
  // Brevo → Transactional → Logs (accepted ≠ delivered).
  const { messageId } = (await res.json().catch(() => ({}))) as { messageId?: string };
  console.log(`[Mail] Brevo accepted → ${to} (messageId: ${messageId ?? 'n/a'})`);
}

// ── Public API ───────────────────────────────────────────────────────────────

/**
 * Single choke point for every transactional email (signup passkey, password
 * reset OTP, support/feedback).
 *
 * Transport is picked by which credentials are configured:
 *
 *   GMAIL_REFRESH_TOKEN → Gmail API over HTTPS  (production)
 *   BREVO_API_KEY       → Brevo API over HTTPS  (alternative)
 *   neither             → direct SMTP           (local dev)
 *
 * Why not SMTP in production: cloud hosts (Railway, Render, …) block outbound
 * SMTP ports to prevent spam, so nodemailer just times out there.
 *
 * Why Gmail over an ESP: without an authenticated custom domain, an ESP sends
 * from its *shared* domain, so you inherit the whole free-tier pool's
 * reputation (Gmail rate-limited us with 421 4.7.28). The Gmail API is sent by
 * Google as the account itself, so SPF/DKIM/DMARC align and it lands in the
 * inbox — no domain required.
 */
export async function sendMail(options: MailOptions): Promise<void> {
  if (process.env.GMAIL_REFRESH_TOKEN?.trim()) return sendViaGmail(options);

  const brevoKey = process.env.BREVO_API_KEY?.trim();
  if (brevoKey) return sendViaBrevo(options, brevoKey);

  // ── Local dev fallback: direct SMTP ──
  await transporter.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: options.to,
    subject: options.subject,
    html: options.html,
    ...(options.replyTo ? { replyTo: options.replyTo } : {}),
  });
}
