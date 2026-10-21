#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${LOCAL_ENV_FILE:-.env.local}"

json_value() {
  local key="$1"
  node -e 'let s=""; process.stdin.on("data", c => s += c).on("end", () => {
    const value = JSON.parse(s)[process.argv[1]];
    process.stdout.write(value == null ? "" : String(value));
  })' "$key"
}

env_value() {
  local key="$1"
  [[ -f "$ENV_FILE" ]] || return 0
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE"
}

# O WAHA publica o engine NOWEB em tags distintas por arquitetura. A tag padrão
# do compose (`latest-2026.7.2`) só existe em linux/amd64: num host ARM64 — Mac
# Apple Silicon, VPS A1 — o `pull` morre com "no matching manifest for
# linux/arm64/v8" e o `local:up` inteiro cai antes de subir o app. A regra é a
# MESMA de `hostgator-setup-kit/_common.sh` (imagem_waha_padrao_para_host), e as
# duas tags são a mesma versão funcional; `tests/shell/stack-local.test.sh`
# compara as duas para elas não divergirem.
imagem_waha_para_esta_maquina() {
  case "$(uname -m 2>/dev/null || true)" in
    aarch64|arm64) printf '%s' 'devlikeapro/waha:noweb-arm-2026.7.2' ;;
    *)             printf '%s' 'devlikeapro/waha:latest-2026.7.2' ;;
  esac
}

# Referências que sabidamente só têm linux/amd64 — as que o install.sh antigo
# gravava (#1266), mais o default do compose. Qualquer outro valor é escolha de
# quem desenvolve (WAHA Plus, tag própria) e não é da conta deste script.
waha_so_amd64_conhecido() {
  case "${1:-}" in
    ""|devlikeapro/waha|devlikeapro/waha:latest|devlikeapro/waha:latest-2026.7.2) return 0 ;;
  esac
  return 1
}

# Quem já tem `.env.local` de antes desta variável existir recebe a tag SEM
# regenerar o ambiente: regenerar trocaria portas, chaves e o pareamento da
# sessão de WhatsApp. Só toca no vazio (preenche) e no WAHA amd64 conhecido em
# host ARM64 — o mesmo critério do kit.
ensure_waha_image() {
  local esperada atual tmp
  esperada="$(imagem_waha_para_esta_maquina)"
  atual="$(env_value WAHA_IMAGE)"
  [[ "$atual" == "$esperada" ]] && return 0
  if [[ -n "$atual" ]]; then
    case "$esperada" in
      *noweb-arm-*) ;;
      *) return 0 ;;
    esac
    waha_so_amd64_conhecido "$atual" || return 0
  fi

  tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
  umask 077
  if grep -q '^WAHA_IMAGE=' "$ENV_FILE"; then
    awk -v imagem="$esperada" '/^WAHA_IMAGE=/ { print "WAHA_IMAGE=" imagem; next } { print }' \
      "$ENV_FILE" > "$tmp"
  else
    {
      cat "$ENV_FILE"
      printf '\n# Tag do WAHA por arquitetura; ver scripts/local-env.sh.\nWAHA_IMAGE=%s\n' "$esperada"
    } > "$tmp"
  fi
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  printf 'WAHA_IMAGE ajustada para a arquitetura desta máquina: %s\n' "$esperada"
}

ensure_vapid_keys() {
  local public_key private_key keys_json
  public_key="$(env_value VAPID_PUBLIC_KEY)"
  private_key="$(env_value VAPID_PRIVATE_KEY)"
  if [[ -n "$public_key" && -n "$private_key" ]]; then
    return
  fi
  keys_json="$(node -e 'const webpush = require("web-push"); process.stdout.write(JSON.stringify(webpush.generateVAPIDKeys()))')"
  public_key="$(printf '%s' "$keys_json" | node -e 'let s=""; process.stdin.on("data", c => s += c).on("end", () => process.stdout.write(JSON.parse(s).publicKey))')"
  private_key="$(printf '%s' "$keys_json" | node -e 'let s=""; process.stdin.on("data", c => s += c).on("end", () => process.stdout.write(JSON.parse(s).privateKey))')"
  printf '\n# Geradas automaticamente por local-env.sh; mantenha estas chaves para preservar as inscrições.\nVAPID_PUBLIC_KEY=%s\nVAPID_PRIVATE_KEY=%s\n' "$public_key" "$private_key" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  printf 'Chaves VAPID geradas automaticamente em %s\n' "$ENV_FILE"
}

has_local_env() {
  [[ "$(env_value DESKCOMM_ENV_MODE)" == "local" ]] || return 1
  local key
  for key in NEXT_PUBLIC_SUPABASE_URL NEXT_PUBLIC_SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY \
    SUPABASE_DB_URL INTERNAL_SECRET CPF_ENCRYPTION_KEY WAHA_BYO_ENCRYPTION_KEY AI_CRED_AES_KEY \
    WAHA_API_BASE_URL WAHA_API_KEY WAHA_WEBHOOK_BASE_URL UPSTASH_REDIS_REST_URL \
    UPSTASH_REDIS_REST_TOKEN WAHA_API_KEY_SHA512 SRH_TOKEN; do
    [[ -n "$(env_value "$key")" ]] || return 1
  done
}

local_ip() {
  hostname -I 2>/dev/null | awk '{print $1}' || true
}

choose_port() {
  local port="${APP_PORT:-3000}"
  if command -v ss >/dev/null 2>&1; then
    while ss -ltn | awk '{print $4}' | grep -Eq "(^|:)${port}$"; do
      port=$((port + 1))
    done
  fi
  printf '%s' "$port"
}

generate() {
  local status vm_ip app_port api_url app_url db_url anon_key service_role_key
  status="$(./scripts/local-supabase.sh status)"
  anon_key="$(printf '%s' "$status" | json_value ANON_KEY)"
  service_role_key="$(printf '%s' "$status" | json_value SERVICE_ROLE_KEY)"
  db_url="$(printf '%s' "$status" | json_value DB_URL)"
  [[ -n "$anon_key" && -n "$service_role_key" && -n "$db_url" ]] || {
    printf 'Erro: o Supabase local não retornou as credenciais necessárias.\n' >&2
    exit 1
  }

  vm_ip="$(local_ip)"
  [[ -n "$vm_ip" ]] || vm_ip="127.0.0.1"
  db_url="${db_url/127.0.0.1/$vm_ip}"
  app_port="$(choose_port)"
  api_url="http://${vm_ip}:54321"
  app_url="http://${vm_ip}:${app_port}"

  if [[ -f "$ENV_FILE" ]] && [[ "$(env_value DESKCOMM_ENV_MODE)" != "local" ]]; then
    local backup
    backup="${ENV_FILE}.cloud-backup"
    if [[ ! -e "$backup" ]]; then
      cp --preserve=mode "$ENV_FILE" "$backup"
      chmod 600 "$backup"
      printf 'Backup do ambiente anterior: %s\n' "$backup"
    fi
  fi

  # A chave do WAHA nasce ALEATÓRIA e é derivada UMA vez: o heredoc abaixo é
  # sem aspas, então dois `$(openssl rand)` produziriam valores diferentes na
  # chave e no hash, e o app tomaria 401. Sem knob: nenhum terceiro precisa
  # conhecê-la, e um `${WAHA_API_KEY:-...}` herdaria a chave da nuvem de quem
  # tiver a variável exportada no shell.
  local waha_key
  waha_key="$(openssl rand -hex 24)"

  local tmp
  tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
  umask 077
  cat > "$tmp" <<EOF
DESKCOMM_ENV_MODE=local
NODE_ENV=production
NEXT_PUBLIC_SUPABASE_URL=$api_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=$anon_key
SUPABASE_SERVICE_ROLE_KEY=$service_role_key
SUPABASE_DB_URL=$db_url
SUPABASE_DB_ADMIN_URL=$db_url

NEXT_PUBLIC_APP_URL=$app_url
NEXT_PUBLIC_ADMIN_URL=$app_url
WAHA_WEBHOOK_BASE_URL=$app_url

INTERNAL_SECRET=$(openssl rand -hex 32)
INTERNAL_CRON_SECRET=$(openssl rand -hex 32)
CPF_ENCRYPTION_KEY=$(openssl rand -base64 32)
WAHA_BYO_ENCRYPTION_KEY=$(openssl rand -base64 32)
AI_CRED_AES_KEY=$(openssl rand -base64 32)
NUVEMSHOP_OAUTH_ENCRYPTION_KEY=$(openssl rand -hex 32)

WAHA_API_BASE_URL=http://waha:3000
WAHA_IMAGE=$(imagem_waha_para_esta_maquina)
WAHA_API_KEY=$waha_key
WAHA_API_KEY_SHA512=$(printf '%s' "$waha_key" | sha512sum | awk '{print $1}')
WAHA_HMAC_SECRET=$(openssl rand -hex 32)
WAHA_WEBHOOK_REQUIRE_SIGNATURE=false
WHATSAPP_RESTART_ALL_SESSIONS=True

UPSTASH_REDIS_REST_URL=http://srh:80
UPSTASH_REDIS_REST_TOKEN=deskcomm-local-redis
SRH_TOKEN=deskcomm-local-redis
LGPD_SIGNING_KEY=$(openssl rand -hex 32)
APP_PORT=$app_port
SENTRY_DSN=
EOF
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  printf 'Ambiente local gerado em %s\n' "$ENV_FILE"
  printf 'Aplicação: %s\n' "$app_url"
}

case "${1:-ensure}" in
  ensure)
    if ! has_local_env; then generate; fi
    ensure_vapid_keys
    ensure_waha_image
    ;;
  generate|force)
    generate
    ;;
  *)
    printf 'Uso: %s {ensure|generate}\n' "$0"
    exit 2
    ;;
esac
