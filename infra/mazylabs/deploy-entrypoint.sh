#!/usr/bin/env bash
# Entry point fixo, root-owned, fora do checkout. Chave SSH só chama este script.
set -euo pipefail
umask 077
request="${1:-}"
[[ "$request" =~ ^deploy\ ([a-f0-9]{40})$ ]] || { echo 'Comando recusado.' >&2; exit 64; }
sha="${BASH_REMATCH[1]}"
base=/opt/crm-mazylabs
mkdir -p "$base/state" "$base/releases"
exec 9>"$base/state/deploy.lock"
flock -w 600 9
[ -s "$base/shared/.env" ] || { echo 'Configuração inicial ausente.' >&2; exit 1; }
repo="$base/repository"
if [ ! -d "$repo/.git" ]; then
  git clone --branch main --single-branch https://github.com/vinialveslopesanjos/crm-mazylabs.git "$repo"
fi
git -C "$repo" fetch origin main
[ "$(git -C "$repo" rev-parse origin/main)" = "$sha" ] \
  || { echo 'Commit superado ou fora da main; deploy recusado.' >&2; exit 1; }
# O token de leitura do GHCR vive somente nesta execução; não fica na VPS.
if IFS= read -r registry_token && [ -n "$registry_token" ]; then
  export DOCKER_CONFIG
  DOCKER_CONFIG="$(mktemp -d "$base/state/docker-auth.XXXXXX")"
  trap 'rm -rf -- "$DOCKER_CONFIG"' EXIT
  # Preserva a descoberta do Compose quando a hospedagem o instala no home.
  if [ -d /root/.docker/cli-plugins ]; then
    ln -s /root/.docker/cli-plugins "$DOCKER_CONFIG/cli-plugins"
  fi
  printf '%s' "$registry_token" | docker login ghcr.io \
    --username vinialveslopesanjos --password-stdin > /dev/null
  unset registry_token
fi
release="$base/releases/$sha"
if [ ! -d "$release" ]; then
  mkdir "$release"
  git -C "$repo" archive "$sha" | tar -x -C "$release"
fi
ln -sfn "$base/shared/.env" "$release/.env"
bash "$release/infra/mazylabs/deploy-release.sh" "$sha"
