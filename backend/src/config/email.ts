import { transporter } from './nodemailer';

export async function sendOTPEmail(email: string, otp: string): Promise<void> {
  await transporter.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: email,
    subject: 'Your PulseSpend OTP',
    html: `
      <h2>Your verification OTP is:</h2>
      <h1 style="color: #DBFF00; font-size: 32px; letter-spacing: 8px;">${otp}</h1>
      <p>This OTP will expire in 5 minutes.</p>
      <p>If you didn't request this, please ignore this email.</p>
    `,
  });
}
