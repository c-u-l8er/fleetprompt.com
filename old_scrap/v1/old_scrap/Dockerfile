# syntax=docker/dockerfile:1

############################
# Frontend build (Vite)
############################
FROM node:20-bookworm-slim AS frontend

WORKDIR /app

# Install node dependencies with a cache-friendly layer
COPY frontend/package.json frontend/package-lock.json ./frontend/
RUN npm ci --prefix frontend

# Copy frontend source
COPY frontend ./frontend

# Ensure the backend static assets directory exists (Vite outputs here)
RUN mkdir -p /app/backend/priv/static/assets

# Build frontend into ../backend/priv/static/assets
RUN npm --prefix frontend run build


############################
# Backend build (Phoenix Release)
############################
FROM hexpm/elixir:1.18.2-erlang-27.0-debian-trixie-20251229-slim AS builder

ARG MIX_ENV=prod
ENV MIX_ENV=$MIX_ENV

WORKDIR /app/backend

# System deps for building Elixir/Erlang deps (and compiling any NIFs)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      build-essential \
      git \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

# Cache deps
COPY backend/mix.exs backend/mix.lock ./
COPY backend/config ./config
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy backend source
COPY backend ./

# Copy built frontend assets into the Phoenix static dir
COPY --from=frontend /app/backend/priv/static/assets ./priv/static/assets

# Compile + digest assets + build release
RUN mix compile
RUN mix phx.digest
RUN mix release


############################
# Runtime
############################
FROM debian:trixie-slim AS runner

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PHX_SERVER=true

WORKDIR /app

# Runtime deps (TLS, certs, terminal libs)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      openssl \
      libstdc++6 \
      libncurses6 \
      libtinfo6 && \
    rm -rf /var/lib/apt/lists/*

# Run as non-root
RUN useradd --system --create-home --home-dir /app app
USER app

# Copy the release from the builder
COPY --from=builder /app/backend/_build/prod/rel/fleet_prompt ./

EXPOSE 4000

CMD ["bin/fleet_prompt", "start"]
