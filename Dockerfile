# Stage 1: Build Flutter Web App (unverändert aus flutter_client/Dockerfile)
FROM ghcr.io/cirruslabs/flutter:3.41.9 AS flutter-build
WORKDIR /app
COPY flutter_client/pubspec.yaml flutter_client/pubspec.lock ./
RUN flutter pub get
COPY flutter_client/ .
RUN flutter build web --release

# Stage 2: Cloudron app image — Node-Backend + Nginx in einem Container
FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

ENV CLOUDRON=1

RUN mkdir -p /app/code
WORKDIR /app/code

# Node-Backend-Abhängigkeiten (separater Layer für Docker-Caching)
COPY server/package.json server/package-lock.json /app/code/server/
RUN cd /app/code/server && npm install --production

COPY server /app/code/server

# Optionaler First-Boot-Seed (server/seed/db_seed.sql.gz) — nur vorhanden, wenn
# vor dem Build ../pb_translation_hub/export_for_cloudron.sh --seed
# server/seed/db_seed.sql.gz gelaufen ist. Ohne diese Datei ist SEED_ON_FIRST_
# BOOT ein No-op (siehe server/index.js), das Image bleibt also auch ohne
# Seed baubar — server/seed/.gitkeep hält das Verzeichnis für COPY vorhanden.

# Flutter-Web-Build als Nginx-Docroot
COPY --from=flutter-build /app/build/web /app/code/web

# Nginx-Site-Config
COPY nginx/app.conf /etc/nginx/sites-available/app
RUN rm -f /etc/nginx/sites-enabled/* && \
    ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app

# nginx.conf's error_log is in the global context (outside http{}), so our
# sites-enabled config can't override it — /var/log/nginx/* is read-only here.
RUN sed -i \
    -e 's#error_log /var/log/nginx/error.log;#error_log /dev/stderr;#' \
    -e 's#access_log /var/log/nginx/access.log;#access_log /dev/stdout;#' \
    /etc/nginx/nginx.conf

COPY start.sh /app/code/start.sh

# The build context is uploaded from a Windows/WSL host over a UNC path,
# which sometimes loses the execute bit on directories (e.g. routes/,
# migrations/ came through as drw-rw-rw-, breaking require() traversal).
# Normalize permissions regardless of what came through.
RUN chmod -R a+rX /app/code && \
    chmod +x /app/code/start.sh && \
    chown -R cloudron:cloudron /app/code

CMD [ "/app/code/start.sh" ]
