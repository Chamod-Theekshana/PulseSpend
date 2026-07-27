# PulseSpend backend — portable container for a persistent host
# (Railway / Render / Fly.io). The app runs TypeScript at runtime via `tsx`
# (a production dependency), so there is no compile step — `npm start` is
# `tsx src/server.ts`. This keeps Socket.IO + all cron schedulers working,
# which serverless (e.g. Vercel) cannot do.
#
# Debian slim (glibc) + build tools so the native `bcrypt` module installs
# reliably on Node 22 (Alpine/musl can force a fragile source build).
FROM node:22-slim

WORKDIR /app

# Toolchain for native addons (bcrypt).
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

# Install dependencies first for better layer caching. `npm ci` installs the
# full lockfile (including tsx), so the runtime image can start with `npm start`.
COPY package*.json ./
RUN npm ci

# Application source.
COPY . .

ENV NODE_ENV=production

# Informational only — the app binds process.env.PORT, which the host injects.
EXPOSE 5001

# Optional container-level healthcheck (the app also exposes GET /health).
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||5001)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["npm", "start"]
