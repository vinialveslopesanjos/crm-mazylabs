#!/usr/bin/env bash
set -euo pipefail
umask 077
sha="${1:-}"
[[ "$sha" =~ ^[a-f0-9]{40}$ ]] || exit 64
base=/opt/crm-mazylabs
release="$base/releases/$sha"
cd "$release"
export COMPOSE_PROJECT_NAME=crm-mazylabs
source hostgator-setup-kit/_common.sh
enter_project
previous="$(readlink -f "$base/current" 2>/dev/null || true)"
changed=0

dc() {
  docker compose -p crm-mazylabs -f docker-compose.prod.yml \
    -f infra/mazylabs/compose.yml --env-file .env "$@"
}
record() {
  printf '{"at":"%s","sha":"%s","status":"%s"}\n' \
    "$(date -u +%FT%TZ)" "$sha" "$1" >> "$base/state/deployments.jsonl"
}
rollback() {
  local rc=$?
  trap - ERR
  record failed
  if [ "$changed" = 1 ] && [ -n "$previous" ] && [ -f "$previous/.images.env" ]; then
    cd "$previous"
    load_env .images.env
    if dc up -d --no-build --wait --wait-timeout 180 app worker scheduler; then
      record rolled_back
      echo 'Falha no deploy; serviços voltaram para a versão anterior.' >&2
    else
      record rollback_failed
      echo 'Falha no rollback; verificar serviços na VPS.' >&2
    fi
  fi
  exit "$rc"
}
trap rollback ERR

registry=ghcr.io/vinialveslopesanjos
export APP_IMAGE="$registry/deskcommcrm:sha-$sha"
export WORKER_IMAGE="$registry/deskcomm-worker:sha-$sha"
export SCHEDULER_IMAGE="$registry/deskcomm-scheduler:sha-$sha"
export APP_PULL_POLICY=missing WORKER_PULL_POLICY=missing SCHEDULER_PULL_POLICY=missing
dc config --quiet
dc pull app worker scheduler waha redis srh

pin_image() {
  local image="$1" repository="${1%:*}" revision pin
  revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")"
  [ "$revision" = "$sha" ] || { echo 'Imagem não corresponde ao commit aprovado.' >&2; return 1; }
  pin="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image" \
    | awk -v prefix="$repository@sha256:" 'index($0,prefix)==1 && !found {print; found=1} END {if (!found) exit 1}')"
  [[ "$pin" =~ ^ghcr\.io/vinialveslopesanjos/[a-z-]+@sha256:[a-f0-9]{64}$ ]] || return 1
  printf '%s' "$pin"
}
# As tags localizam a publicação; os digests fixam o artefato de cada release.
# Atribuições separadas de `export`: o builtin não pode esconder falha do pin.
app_pin="$(pin_image "$APP_IMAGE")"
worker_pin="$(pin_image "$WORKER_IMAGE")"
scheduler_pin="$(pin_image "$SCHEDULER_IMAGE")"
export APP_IMAGE="$app_pin" WORKER_IMAGE="$worker_pin" SCHEDULER_IMAGE="$scheduler_pin"
printf 'APP_IMAGE=%s\nWORKER_IMAGE=%s\nSCHEDULER_IMAGE=%s\n' \
  "$APP_IMAGE" "$WORKER_IMAGE" "$SCHEDULER_IMAGE" > .images.env

if [ -n "$previous" ]; then
  # Reutiliza as verificações de integridade e retenção do kit original.
  BACKUP_DIR="$base/backups" bash hostgator-setup-kit/backup.sh
fi

pg_container postgres:17-alpine psql "$(url_do_schema)" -v ON_ERROR_STOP=1 -c \
  'create extension if not exists vector with schema public; create extension if not exists citext with schema public; create extension if not exists pg_trgm with schema public;' \
  > "$base/state/extensions.log" 2>&1
has_schema="$(psql_run -tAc "select to_regclass('public.organizations') is not null" | tr -d '[:space:]')"
if [ "$has_schema" = t ]; then
  reaplicar_baseline "$release/supabase/baseline.sql" "$base/state/baseline.log"
else
  pg_container -i -v "$release/supabase/baseline.sql:/baseline.sql:ro" \
    postgres:17-alpine psql "$(url_do_schema)" -v ON_ERROR_STOP=1 -f /baseline.sql \
    > "$base/state/baseline.log" 2>&1
fi

changed=1
dc up -d --no-build --wait --wait-timeout 240 app worker scheduler waha redis srh
# Verifica o login e as dependências reais antes de promover a release.
curl --fail --silent --show-error --max-time 20 http://127.0.0.1:3020/login > /dev/null
health="$(curl --fail --silent --show-error --max-time 20 http://127.0.0.1:3020/api/v1/health)"
printf '%s' "$health" | grep -Fq "${sha:0:7}"
ln -sfn "$release" "$base/current"
record success
echo "CRM atualizado: ${sha:0:7}."
