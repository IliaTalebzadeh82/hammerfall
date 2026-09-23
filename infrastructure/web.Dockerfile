FROM node:24.20.0-bookworm-slim

WORKDIR /app
COPY apps/web/package.json apps/web/package-lock.json ./
RUN npm ci
ARG LOCAL_UID=1000
ARG LOCAL_GID=1000
RUN groupmod --non-unique --gid ${LOCAL_GID} node && usermod --non-unique --uid ${LOCAL_UID} --gid ${LOCAL_GID} node
RUN mkdir -p /app/.next && chown -R node:node /app
USER node
RUN sha256sum package.json package-lock.json > node_modules/.hammerfall-dependencies
COPY infrastructure/web-dev.sh /usr/local/bin/hammerfall-web-dev
EXPOSE 3000
CMD ["hammerfall-web-dev"]
