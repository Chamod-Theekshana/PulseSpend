/**
 * One-time helper: obtains a Gmail API refresh token for sending mail.
 *
 * Usage (from backend/):
 *   GMAIL_CLIENT_ID=... GMAIL_CLIENT_SECRET=... npx tsx scripts/gmail-oauth.ts
 *
 * Google removed the out-of-band (copy/paste code) flow, so this spins up a
 * temporary loopback server, waits for the consent redirect, exchanges the code
 * and prints the refresh token. Create the OAuth client as a **Desktop app** —
 * that type allows http://localhost redirects without registering a URI.
 *
 * IMPORTANT: publish the OAuth consent screen. While it stays in "Testing",
 * Google expires refresh tokens after 7 days and production breaks weekly.
 */
import http from 'http';

const PORT = 53682;
const REDIRECT_URI = `http://localhost:${PORT}`;
const SCOPE = 'https://www.googleapis.com/auth/gmail.send';

const clientId = process.env.GMAIL_CLIENT_ID?.trim();
const clientSecret = process.env.GMAIL_CLIENT_SECRET?.trim();

if (!clientId || !clientSecret) {
  console.error(
    'Missing credentials.\n\n' +
      '  GMAIL_CLIENT_ID=xxx GMAIL_CLIENT_SECRET=yyy npx tsx scripts/gmail-oauth.ts\n\n' +
      'Get them from Google Cloud Console → APIs & Services → Credentials →\n' +
      'Create OAuth client ID → Desktop app.',
  );
  process.exit(1);
}

const authUrl =
  'https://accounts.google.com/o/oauth2/v2/auth?' +
  new URLSearchParams({
    client_id: clientId,
    redirect_uri: REDIRECT_URI,
    response_type: 'code',
    scope: SCOPE,
    access_type: 'offline', // ask for a refresh token
    prompt: 'consent', // force one even if previously granted
  });

async function exchangeCode(code: string): Promise<Record<string, unknown>> {
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: clientId!,
      client_secret: clientSecret!,
      redirect_uri: REDIRECT_URI,
      grant_type: 'authorization_code',
    }),
  });
  const data = (await res.json()) as Record<string, unknown>;
  if (!res.ok) throw new Error(`Token exchange failed (${res.status}): ${JSON.stringify(data)}`);
  return data;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', REDIRECT_URI);
  const code = url.searchParams.get('code');
  const error = url.searchParams.get('error');

  if (error) {
    res.writeHead(400, { 'content-type': 'text/plain' });
    res.end(`Authorisation failed: ${error}`);
    console.error(`\n✗ Authorisation failed: ${error}`);
    server.close();
    process.exit(1);
  }

  if (!code) {
    // Ignore favicon and other stray hits while we wait for the redirect.
    res.writeHead(204);
    res.end();
    return;
  }

  try {
    const tokens = await exchangeCode(code);
    const refreshToken = tokens.refresh_token as string | undefined;

    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(
      refreshToken
        ? '<h2>✅ Done — refresh token printed in your terminal.</h2><p>You can close this tab.</p>'
        : '<h2>⚠️ No refresh token returned.</h2><p>Check the terminal.</p>',
    );

    if (!refreshToken) {
      console.error(
        '\n✗ No refresh_token in the response. Google only returns one on first consent —\n' +
          '  revoke access at https://myaccount.google.com/permissions and run this again.\n' +
          `  Raw response: ${JSON.stringify(tokens)}`,
      );
      server.close();
      process.exit(1);
    }

    console.log('\n──────────────────────────────────────────────────────────────');
    console.log('✅ GMAIL_REFRESH_TOKEN');
    console.log(refreshToken);
    console.log('──────────────────────────────────────────────────────────────');
    console.log('\nAdd these to Railway (and your local .env):');
    console.log('  GMAIL_CLIENT_ID     = <your client id>');
    console.log('  GMAIL_CLIENT_SECRET = <your client secret>');
    console.log('  GMAIL_REFRESH_TOKEN = <the token above>');
    console.log('  SMTP_FROM           = PulseSpend <your-gmail@gmail.com>\n');
    console.log('⚠️  Publish the OAuth consent screen, or this token dies in 7 days.\n');

    server.close();
    process.exit(0);
  } catch (err) {
    res.writeHead(500, { 'content-type': 'text/plain' });
    res.end('Token exchange failed — see terminal.');
    console.error('\n✗', (err as Error).message);
    server.close();
    process.exit(1);
  }
});

server.listen(PORT, () => {
  console.log('\nOpen this URL in your browser and grant access:\n');
  console.log(authUrl);
  console.log(`\nWaiting for the redirect on ${REDIRECT_URI} …`);
  console.log("(Google will warn the app is unverified — it's yours, click Advanced → Continue.)\n");
});
