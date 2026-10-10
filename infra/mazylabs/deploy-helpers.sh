#!/usr/bin/env bash

previous_release() {
  local base="$1" target
  # readlink -f também retorna caminho para um último componente inexistente.
  # Isso não pode transformar a primeira instalação em atualização.
  if [ ! -e "$base/current" ] && [ ! -L "$base/current" ]; then return 0; fi
  [ -L "$base/current" ] || { echo 'current não é um link de release.' >&2; return 1; }
  target="$(readlink -f "$base/current")"
  [ -d "$target" ] && [ -f "$target/.images.env" ] \
    && [ "$(dirname "$target")" = "$base/releases" ] \
    && [[ "$(basename "$target")" =~ ^[a-f0-9]{40}$ ]] \
    || { echo 'Release anterior inválida; deploy recusado.' >&2; return 1; }
  printf '%s' "$target"
}

pin_image() {
  local sha="$1" image="$2" repository="${2%:*}" revision pin
  [[ "$sha" =~ ^[a-f0-9]{40}$ ]] || return 1
  # Referências já fixadas mantêm seu repositório sem a parte do digest.
  repository="${repository%%@*}"
  revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")"
  [ "$revision" = "$sha" ] || { echo 'Imagem não corresponde ao commit aprovado.' >&2; return 1; }
  pin="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image" \
    | awk -v prefix="$repository@sha256:" 'index($0,prefix)==1 && !found {print; found=1} END {if (!found) exit 1}')"
  [[ "$pin" =~ ^ghcr\.io/vinialveslopesanjos/[a-z-]+@sha256:[a-f0-9]{64}$ ]] || return 1
  printf '%s' "$pin"
}
