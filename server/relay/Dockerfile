# Wattlands relay (BRIEF 5.3). Build from server/relay:
#   docker build -t wattlands-relay .
#   docker run --rm -p 8787:8787 wattlands-relay
# Node runs the TypeScript sources directly (type stripping, unflagged since Node 22.18/23.6).
FROM node:24-alpine

ENV NODE_ENV=production \
    PORT=8787 \
    RELAY_LOG=info

WORKDIR /app

# The ws package when a lockfile is present; without one the relay uses its built-in
# RFC 6455 server, so the image also builds with zero npm dependencies.
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev --no-audit --no-fund && npm cache clean --force; fi

COPY src ./src

# Files stay root-owned and read-only for the runtime user.
USER node

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8787)+'/health').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"

CMD ["node", "--disable-warning=ExperimentalWarning", "src/main.ts"]
