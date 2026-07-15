import nodemailer from 'nodemailer';
import 'dotenv/config';

const smtpPort = Number(process.env.SMTP_PORT) || 465;

/**
 * Direct SMTP transport — the LOCAL DEV fallback only.
 *
 * Cloud hosts (Railway, Render, …) block outbound SMTP ports to stop spam, so
 * a direct connection just times out in production. Everything sends through
 * `sendMail()` in ./mailer.ts, which uses Brevo's HTTPS API when
 * BREVO_API_KEY is set and falls back to this transporter otherwise.
 */
export const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  // Port 465 = direct SSL (secure:true)  — not blocked by most ISPs.
  // Port 587 = STARTTLS (secure:false)   — often blocked by ISPs in South Asia.
  port: smtpPort,
  secure: smtpPort === 465,
  connectionTimeout: 15000,
  greetingTimeout: 15000,
  socketTimeout: 20000,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});
