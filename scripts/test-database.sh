#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
container="flype-dictionary-test-$$"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
docker run -d --rm --name "$container" -e POSTGRES_PASSWORD=flype-local-test postgres:18-alpine >/dev/null
for attempt in {1..100}; do
  if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
  sleep 0.2
done
docker exec -i "$container" psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/bootstrap.sql
for migration in supabase/migrations/*.sql; do
  docker exec -i "$container" psql -U postgres -v ON_ERROR_STOP=1 < "$migration"
done
for suite in supabase/tests/dictionary.sql supabase/tests/settings.sql supabase/tests/cloud_cleanup.sql supabase/tests/account_deletion.sql; do
  docker exec -i "$container" psql -U postgres -v ON_ERROR_STOP=1 < "$suite"
done
print 'Datenbanktests erfolgreich.'
