#!/usr/bin/env bash
# =============================================================================
# create-chatwoot-account.sh
# Creates a Chatwoot Account (tenant) and a default API Inbox via Super Admin API.
# Usage: ./create-chatwoot-account.sh [ACCOUNT_NAME] [ADMIN_EMAIL] [ADMIN_PASSWORD]
# Requires: curl, jq
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override via env or positional args
# ---------------------------------------------------------------------------
CHATWOOT_URL="${CHATWOOT_URL:-http://localhost:3000}"
ACCOUNT_NAME="${1:-TurboTrack Test Account}"
ADMIN_EMAIL="${2:-${CHATWOOT_ADMIN_EMAIL:-admin@turbotrack.local}}"
ADMIN_PASSWORD="${3:-${CHATWOOT_ADMIN_PASSWORD:-changeme123}}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 not found" >&2; exit 1; }; }
require curl
require jq

log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Step 1 — Wait for Chatwoot to be healthy
# ---------------------------------------------------------------------------
log "Waiting for Chatwoot at $CHATWOOT_URL ..."
for i in $(seq 1 30); do
  status=$(curl -s -o /dev/null -w "%{http_code}" "$CHATWOOT_URL/auth/sign_in" || true)
  if [ "$status" = "200" ] || [ "$status" = "401" ]; then
    log "Chatwoot is up (HTTP $status)"
    break
  fi
  [ "$i" -eq 30 ] && fail "Chatwoot did not respond after 30 attempts"
  log "Attempt $i/30 — HTTP $status — retrying in 5s..."
  sleep 5
done

# ---------------------------------------------------------------------------
# Step 2 — Sign in as super admin to get auth token
# ---------------------------------------------------------------------------
log "Signing in as $ADMIN_EMAIL ..."
auth_response=$(curl -s -X POST "$CHATWOOT_URL/auth/sign_in" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")

access_token=$(echo "$auth_response" | jq -r '.data.access_token // empty')
[ -z "$access_token" ] && fail "Could not get access token. Response: $auth_response"
log "Auth token obtained."

# ---------------------------------------------------------------------------
# Step 3 — Create Account via Super Admin API
# ---------------------------------------------------------------------------
log "Creating account: '$ACCOUNT_NAME' ..."
account_response=$(curl -s -X POST "$CHATWOOT_URL/super_admin/api/v1/accounts" \
  -H "Content-Type: application/json" \
  -H "api_access_token: $access_token" \
  -d "{\"account\":{\"name\":\"$ACCOUNT_NAME\"}}")

account_id=$(echo "$account_response" | jq -r '.id // empty')
[ -z "$account_id" ] && fail "Could not create account. Response: $account_response"
log "Account created — ID: $account_id"

# ---------------------------------------------------------------------------
# Step 4 — Create API Inbox in the new Account
# ---------------------------------------------------------------------------
log "Creating API Inbox in account $account_id ..."
inbox_response=$(curl -s -X POST "$CHATWOOT_URL/api/v1/accounts/$account_id/inboxes" \
  -H "Content-Type: application/json" \
  -H "api_access_token: $access_token" \
  -d '{
    "name": "Evolution WhatsApp",
    "channel": {
      "type": "api",
      "webhook_url": ""
    }
  }')

inbox_id=$(echo "$inbox_response" | jq -r '.id // empty')
inbox_token=$(echo "$inbox_response" | jq -r '.channel_identifier // empty')
[ -z "$inbox_id" ] && fail "Could not create inbox. Response: $inbox_response"
log "Inbox created — ID: $inbox_id | Channel token: $inbox_token"

# ---------------------------------------------------------------------------
# Step 5 — Print summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Chatwoot Account Created Successfully"
echo "============================================================"
echo "  Account Name : $ACCOUNT_NAME"
echo "  Account ID   : $account_id"
echo "  Inbox Name   : Evolution WhatsApp"
echo "  Inbox ID     : $inbox_id"
echo "  Inbox Token  : $inbox_token"
echo "  Admin Email  : $ADMIN_EMAIL"
echo "  Chatwoot URL : $CHATWOOT_URL"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Store Account ID ($account_id) and Inbox Token in your tenant config"
echo "  2. Configure Evolution API webhook → $CHATWOOT_URL/api/v1/accounts/$account_id/..."
echo "  3. Run EMP-55 (Semana 2) to wire Evolution API to this inbox"
echo ""
