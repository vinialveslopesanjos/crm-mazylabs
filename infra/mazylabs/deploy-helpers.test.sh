#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/deploy-helpers.sh"
tmp_parent="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
tmp="$(mktemp -d "$tmp_parent/crm-deploy-test.XXXXXX")"
cleanup() {
  # Confere o destino resolvido antes de remover a pasta criada pelo teste.
  case "$(cd "$tmp" && pwd -P)" in
    "$tmp_parent"/crm-deploy-test.*) rm -rf -- "$tmp" ;;
    *) echo 'Recusei remover uma pasta fora do teste.' >&2 ;;
  esac
}
trap cleanup EXIT
sha="$(printf 'a%.0s' {1..40})"
digest="$(printf 'b%.0s' {1..64})"
base="$tmp/project"
mkdir -p "$base/releases/$sha" "$tmp/bin"

[ -z "$(previous_release "$base")" ]
echo 'PASS: instalação inicial não tem release anterior.'
printf 'APP_IMAGE=pin-de-teste\n' > "$base/releases/$sha/.images.env"
ln -s "$base/releases/$sha" "$base/current"
[ "$(previous_release "$base")" = "$base/releases/$sha" ]
echo 'PASS: atualização identifica a release realmente existente.'
rm "$base/current"
ln -s "$tmp" "$base/current"
if previous_release "$base" > /dev/null 2>&1; then exit 1; fi
echo 'PASS: current fora das releases é recusado.'

cat > "$tmp/bin/docker" <<'FAKE'
#!/usr/bin/env sh
case "$4" in
  *Config.Labels*) printf '%s\n' "$CRM_TEST_REVISION" ;;
  *RepoDigests*) printf '%s\n' "$CRM_TEST_DIGESTS" ;;
  *) exit 2 ;;
esac
FAKE
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH"
image='ghcr.io/vinialveslopesanjos/deskcommcrm:sha-teste'
pin="ghcr.io/vinialveslopesanjos/deskcommcrm@sha256:$digest"
export CRM_TEST_REVISION="$sha" CRM_TEST_DIGESTS="$pin"
[ "$(pin_image "$sha" "$image")" = "$pin" ]
[ "$(pin_image "$sha" "$pin")" = "$pin" ]
echo 'PASS: tag e digest retornam o artefato do repositório correto.'
CRM_TEST_REVISION='commit-errado'
if pin_image "$sha" "$image" > /dev/null 2>&1; then exit 1; fi
echo 'PASS: imagem de outro commit é recusada.'
CRM_TEST_REVISION="$sha"
CRM_TEST_DIGESTS="ghcr.io/outro/deskcommcrm@sha256:$digest"
if pin_image "$sha" "$image" > /dev/null 2>&1; then exit 1; fi
echo 'PASS: digest de outro repositório é recusado.'
CRM_TEST_DIGESTS='ghcr.io/vinialveslopesanjos/deskcommcrm@sha256:curto'
if pin_image "$sha" "$image" > /dev/null 2>&1; then exit 1; fi
echo 'PASS: digest incompleto é recusado.'
