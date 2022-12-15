FROM fischerscode/flutter:3.3.9 AS builder

RUN mkdir app
WORKDIR app
COPY --chown=flutter pubspec.yaml .
COPY --chown=flutter pubspec.lock .
RUN flutter pub get
COPY --chown=flutter . .
RUN flutter build web

FROM nginx:1.23-alpine
COPY --from=builder /home/flutter/app/build/web /usr/share/nginx/html
