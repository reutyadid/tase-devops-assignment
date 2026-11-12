#!/usr/bin/env bash
# One-time Nexus setup (D-011, D-012). Safe to run again: every step checks first.
# It also validates the Jenkins values in .env, so mistakes show up before Jenkins starts.
#   0. Validate .env; stop unless NEXUS_ACCEPT_EULA=true (the EULA is the user's decision)
#   1. Wait until Nexus accepts writes
#   2. Replace the random initial admin password with NEXUS_ADMIN_PASSWORD
#   3. Accept the EULA in Nexus
#   4. Create/update a role that can only read and upload to maven-releases
#   5. Create/update the deploy user with only that role
# Usage (from 1-jenkins-pipeline/, after `docker compose up -d nexus`): ./nexus/setup.sh
set -euo pipefail

cd "$(dirname "$0")/.."            # 1-jenkins-pipeline/: where .env and docker-compose.yml are
NEXUS_URL="http://localhost:8081"
API="$NEXUS_URL/service/rest/v1"
ROLE_ID="maven-releases-deployer"
EULA_URL="https://links.sonatype.com/products/nxrm/ce-eula"

log() { echo "[setup] $*"; }
die() { echo "[setup] ERROR: $*" >&2; exit 1; }

# --- 0. Load and validate .env ---------------------------------------------------
[[ -f .env ]] || die ".env not found. Run: cp .env.example .env  (then edit it)"
set -a                             # export every variable defined in .env
# shellcheck source=/dev/null
source ./.env
set +a

for var in NEXUS_ACCEPT_EULA NEXUS_ADMIN_PASSWORD NEXUS_DEPLOY_USER NEXUS_DEPLOY_PASSWORD \
           JENKINS_ADMIN_PASSWORD GIT_REPO_URL JENKINS_AGENT_SSH_PUBKEY SMEE_URL GWT_TOKEN; do
  [[ -n "${!var:-}" ]] || die "$var is not set in .env"
done
# Passwords: letters, digits and . _ - only, at least 12 characters. Other characters
# ($, quotes, backslash, ...) are read differently by bash, Docker Compose, JSON and curl.
# Generate one with: openssl rand -hex 16
for var in NEXUS_ADMIN_PASSWORD NEXUS_DEPLOY_PASSWORD JENKINS_ADMIN_PASSWORD GWT_TOKEN; do
  [[ "${!var}" != "change-me" ]] || die "$var is still 'change-me' in .env"
  [[ "${!var}" =~ ^[a-zA-Z0-9._-]{12,}$ ]] \
    || die "$var must be at least 12 characters: letters, digits, . _ - only"
done
[[ "$NEXUS_DEPLOY_USER" =~ ^[a-zA-Z0-9._-]+$ ]] || die "NEXUS_DEPLOY_USER has invalid characters"
[[ "$GIT_REPO_URL" == https://* && "$GIT_REPO_URL" != *YOUR-USER* ]] \
  || die "GIT_REPO_URL must be the https URL of your GitHub repository"
[[ "$SMEE_URL" =~ ^https://smee\.io/[A-Za-z0-9]+$ && "$SMEE_URL" != *CHANGE-ME* ]] \
  || die "SMEE_URL must be your channel URL from https://smee.io"
[[ -r secrets/agent_key ]] || die "secrets/agent_key not found. See the SSH key steps in .env.example"

# The EULA is a legal agreement: never accept it on the user's behalf.
if [[ "$NEXUS_ACCEPT_EULA" != "true" ]]; then
  die "Nexus needs its EULA accepted before uploads work.
  Read $EULA_URL
  If you agree, set NEXUS_ACCEPT_EULA=true in .env and run this script again."
fi

# --- curl helper ----------------------------------------------------------------
# api USER PASSWORD METHOD PATH [CONTENT_TYPE]  (request body, if any, comes from stdin)
# Credentials go through a curl config file (-K), not the command line,
# so they never show up in `ps`. Prints the HTTP status code; the body goes to $BODY.
BODY="$(mktemp)"
trap 'rm -f "$BODY"' EXIT

api() {
  local user="$1" pass="$2" method="$3" path="$4" type="${5:-}"
  local args=(-sS -o "$BODY" -w '%{http_code}' -X "$method")
  if [[ -n "$type" ]]; then
    args+=(-H "Content-Type: $type" --data-binary @-)
  fi
  # <(...) must be on the curl line itself: its file is closed once the command that created it ends.
  curl "${args[@]}" -K <(printf 'user = "%s:%s"\n' "$user" "$pass") "$API$path"
}

expect() {   # expect EXPECTED_CODES ACTUAL_CODE WHAT
  [[ " $1 " == *" $2 "* ]] || die "$3 failed: HTTP $2 $(cat "$BODY")"
}

# --- 1. Wait until Nexus accepts writes (first start takes ~4 minutes) --------------
log "Waiting for Nexus at $NEXUS_URL ..."
tries=0
until curl -sf -o /dev/null "$API/status/writable"; do
  tries=$((tries + 1))
  (( tries < 60 )) || die "Nexus is not ready after 10 minutes. Check: docker compose logs nexus"
  sleep 10
done
log "Nexus is ready."

# --- 2. Admin password ------------------------------------------------------------
# If the password from .env already works, it was changed on an earlier run.
if [[ "$(api admin "$NEXUS_ADMIN_PASSWORD" GET /status/check)" == "200" ]]; then
  log "Admin password already set."
else
  # Nexus writes a random initial password to this file and deletes it once changed.
  initial="$(docker compose exec -T nexus cat /nexus-data/admin.password 2>/dev/null)" \
    || die "Admin login failed and no initial password file exists.
  NEXUS_ADMIN_PASSWORD in .env does not match the current admin password."
  code="$(printf '%s' "$NEXUS_ADMIN_PASSWORD" \
    | api admin "$initial" PUT /security/users/admin/change-password text/plain)"
  expect 204 "$code" "Changing the admin password"
  log "Admin password changed."
fi
ADMIN=(admin "$NEXUS_ADMIN_PASSWORD")

# --- 3. EULA ----------------------------------------------------------------------
code="$(api "${ADMIN[@]}" GET /system/eula)"; expect 200 "$code" "Reading EULA status"
if grep -Eq '"accepted" *: *true' "$BODY"; then
  log "EULA already accepted."
else
  # Send back the same object Nexus returned, with accepted switched to true.
  eula="$(sed -E 's/"accepted" *: *false/"accepted": true/' "$BODY")"
  code="$(printf '%s' "$eula" | api "${ADMIN[@]}" POST /system/eula application/json)"
  expect "200 204" "$code" "Accepting EULA"
  # Check the result instead of trusting the HTTP code.
  code="$(api "${ADMIN[@]}" GET /system/eula)"; expect 200 "$code" "Reading EULA status"
  grep -Eq '"accepted" *: *true' "$BODY" || die "EULA is still not accepted: $(cat "$BODY")"
  log "EULA accepted (NEXUS_ACCEPT_EULA=true)."
fi

# --- 4. Role: read + upload to maven-releases only ------------------------------------
# Minimal set, verified in C4: without "edit" even the first upload gets 403 (T-004, D-011).
role_json='{
  "id": "'"$ROLE_ID"'",
  "name": "'"$ROLE_ID"'",
  "description": "Read and upload to maven-releases only (used by Jenkins)",
  "privileges": [
    "nx-repository-view-maven2-maven-releases-read",
    "nx-repository-view-maven2-maven-releases-add",
    "nx-repository-view-maven2-maven-releases-edit"
  ],
  "roles": []
}'
if [[ "$(api "${ADMIN[@]}" GET "/security/roles/$ROLE_ID")" == "200" ]]; then
  code="$(printf '%s' "$role_json" | api "${ADMIN[@]}" PUT "/security/roles/$ROLE_ID" application/json)"
  expect "200 204" "$code" "Updating role"; log "Role $ROLE_ID updated."
else
  code="$(printf '%s' "$role_json" | api "${ADMIN[@]}" POST /security/roles application/json)"
  expect 200 "$code" "Creating role"; log "Role $ROLE_ID created."
fi

# --- 5. Deploy user -----------------------------------------------------------------
user_fields='"userId": "'"$NEXUS_DEPLOY_USER"'",
  "firstName": "Jenkins", "lastName": "Deploy",
  "emailAddress": "jenkins-deploy@example.invalid",
  "status": "active", "roles": ["'"$ROLE_ID"'"]'

code="$(api "${ADMIN[@]}" GET "/security/users?userId=$NEXUS_DEPLOY_USER")"
expect 200 "$code" "Looking up deploy user"
if grep -qF "\"userId\" : \"$NEXUS_DEPLOY_USER\"" "$BODY"; then   # -F: exact text, "." is not a wildcard
  code="$(printf '{%s, "source": "default"}' "$user_fields" \
    | api "${ADMIN[@]}" PUT "/security/users/$NEXUS_DEPLOY_USER" application/json)"
  expect 204 "$code" "Updating deploy user"
  # Keep the password in sync with .env.
  code="$(printf '%s' "$NEXUS_DEPLOY_PASSWORD" \
    | api "${ADMIN[@]}" PUT "/security/users/$NEXUS_DEPLOY_USER/change-password" text/plain)"
  expect 204 "$code" "Updating deploy user password"
  log "User $NEXUS_DEPLOY_USER updated."
else
  code="$(printf '{%s, "password": "%s"}' "$user_fields" "$NEXUS_DEPLOY_PASSWORD" \
    | api "${ADMIN[@]}" POST /security/users application/json)"
  expect 200 "$code" "Creating deploy user"
  log "User $NEXUS_DEPLOY_USER created."
fi

log "Done."
