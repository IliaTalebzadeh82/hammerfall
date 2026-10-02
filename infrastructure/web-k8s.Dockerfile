FROM node:24.20.0-bookworm-slim

WORKDIR /app
COPY apps/web/package.json apps/web/package-lock.json ./
RUN npm ci
COPY --chown=node:node apps/web/ ./
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build && chown -R node:node /app/.next
USER node
EXPOSE 3000
CMD ["./node_modules/.bin/next", "start", "--hostname", "0.0.0.0"]
