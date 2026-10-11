# Keycloak + Spring Boot Authentication & Authorization Demo

A small, GitHub-ready example showing the complete flow:

`User -> Keycloak -> JWT access token -> Spring Boot Resource Server -> Authentication -> Role-based Authorization`

Nothing is imported into Keycloak at startup. Keycloak boots empty, and the realm, client, roles and users are created by a provisioning script against the running instance, the same way you would set up a real Keycloak environment.

## Stack

- Java 21
- Spring Boot 3.5.16
- Spring Security OAuth2 Resource Server
- Keycloak 26.7.4 (dev mode, via Docker Compose)
- Keycloak Admin CLI (`kcadm.sh`) for provisioning
- Maven

## Project structure

```text
keycloak-spring-boot-auth-demo/
├── scripts/
│   ├── provision-users.sh      # macOS / Linux / Git Bash / WSL
│   └── provision-users.ps1     # Windows PowerShell
├── src/main/java/com/example/keycloak/
│   ├── KeycloakSpringBootAuthDemoApplication.java
│   ├── SecurityConfig.java     # JWT validation + Keycloak role mapping
│   └── SecureController.java   # Endpoints protected with @PreAuthorize
├── src/main/resources/application.yml
├── docs/
│   ├── dynamic-authorization.md
│   └── presentation-notes.md   # Slide-by-slide content for a PPT
├── docker-compose.yml
├── pom.xml
└── README.md
```

## 1. Start Keycloak

From the project root:

```bash
docker compose up -d
```

Keycloak will be available at:

- Admin Console: http://localhost:8080/admin (bootstrap admin: `admin` / `admin`)

At this point Keycloak only has the `master` realm. The `demo` realm does not exist yet.

## 2. Provision the realm, client, roles and users

```bash
# macOS / Linux / Git Bash / WSL
./scripts/provision-users.sh

# Windows (PowerShell)
.\scripts\provision-users.ps1
```

If PowerShell blocks the script, run it with `powershell -ExecutionPolicy Bypass -File .\scripts\provision-users.ps1`.

Both scripts do exactly the same thing. They run `kcadm.sh` inside the `keycloak-demo` container and:

| Step | What is created | kcadm command |
|---|---|---|
| 1 | Logs in as the bootstrap admin (waits until Keycloak is ready) | `config credentials` |
| 2 | Realm `demo` | `create realms` |
| 3 | Realm roles `USER` and `ADMIN` | `create roles` |
| 4 | Public client `spring-boot-api` with Direct Access Grants enabled | `create clients` |
| 5 | Users `ajay` and `admin` | `create users` |
| 6 | Passwords for each user | `set-password` |
| 7 | Role mappings | `add-roles` |

The scripts are idempotent: anything that already exists is skipped, so running them twice is safe. Passwords and role mappings are always re-applied.

The first run takes about a minute while Keycloak finishes starting. In PowerShell you will see a few `Connection refused` lines during that wait; that is expected.

### Demo users

| Username | Password | Realm roles |
|---|---|---|
| ajay | ajay123 | USER |
| admin | admin123 | USER, ADMIN |

The `admin` user here is an application admin inside the `demo` realm. It is not the Keycloak bootstrap admin in the `master` realm.

These credentials are for local development only. Do not use them outside the demo environment.

To use your own usernames, passwords or emails, edit the variables at the top of `scripts/provision-users.sh` (`APP_USER`, `APP_USER_PASSWORD`, `APP_ADMIN`, ...) or `scripts/provision-users.ps1` (`$AppUser`, `$AppUserPassword`, `$AppAdmin`, ...). The Keycloak connection settings (`CONTAINER`, `ADMIN_USER`, `ADMIN_PASSWORD`, `REALM`, `CLIENT_ID`) are defined in the same place.

### Client settings

| Setting | Value | Why |
|---|---|---|
| `clientId` | `spring-boot-api` | Matches the client roles lookup in `SecurityConfig` |
| `publicClient` | `true` | No client secret needed for the demo |
| `directAccessGrantsEnabled` | `true` | Allows the password grant from curl/Postman |
| `standardFlowEnabled` | `false` | No browser login flow in this demo |
| `fullScopeAllowed` | `true` | Realm roles are included in the access token |

### Doing the same with the Admin REST API (OPTIONAL)

`kcadm.sh` is a wrapper around Keycloak's Admin REST API. A provisioning service or CI job would call the API directly instead of shelling into the container:

```bash
# 1. Get an admin access token from the master realm
ADMIN_TOKEN=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli" -d "grant_type=password" \
  -d "username=admin" -d "password=admin" | jq -r .access_token)

# 2. Create a user in the demo realm
curl -X POST "http://localhost:8080/admin/realms/demo/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "username": "ajay",
        "enabled": true,
        "email": "ajay@example.com",
        "credentials": [{"type": "password", "value": "ajay123", "temporary": false}]
      }'
```

## 3. Start Spring Boot

Requirements: Java 21 and Maven.

```bash
mvn spring-boot:run
```

The API runs on `http://localhost:8081` and validates tokens issued by `http://localhost:8080/realms/demo` (see `application.yml`). Start it after the realm has been provisioned.

## 4. Test the public endpoint

```bash
curl http://localhost:8081/api/public
```

Expected:

```json
{"message":"Public endpoint - no token required"}
```

Calling a protected endpoint without a token returns `401 Unauthorized`:

```bash
curl -i http://localhost:8081/api/me
```

## 5. Get a token for Ajay

For this learning demo the client has Direct Access Grants enabled so the password grant can be exercised from curl/Postman.

```bash
curl -X POST "http://localhost:8080/realms/demo/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=spring-boot-api" \
  -d "grant_type=password" \
  -d "username=ajay" \
  -d "password=ajay123"
```

Copy `access_token` from the response. Access tokens expire after 5 minutes by default, so request a new one if you get a `401`.

> Note: password grant is used here only to make the local learning flow easy to demonstrate. For real user-facing applications, use the appropriate OpenID Connect authorization flow rather than building a production design around password grant.

## 6. Authentication and authorization as Ajay

```bash
curl http://localhost:8081/api/me \
  -H "Authorization: Bearer <AJAY_ACCESS_TOKEN>"
```

Expected (Keycloak also adds its default roles):

```json
{"authorities":["ROLE_offline_access","ROLE_uma_authorization","ROLE_default-roles-demo","ROLE_USER"],"username":"ajay"}
```

Ajay can list accounts:

```bash
curl http://localhost:8081/api/accounts \
  -H "Authorization: Bearer <AJAY_ACCESS_TOKEN>"
```

But Ajay cannot create an account:

```bash
curl -i -X POST http://localhost:8081/api/accounts \
  -H "Authorization: Bearer <AJAY_ACCESS_TOKEN>"
```

Expected: `403 Forbidden`.

## 7. Get an admin token

```bash
curl -X POST "http://localhost:8080/realms/demo/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=spring-boot-api" \
  -d "grant_type=password" \
  -d "username=admin" \
  -d "password=admin123"
```

Then:

```bash
curl -X POST http://localhost:8081/api/accounts \
  -H "Authorization: Bearer <ADMIN_ACCESS_TOKEN>"
```

Expected:

```json
{"message":"ADMIN can create accounts"}
```

```bash
curl -X DELETE http://localhost:8081/api/accounts/42 \
  -H "Authorization: Bearer <ADMIN_ACCESS_TOKEN>"
```

Expected:

```json
{"id":"42","message":"ADMIN can delete account"}
```

## What is happening?

### Authentication

1. The user authenticates with Keycloak.
2. Keycloak issues a signed JWT access token.
3. The client sends the token to Spring Boot in the `Authorization: Bearer ...` header.
4. Spring Security validates the JWT using the issuer metadata/JWKs exposed by Keycloak.
5. A valid token establishes the authenticated principal (`preferred_username`).

### Authorization

Keycloak puts realm roles in the JWT under:

```json
"realm_access": {
  "roles": ["USER", "ADMIN"]
}
```

Spring Security does not automatically turn Keycloak's `realm_access.roles` into `ROLE_*` authorities. `SecurityConfig` contains a custom JWT converter that reads realm roles and `spring-boot-api` client roles (`resource_access.spring-boot-api.roles`) and maps:

```text
USER  -> ROLE_USER
ADMIN -> ROLE_ADMIN
```

Then method security handles authorization:

```java
@PreAuthorize("hasAnyRole('USER', 'ADMIN')")
```

and:

```java
@PreAuthorize("hasRole('ADMIN')")
```

## Endpoint matrix

| Endpoint | Authentication | Required role | ajay | admin |
|---|---|---|---|---|
| `GET /api/public` | No | None | 200 | 200 |
| `GET /api/me` | Yes | Any authenticated user | 200 | 200 |
| `GET /api/accounts` | Yes | USER or ADMIN | 200 | 200 |
| `POST /api/accounts` | Yes | ADMIN | 403 | 200 |
| `DELETE /api/accounts/{id}` | Yes | ADMIN | 403 | 200 |

Any protected endpoint called without a token returns `401`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Script keeps printing `Connection refused` | Keycloak is still starting. Wait; the script retries every 2 seconds. |
| `No such container: keycloak-demo` | Run `docker compose up -d` first. |
| `401` with a token you just copied | Token expired (5 minutes) or Spring Boot was started before the realm existed. Get a new token / restart the app. |
| Login fails with `invalid_grant` | Wrong password, or the realm was never provisioned. Re-run the script. |
| Old users (from a previous realm import) show up | An old `keycloak-demo` container is being reused. `docker rm -f keycloak-demo`, then start again. |

## Cleanup

```bash
docker compose down
```

Keycloak runs in dev mode with its embedded database inside the container, so removing the container removes the realm and users. Run the provisioning script again after the next `docker compose up -d`.

## Important learning point

Do not put username/password validation or JWT signature validation in your Spring Boot controller. That is exactly the type of IAM responsibility Keycloak is intended to centralize.

The Spring Boot application acts as an OAuth2 Resource Server. It trusts tokens issued by the configured Keycloak realm and makes authorization decisions from the resulting authorities.
