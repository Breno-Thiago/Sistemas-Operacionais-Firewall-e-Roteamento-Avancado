#!/usr/bin/env bash
set -euo pipefail

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Arquivo .env criado a partir de .env.example"
fi

echo "Subindo dashboard em http://localhost:8088"
if docker compose version >/dev/null 2>&1; then
  docker compose up --build
else
  docker-compose up --build
fi
