#!/usr/bin/env bash
# Provisions the demo realm, client, roles and users using Keycloak's
# Admin CLI (kcadm.sh), the way you would against a real Keycloak
# instance that has no pre-built realm export to import.
#
# Safe to re-run: anything that already exists is skipped.
#
# For macOS and Linux (or Windows via Git Bash / WSL). Windows users on
# native PowerShell should use scripts/provision-users.ps1 instead.
#
# Usage:
#   docker compose up -d
#   ./scripts/provision-users.sh
set -euo pipefail

# Git Bash on Windows rewrites "/opt/..." arguments into Windows paths
# before they reach docker; disable that conversion.
export MSYS_NO_PATHCONV=1

CONTAINER="keycloak-demo"
KCADM="/opt/keycloak/bin/kcadm.sh"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin"
REALM="demo"
CLIENT_ID="spring-boot-api"

# Demo users. Change these to provision your own users.
APP_USER="ajay"
APP_USER_PASSWORD="ajay123"
APP_USER_EMAIL="ajay@example.com"
APP_USER_FIRST_NAME="Ajay"
APP_USER_LAST_NAME="User"

# Application admin inside the demo realm, not the Keycloak bootstrap admin.
APP_ADMIN="admin"
APP_ADMIN_PASSWORD="admin123"
APP_ADMIN_EMAIL="admin@example.com"
APP_ADMIN_FIRST_NAME="Admin"
APP_ADMIN_LAST_NAME="User"

kcadm() {
  docker exec "$CONTAINER" "$KCADM" "$@"
}

# Returns 0 if the kcadm "get" query returns a non-empty JSON array/object.
exists() {
  local out
  out=$(kcadm get "$@" 2>/dev/null) || return 1
  [[ -n "$out" && "$out" != "[ ]" && "$out" != "[]" ]]
}

create_user() {
  local username=$1 email=$2 first=$3 last=$4 password=$5
  shift 5
  if exists users -r "$REALM" -q "username=$username" -q exact=true; then
    echo "User '$username' already exists, skipping create."
  else
    echo "Creating user '$username'..."
    kcadm create users -r "$REALM" -s username="$username" -s enabled=true \
      -s email="$email" -s emailVerified=true -s firstName="$first" -s lastName="$last"
  fi
  kcadm set-password -r "$REALM" --username "$username" --new-password "$password"
  for role in "$@"; do
    echo "  Assigning realm role $role to '$username'"
    kcadm add-roles -r "$REALM" --uusername "$username" --rolename "$role"
  done
}

echo "Waiting for Keycloak to accept admin CLI logins..."
until kcadm config credentials --server http://localhost:8080 --realm master \
  --user "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null 2>&1; do
  sleep 2
done

if exists "realms/$REALM"; then
  echo "Realm '$REALM' already exists, skipping create."
else
  echo "Creating realm '$REALM'..."
  kcadm create realms -s realm="$REALM" -s enabled=true \
    -s displayName="Keycloak Spring Boot Demo"
fi

for role in USER ADMIN; do
  if exists "roles/$role" -r "$REALM"; then
    echo "Realm role $role already exists, skipping create."
  else
    echo "Creating realm role $role..."
    if [[ "$role" == "USER" ]]; then desc="Regular application user"; else desc="Application administrator"; fi
    kcadm create roles -r "$REALM" -s name="$role" -s description="$desc"
  fi
done

if exists clients -r "$REALM" -q clientId="$CLIENT_ID"; then
  echo "Client '$CLIENT_ID' already exists, skipping create."
else
  echo "Creating client '$CLIENT_ID'..."
  kcadm create clients -r "$REALM" \
    -s clientId="$CLIENT_ID" \
    -s name="Spring Boot API" \
    -s enabled=true \
    -s publicClient=true \
    -s protocol=openid-connect \
    -s directAccessGrantsEnabled=true \
    -s standardFlowEnabled=false \
    -s serviceAccountsEnabled=false \
    -s fullScopeAllowed=true
fi

create_user "$APP_USER" "$APP_USER_EMAIL" "$APP_USER_FIRST_NAME" "$APP_USER_LAST_NAME" "$APP_USER_PASSWORD" USER
create_user "$APP_ADMIN" "$APP_ADMIN_EMAIL" "$APP_ADMIN_FIRST_NAME" "$APP_ADMIN_LAST_NAME" "$APP_ADMIN_PASSWORD" USER ADMIN

echo "Done. Realm '$REALM' is provisioned with client '$CLIENT_ID' and users $APP_USER/$APP_ADMIN."
