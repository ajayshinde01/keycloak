## Run Keycloak with persistent storage (PostgreSQL)

`docker run … start-dev` keeps everything in a built-in dev database **inside the container**.
Remove or recreate the container and the `bank-demo` realm, its clients, users, roles and groups are gone.

This folder's `docker-compose.yml` runs Keycloak against **PostgreSQL**, so everything you
configure is stored in real database tables on a Docker volume.

### Start

```bash
docker compose up -d
docker compose logs -f keycloak     # wait for "Listening on: http://0.0.0.0:8080"
```

Admin Console: http://localhost:8080/admin (admin / admin on first start).

### Stop / start again — data is kept

```bash
docker compose down        # stops containers, keeps the keycloak-db volume
docker compose up -d       # bank-demo, ajay, akash, roles and groups are still there
```

`docker compose down -v` also deletes the volume, which wipes all Keycloak data.

> Moving from the old `docker run … start-dev` container? Its data does not carry over.
> Recreate the realm once (realm → client → users → role → group, slides 6–10); after that it persists.

### Look at the data in PostgreSQL

```bash
docker exec -it keycloak-postgres psql -U keycloak -d keycloak
```

Or connect any SQL client (DBeaver, pgAdmin) to `localhost:5433`, database `keycloak`, user/password `keycloak`.

```sql
-- Users in the bank-demo realm
SELECT u.username, u.email, u.enabled
FROM user_entity u
JOIN realm r ON r.id = u.realm_id
WHERE r.name = 'bank-demo';

-- Which user is in which group
SELECT u.username, g.name AS group_name
FROM user_group_membership m
JOIN user_entity u    ON u.id = m.user_id
JOIN keycloak_group g ON g.id = m.group_id;

-- Which roles each group grants
SELECT g.name AS group_name, kr.name AS role_name
FROM group_role_mapping gm
JOIN keycloak_group g ON g.id = gm.group_id
JOIN keycloak_role kr ON kr.id = gm.role_id;
```

> **Read-only.** Use these queries to understand how Keycloak stores things.
> Always change data through the Admin Console or Admin REST API — editing tables
> directly can break Keycloak's caches and internal consistency.
