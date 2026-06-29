import nodemailer from 'nodemailer';
import 'dotenv/config';

const smtpPort = Number(process.env.SMTP_PORT) || 465;

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

export async function sendPasskeyEmail(email: string, passkey: string): Promise<void> {
  await transporter.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: email,
    subject: 'Your PulseSpend Passkey',
    html: `
      <h2>Your verification passkey is:</h2>
      <h1 style="color: #DBFF00; font-size: 32px; letter-spacing: 8px;">${passkey}</h1>
      <p>This passkey will expire in 5 minutes.</p>
      <p>If you didn't request this, please ignore this email.</p>
    `,
  });
}
