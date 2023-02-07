FROM cirrusci/flutter:3.7.1 AS builder
RUN mkdir app
WORKDIR app
COPY . .
RUN flutter pub get
RUN flutter build web

FROM nginx:1.23-alpine
COPY --from=builder /app/build/web /usr/share/nginx/html
