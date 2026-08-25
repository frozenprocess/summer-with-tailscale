#!/usr/bin/env bash
#
# end-to-end.sh — chains modules 01-03 together, driven entirely by the
# Tailscale API. This script doesn't introduce new concepts; it's the four
# modules run back to back. If a step below is unclear, the referenced
# readme walks through that exact API call by hand:
#
#   1. Provision two isolated tailnets            -> ../01-tailnet-sandboxes/readme.md
#   2. Bring up a tsnet app inside each one        -> ../02-tailnet-membership/readme.md
#   3. Declaratively share the two tailnets        -> ../03-declarative-sharing/readme.md
#   4. (this file) wire it together via the API    -> ./readme.md
#
# Usage:
#   export CLIENT_ID=<org-level OAuth client id>       # or put them in ../.env
#   export CLIENT_SECRET=<org-level OAuth client secret>
#   ./end-to-end.sh up       # provision, deploy, and share (needs CLIENT_ID/CLIENT_SECRET)
#   ./end-to-end.sh status   # show what's running
#   ./end-to-end.sh down     # tear everything back down (uses the per-tailnet
#                             # credentials saved under .state/, not CLIENT_ID/CLIENT_SECRET)
#
# Requires: curl, jq, docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$SCRIPT_DIR/.state"
APP_IMAGE="ts-demo-app"
DOMAIN="https://api.tailscale.com"

# Two isolated tailnets get created and torn down by this script.
LABELS=(a b)

log()  { printf '\033[1;34m[e2e]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[e2e]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[e2e]\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

load_env() {
  [[ -f "$ROOT_DIR/.env" ]] && { set -a; source "$ROOT_DIR/.env"; set +a; }
}

require_env() {
  load_env
  [[ -n "${CLIENT_ID:-}" && -n "${CLIENT_SECRET:-}" ]] \
    || die "CLIENT_ID/CLIENT_SECRET not set (export them, or fill in $ROOT_DIR/.env — see .env.example)"
}

# --- Step 0: org-level access token -----------------------------------
# Same exchange as ../01-tailnet-sandboxes/readme.md. This token is only
# used to create/delete the two sandbox tailnets below; every other call
# uses the scoped token handed back for that specific tailnet.
org_access_token() {
  curl -sS -X POST "$DOMAIN/api/v2/oauth/token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    | jq -r '.access_token'
}

# --- Step 1: provision two isolated tailnets ---------------------------
# See ../01-tailnet-sandboxes/readme.md for the same call explained line
# by line, including why the response must be saved immediately.
create_tailnet() {
  local label="$1" token="$2"
  curl -sS "$DOMAIN/api/v2/organizations/-/tailnets" \
    --request POST \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $token" \
    --data "{\"displayName\": \"e2e-sandbox-$label\"}"
}

tailnet_access_token() {
  local client_id="$1" client_secret="$2"
  curl -sS -X POST "$DOMAIN/api/v2/oauth/token" \
    -d "client_id=$client_id" \
    -d "client_secret=$client_secret" \
    | jq -r '.access_token'
}

# --- Step 1.5: turn on HTTPS certs for the new tailnet ------------------
# A fresh tailnet has HTTPS certificates off by default, and ../02-tailnet-
# membership/main.go calls srv.ListenTLS — without this, that call fails
# at runtime with "you must enable HTTPS in the admin panel to proceed".
# There's no dedicated toggle endpoint in the public API docs, but the
# tailnet settings resource accepts a PATCH for it.
enable_https() {
  local token="$1"
  curl -sS "$DOMAIN/api/v2/tailnet/-/settings" \
    --request PATCH \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $token" \
    --data '{"httpsEnabled": true}' --fail-with-body -o /dev/null
}

# --- Step 2: tag the policy file + declaratively share -----------------
# Split into two calls on purpose: tagOwners is plain ACL housekeeping
# needed before we can issue a tagged auth key below, and must succeed.
# externalTailnets/grants is the declarative sharing pattern from
# ../03-declarative-sharing/readme.md, which is still waitlist-gated — if
# your account isn't enrolled, the Tailscale API rejects that whole POST
# (as one atomic policy update) with "external tailnet not allowed in
# local policy grants". Keeping it in a separate call means that failure
# can't also take the tag declaration down with it.
get_policy() {
  local token="$1"
  # The ACL endpoint returns HuJSON (JSON with comments) by default, which
  # jq can't parse — ask for plain JSON instead.
  curl -sS "$DOMAIN/api/v2/tailnet/-/acl" \
    --header "Authorization: Bearer $token" \
    --header 'Accept: application/json'
}

put_policy() {
  local token="$1" policy="$2"
  curl -sS "$DOMAIN/api/v2/tailnet/-/acl" \
    --request POST \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $token" \
    --data "$policy" --fail-with-body -o /dev/null
}

patch_policy_tag() {
  local token="$1" new
  new=$(jq '.tagOwners["tag:tsnet-app"] = (.tagOwners["tag:tsnet-app"] // ["autogroup:admin"])' \
    <<<"$(get_policy "$token")")
  put_policy "$token" "$new"
}

patch_policy_sharing() {
  local token="$1" other_id="$2" other_label="$3"
  local new
  new=$(jq \
    --arg tag "tag:tsnet-app" \
    --arg name "sandbox-$other_label" \
    --arg id "$other_id" \
    '.externalTailnets[$name] = {"externalID": $id, "allowExternalReferencesTo": [$tag]}
     | .grants = ((.grants // []) + [{"src": ["group://\($name)/all"], "dst": [$tag], "ip": ["*"]}])' \
    <<<"$(get_policy "$token")")

  put_policy "$token" "$new" \
    && log "policy updated for sandbox-$other_label sharing" \
    || warn "policy update failed (likely not on the Declarative Sharing waitlist) — continuing without cross-tailnet sharing"
}

# --- Step 3: issue a scoped auth key ------------------------------------
# See ../04-api-is-the-way/readme.md, "Issuing auth keys instead of
# copy-pasting them" for what each field below does.
issue_auth_key() {
  local token="$1"
  curl -sS "$DOMAIN/api/v2/tailnet/-/keys" \
    --request POST \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $token" \
    --data '{
      "capabilities": {
        "devices": {
          "create": {
            "reusable": false,
            "ephemeral": true,
            "preauthorized": true,
            "tags": ["tag:tsnet-app"]
          }
        }
      },
      "expirySeconds": 3600
    }' | jq -r '.key'
}

# --- Step 4: deploy the tsnet app ---------------------------------------
# This is exactly ../02-tailnet-membership/main.go, built from its
# dockerfile, given an auth key instead of a dashboard-issued one. It
# serves "Hello from tsnet" directly over HTTPS on the tailnet — no
# backend to stand up.
deploy_app() {
  local label="$1" authkey="$2"

  docker run -d --name "ts-demo-app-$label" \
    -e "TS_HOSTNAME=sandbox-$label-app" \
    -e "TS_AUTHKEY=$authkey" \
    "$APP_IMAGE" >/dev/null
}

cmd_up() {
  require_env
  require_cmd curl; require_cmd jq; require_cmd docker
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"

  log "requesting org access token"
  local org_token; org_token=$(org_access_token)
  [[ "$org_token" != "null" && -n "$org_token" ]] || die "failed to get org access token — check CLIENT_ID/CLIENT_SECRET"

  log "building tsnet app image from ../02-tailnet-membership"
  docker build -q -f "$ROOT_DIR/02-tailnet-membership/dockerfile" -t "$APP_IMAGE" "$ROOT_DIR/02-tailnet-membership" >/dev/null

  for label in "${LABELS[@]}"; do
    local f="$STATE_DIR/tailnet-$label.json"

    # There is a secret let's reuse it
    if [[ -f "$f" ]] && jq -e '.oauthClient.secret' "$f" >/dev/null 2>&1; then
      log "reusing existing tailnet state for e2e-sandbox-$label"
      continue
    fi

    # Don't write down keys if its an error
    log "creating tailnet e2e-sandbox-$label"
    create_tailnet "$label" "$org_token" > "$f.tmp"
    if jq -e '.oauthClient.secret' "$f.tmp" >/dev/null 2>&1; then
      mv "$f.tmp" "$f"
      chmod 600 "$f"
    else
      local msg; msg=$(jq -r '.message // .' "$f.tmp" 2>/dev/null) || msg=$(cat "$f.tmp")
      rm -f "$f.tmp"
      die "tailnet creation failed for e2e-sandbox-$label: $msg"
    fi
  done

  for label in "${LABELS[@]}"; do
    local other; other=$([[ "$label" == "a" ]] && echo b || echo a)
    local cid csecret token authkey

    cid=$(jq -r '.oauthClient.id' "$STATE_DIR/tailnet-$label.json")
    csecret=$(jq -r '.oauthClient.secret' "$STATE_DIR/tailnet-$label.json")
    token=$(tailnet_access_token "$cid" "$csecret")

    log "enabling HTTPS certs for sandbox-$label"
    enable_https "$token" || die "failed to enable HTTPS certs for sandbox-$label"

    log "declaring tag:tsnet-app for sandbox-$label"
    patch_policy_tag "$token" || die "failed to update policy tags for sandbox-$label"

    other_id=$(jq -r '.id' "$STATE_DIR/tailnet-$other.json")
    log "updating policy for sandbox-$label -> sandbox-$other sharing"
    patch_policy_sharing "$token" "$other_id" "$other"

    log "issuing tsnet auth key for sandbox-$label"
    authkey=$(issue_auth_key "$token")
    [[ -n "$authkey" && "$authkey" != "null" ]] || die "failed to issue auth key for sandbox-$label"

    log "deploying app for sandbox-$label"
    deploy_app "$label" "$authkey"
  done

  log "done. run '$0 status' to see the two apps."
}

cmd_status() {
  [[ -d "$STATE_DIR" ]] || die "nothing is up (no $STATE_DIR) — run '$0 up' first"
  for label in "${LABELS[@]}"; do
    local f="$STATE_DIR/tailnet-$label.json"
    [[ -f "$f" ]] || continue
    local dns; dns=$(jq -r '.dnsName' "$f")
    echo "sandbox-$label:  https://sandbox-$label-app.$dns"
  done
  echo
  docker ps --filter "name=ts-demo-" --format 'table {{.Names}}\t{{.Status}}'
}

cmd_down() {
  require_cmd curl; require_cmd jq; require_cmd docker

  # Docker resources never need a Tailscale credential to remove, so this
  # always runs even if CLIENT_ID/CLIENT_SECRET are missing or rotated.
  for label in "${LABELS[@]}"; do
    docker rm -f "ts-demo-app-$label" >/dev/null 2>&1 || true
  done
  docker rmi "$APP_IMAGE" >/dev/null 2>&1 || true
  log "docker resources removed"

  if [[ -d "$STATE_DIR" ]]; then
    # Deletion requires a token scoped to the specific tailnet being
    # deleted — the org-level CLIENT_ID/CLIENT_SECRET can't do it, only
    # the oauthClient credentials returned when that tailnet was created
    # can. See ../01-tailnet-sandboxes/readme.md, "Delete a Tailnet".
    # That means `down` doesn't need CLIENT_ID/CLIENT_SECRET at all —
    # everything it needs is already sitting in $STATE_DIR.
    local all_deleted=true
    for label in "${LABELS[@]}"; do
      local f="$STATE_DIR/tailnet-$label.json"
      [[ -f "$f" ]] || continue

      local id cid csecret token
      id=$(jq -r '.id' "$f")
      cid=$(jq -r '.oauthClient.id' "$f")
      csecret=$(jq -r '.oauthClient.secret' "$f")
      token=$(tailnet_access_token "$cid" "$csecret")
      if [[ "$token" == "null" || -z "$token" ]]; then
        warn "could not get an access token for tailnet $id (sandbox-$label) — leaving it in $STATE_DIR"
        all_deleted=false
        continue
      fi

      log "deleting tailnet $id (sandbox-$label)"
      curl -sS "$DOMAIN/api/v2/tailnet/$id" \
        --request DELETE \
        --header "Authorization: Bearer $token" -o /dev/null \
        || { warn "could not delete tailnet $id — check the console"; all_deleted=false; }
    done
    # Only wipe the state (and the credentials it holds) once every
    # tailnet it references is confirmed gone.
    [[ "$all_deleted" == true ]] && rm -rf "$STATE_DIR"
  fi
  log "done."
}

case "${1:-}" in
  up)     cmd_up ;;
  status) cmd_status ;;
  down)   cmd_down ;;
  *) die "usage: $0 {up|status|down}" ;;
esac
