import { describe, it, expect } from 'vitest';
import { parseSender, encodeHeaderWord, formatAddress, buildMimeMessage } from './mailer';

describe('parseSender', () => {
  it('parses the RFC form `Name <email>`', () => {
    expect(parseSender('PulseSpend <you@example.com>')).toEqual({
      name: 'PulseSpend',
      email: 'you@example.com',
    });
  });

  it('parses a bare address', () => {
    expect(parseSender('you@example.com')).toEqual({ name: undefined, email: 'you@example.com' });
  });

  it('parses the bracket-less `Name email` form nodemailer tolerated', () => {
    // This is what the real .env had — Brevo 400s on it unless we extract.
    expect(parseSender('PulseSpend japansamurai1234@gmail.com')).toEqual({
      name: 'PulseSpend',
      email: 'japansamurai1234@gmail.com',
    });
  });

  it('strips surrounding quotes (dashboard paste mistake)', () => {
    expect(parseSender('"PulseSpend <you@example.com>"')).toEqual({
      name: 'PulseSpend',
      email: 'you@example.com',
    });
  });

  it('tolerates extra whitespace', () => {
    expect(parseSender('  PulseSpend   <  you@example.com  >  ')).toEqual({
      name: 'PulseSpend',
      email: 'you@example.com',
    });
  });

  it('returns the raw value when there is no address to find', () => {
    // sendMail validates this and throws a clear error rather than calling Brevo.
    expect(parseSender('PulseSpend').email).toBe('PulseSpend');
  });
});

describe('encodeHeaderWord', () => {
  it('passes plain ASCII through untouched', () => {
    expect(encodeHeaderWord('Your PulseSpend Passkey')).toBe('Your PulseSpend Passkey');
  });

  it('RFC 2047 encodes non-ASCII', () => {
    const encoded = encodeHeaderWord('ඔබේ passkey');
    expect(encoded).toMatch(/^=\?UTF-8\?B\?.+\?=$/);
    // Round-trips back to the original.
    const b64 = encoded.slice('=?UTF-8?B?'.length, -2);
    expect(Buffer.from(b64, 'base64').toString('utf8')).toBe('ඔබේ passkey');
  });
});

describe('formatAddress', () => {
  it('renders a bare address when there is no name', () => {
    expect(formatAddress({ email: 'a@b.com' })).toBe('a@b.com');
  });

  it('renders `Name <email>`', () => {
    expect(formatAddress({ name: 'PulseSpend', email: 'a@b.com' })).toBe('PulseSpend <a@b.com>');
  });

  it('quotes an ASCII display name containing specials', () => {
    expect(formatAddress({ name: 'Pulse, Spend', email: 'a@b.com' })).toBe('"Pulse, Spend" <a@b.com>');
  });

  it('encodes (and does NOT quote) a non-ASCII display name', () => {
    const out = formatAddress({ name: 'පල්ස්', email: 'a@b.com' });
    expect(out).toMatch(/^=\?UTF-8\?B\?.+\?= <a@b\.com>$/);
    expect(out).not.toContain('"');
  });
});

describe('buildMimeMessage', () => {
  const base = {
    from: { name: 'PulseSpend', email: 'me@gmail.com' },
    to: 'user@example.com',
    subject: 'Your PulseSpend Passkey',
    html: '<h1>123456</h1>',
  };

  it('emits the expected headers followed by a blank line then the body', () => {
    const mime = buildMimeMessage(base);
    const [headers, body] = mime.split('\r\n\r\n');
    expect(headers).toContain('From: PulseSpend <me@gmail.com>');
    expect(headers).toContain('To: user@example.com');
    expect(headers).toContain('Subject: Your PulseSpend Passkey');
    expect(headers).toContain('Content-Type: text/html; charset="UTF-8"');
    expect(headers).toContain('Content-Transfer-Encoding: base64');
    expect(body.length).toBeGreaterThan(0);
  });

  it('base64-encodes the HTML body so it round-trips', () => {
    const mime = buildMimeMessage(base);
    const body = mime.split('\r\n\r\n')[1].replace(/\r\n/g, '');
    expect(Buffer.from(body, 'base64').toString('utf8')).toBe('<h1>123456</h1>');
  });

  it('wraps the base64 body at 76 chars (RFC 2045)', () => {
    const mime = buildMimeMessage({ ...base, html: '<p>' + 'x'.repeat(500) + '</p>' });
    const lines = mime.split('\r\n\r\n')[1].split('\r\n');
    expect(lines.length).toBeGreaterThan(1);
    for (const line of lines) expect(line.length).toBeLessThanOrEqual(76);
  });

  it('omits Reply-To unless given', () => {
    expect(buildMimeMessage(base)).not.toContain('Reply-To:');
    expect(buildMimeMessage({ ...base, replyTo: 'x@y.com' })).toContain('Reply-To: x@y.com');
  });

  it('preserves UTF-8 in the body', () => {
    const html = '<p>ඔබේ passkey එක</p>';
    const mime = buildMimeMessage({ ...base, html });
    const body = mime.split('\r\n\r\n')[1].replace(/\r\n/g, '');
    expect(Buffer.from(body, 'base64').toString('utf8')).toBe(html);
  });
});
