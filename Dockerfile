# Builds the Flutter web app and serves it with nginx on port 8080.
#
#   docker build -t bringmeback-web .
#   docker run --rm -p 8080:8080 bringmeback-web
#
# Then open http://localhost:8080.

# ---- Build stage ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS build

# Keep in step with flutter-version in .github/workflows/*.yaml.
ARG FLUTTER_VERSION=3.47.7

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git python3 unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt \
 && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN flutter config --no-analytics --enable-web >/dev/null \
 && flutter precache --web

WORKDIR /app

# Fetch packages first so this layer is reused when only the app code changes.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
# A checkout on Windows may have CRLF line endings, which break the bash script and the checksum file.
RUN sed -i 's/\r$//' tool/build_symbolon.sh tool/symbolon-web.sha256 \
 && bash tool/build_symbolon.sh web \
 && flutter build web --release --no-web-resources-cdn

# ---- Serve stage ---------------------------------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.29-alpine

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 8080
