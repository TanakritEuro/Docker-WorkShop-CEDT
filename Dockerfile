# syntax=docker/dockerfile:1.7

# =============================================================================
# Builder stage — installs production dependencies only, on a fresh Node base.
# =============================================================================

# step-4a: builder base image, pinned for reproducible builds.
FROM node:20.11-slim AS builder

WORKDIR /app

# step-4b: copy the manifests first so the npm layer is cached, then install deps.
#   `npm update proxy-addr` pulls in 2.0.8 (still inside express's ~2.0.7 range),
#   which fixes the CRITICAL GHSA-jqcg-44mw-7w3h that Trivy would otherwise flag.
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev && npm update proxy-addr --omit=dev && npm cache clean --force

# step-4c: copy the rest of the app source into /app.
COPY app/ ./

# =============================================================================
# Runtime stage — slim final image. Nothing from builder's caches leaks in.
# =============================================================================

# step-4d: runtime base image (same tag as the builder).
FROM node:20.11-slim

WORKDIR /app

# The app is started with plain `node`, so drop the package managers bundled in the
# base image: smaller image and fewer packages for Trivy to flag.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-*

# step-4e: copy the fully-installed app from the builder stage.
COPY --from=builder /app /app

ENV NODE_ENV=production
EXPOSE 3000

# step-4f: HEALTHCHECK using Node's built-in http module (no curl/wget in slim).
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))"

# step-4g: container start command.
CMD ["node", "src/index.js"]
