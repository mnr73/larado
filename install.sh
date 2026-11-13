#!/usr/bin/env sh
# Run in a Laravel project root:
#   curl -fsSL https://raw.githubusercontent.com/mnr73/larado/main/install.sh | sh
# Pick php version:  ... | PHP_VERSION=8.3 sh
set -e
BASE="${LARADO_URL:-https://raw.githubusercontent.com/mnr73/larado/main}"
for f in Dockerfile compose.yml compose.dev.yml; do curl -fsSL "$BASE/$f" -o "$f"; done
# ponytail: appends once; to change defaults later edit .env by hand.
if [ -f .env ] && ! grep -q '^LARADO_IMAGE=' .env; then
    printf '\n' >> .env
    curl -fsSL "$BASE/.env.larado.example" >> .env
    echo "larado vars appended to .env"
fi
if [ -n "$PHP_VERSION" ]; then
    [ -f .env ] || { echo "no .env here: create it, then re-run" >&2; exit 1; }
    if grep -q '^PHP_VERSION=' .env; then
        sed -i.bak "s/^PHP_VERSION=.*/PHP_VERSION=$PHP_VERSION/" .env && rm -f .env.bak
    else
        printf 'PHP_VERSION=%s\n' "$PHP_VERSION" >> .env
    fi
    echo "PHP_VERSION=$PHP_VERSION"
fi
echo "set DB_HOST=mysql REDIS_HOST=redis in .env, then: docker compose up -d --build"
