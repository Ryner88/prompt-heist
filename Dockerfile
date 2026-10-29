FROM ubuntu:24.04 AS web-build

ARG GODOT_VERSION=4.7.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --output /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -j /tmp/godot.zip -d /usr/local/bin \
    && mv "/usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
    && curl --fail --location --output /tmp/godot-templates.tpz \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
    && unzip -j /tmp/godot-templates.tpz templates/version.txt templates/web_nothreads_release.zip \
      -d "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
    && rm /tmp/godot.zip /tmp/godot-templates.tpz

WORKDIR /src
COPY . .
RUN mkdir -p /out && godot --headless --path . --export-release Web /out/index.html

FROM node:22.22.0-alpine3.23

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=10000 \
    STATIC_DIR=/app/public

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY server ./server
COPY --from=web-build /out ./public

USER node
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/healthz').then(r => { if (!r.ok) process.exit(1) }).catch(() => process.exit(1))"

CMD ["node", "server/src/main.js"]
