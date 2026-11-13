#!/usr/bin/env sh
# Run in a Laravel project root:
#   curl -fsSL https://raw.githubusercontent.com/mnr73/larado/main/install.sh | sh
set -e
BASE="${LARADO_URL:-https://raw.githubusercontent.com/mnr73/larado/main}"
for f in Dockerfile compose.yml compose.dev.yml; do curl -fsSL "$BASE/$f" -o "$f"; done
# ponytail: appends once; to change defaults later edit .env by hand.
if [ -f .env ] && ! grep -q '^LARADO_IMAGE=' .env; then
    printf '\n' >> .env
    curl -fsSL "$BASE/.env.larado.example" >> .env
    echo "larado vars appended to .env"
fi
echo "set DB_HOST=mysql REDIS_HOST=redis in .env, then: docker compose up -d --build"
