#!/usr/bin/env bash
# Executar uma vez como administrador na VPS, com a chave PÚBLICA do CI.
set -euo pipefail
umask 077
[ "$EUID" = 0 ] || { echo 'Execute como administrador.' >&2; exit 1; }
key_file="${1:?uso: provision-deploy-access.sh <arquivo da chave pública>}"
ssh-keygen -lf "$key_file" > /dev/null
public_key="$(head -n 1 "$key_file")"
[[ "$public_key" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ .*)?$ ]] || exit 64

if ! id crm-deploy > /dev/null 2>&1; then
  useradd --create-home --shell /bin/bash crm-deploy
fi
if id -nG crm-deploy | tr ' ' '\n' | grep -qx docker; then
  echo 'O usuário crm-deploy já tem acesso amplo ao Docker; revise antes de continuar.' >&2
  exit 1
fi
install -d -m 0700 -o root -g root /opt/crm-mazylabs/shared /opt/crm-mazylabs/state
source_dir="$(cd "$(dirname "$0")" && pwd)"
install -m 0755 -o root -g root "$source_dir/deploy-entrypoint.sh" /usr/local/sbin/crm-mazylabs-deploy
cat > /usr/local/sbin/crm-mazylabs-ssh <<'WRAPPER'
#!/bin/sh
exec sudo -n /usr/local/sbin/crm-mazylabs-deploy "${SSH_ORIGINAL_COMMAND:-}"
WRAPPER
chown root:root /usr/local/sbin/crm-mazylabs-ssh
chmod 0755 /usr/local/sbin/crm-mazylabs-ssh

sudoers="$(mktemp)"
trap 'rm -f -- "$sudoers"' EXIT
printf '%s\n' 'crm-deploy ALL=(root) NOPASSWD: /usr/local/sbin/crm-mazylabs-deploy *' > "$sudoers"
visudo -cf "$sudoers" > /dev/null
install -m 0440 -o root -g root "$sudoers" /etc/sudoers.d/crm-mazylabs

install -d -m 0755 -o root -g root /home/crm-deploy/.ssh
authorized=/home/crm-deploy/.ssh/authorized_keys
line="restrict,command=\"/usr/local/sbin/crm-mazylabs-ssh\" $public_key"
touch "$authorized"
grep -Fqx "$line" "$authorized" || printf '%s\n' "$line" >> "$authorized"
chown root:root "$authorized"
chmod 0644 "$authorized"
echo 'Acesso do CI instalado: somente deploy do CRM, sem PTY nem encaminhamento de portas.'
