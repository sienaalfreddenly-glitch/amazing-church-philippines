# syntax=docker/dockerfile:1

# ---- deps ---------------------------------------------------------------
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# Capacitor's native platform packages are only needed to build the mobile
# apps, never to serve the website, so the image installs production deps only.
RUN npm ci --omit=dev --ignore-scripts

# ---- builder ------------------------------------------------------------
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY . .

# NEXT_PUBLIC_* values are inlined into the client bundle at build time, so the
# public origin has to be known here rather than at container start. Rebuild the
# image if the public URL changes.
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_FACEBOOK_PAGE_URL
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY \
    NEXT_PUBLIC_FACEBOOK_PAGE_URL=$NEXT_PUBLIC_FACEBOOK_PAGE_URL \
    NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# ---- runner -------------------------------------------------------------
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
# The standalone output already contains the trimmed node_modules and server.js.
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000

# No shell, so a container stop signals node directly.
CMD ["node", "server.js"]
