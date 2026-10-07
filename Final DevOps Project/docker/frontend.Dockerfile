# ReadTrack frontend - stage 1 builds the Vite bundle with Node, stage 2 serves it
# with the unprivileged nginx image (runs as uid 101, listens on 8080).
# build: docker build -f docker/frontend.Dockerfile -t readtrack-frontend application/frontend
FROM public.ecr.aws/docker/library/node:22-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

FROM public.ecr.aws/nginx/nginx-unprivileged:1.27-alpine
LABEL org.opencontainers.image.source="https://github.com/AbhiGandhi02/Devops-Assignment" \
      org.opencontainers.image.description="ReadTrack web UI - Final DevOps Project"
USER root
RUN apk upgrade --no-cache
USER 101
ENV BACKEND_URL=http://backend:8000
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
