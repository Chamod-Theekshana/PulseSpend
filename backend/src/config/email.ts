import { sendMail } from './mailer';

/** Shared markup for the 6-digit code emails (signup passkey / reset OTP). */
function codeEmailHtml(label: string, code: string): string {
  return `
      <h2>Your verification ${label} is:</h2>
      <h1 style="color: #DBFF00; font-size: 32px; letter-spacing: 8px;">${code}</h1>
      <p>This ${label} will expire in 5 minutes.</p>
      <p>If you didn't request this, please ignore this email.</p>
    `;
}

export async function sendOTPEmail(email: string, otp: string): Promise<void> {
  await sendMail({
    to: email,
    subject: 'Your PulseSpend OTP',
    html: codeEmailHtml('OTP', otp),
  });
}

export async function sendPasskeyEmail(email: string, passkey: string): Promise<void> {
  await sendMail({
    to: email,
    subject: 'Your PulseSpend Passkey',
    html: codeEmailHtml('passkey', passkey),
  });
}
