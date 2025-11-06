# Laurentius — Docker / WildFly development image

This repository contains Laurentius (WildFly based) application sources and a Docker build (Dockerfile.cicd) and docker-compose configuration for local development. The image and entrypoint are designed to:

- build the application artifacts in a multi-stage Dockerfile,
- copy required modules and deployments into a WildFly image,
- run a one-time "init" pass that creates the demo database and sample data on first container start, and
- start WildFly in the foreground so Docker manages the server lifecycle.

This README documents how to build, run and operate the Docker image and compose stack.

---

## Quick summary

- Use `docker compose build --no-cache` and `docker compose up -d` to rebuild and run the service.
- The image contains an entrypoint wrapper `laurentius-entrypoint.sh` which performs a one-time initialization on first run (marker file `.initialized` in the named data volume).
- Named Docker volumes are used for data and logs to avoid host-permission issues (especially on Windows).
- A container healthcheck is included (uses `curl` — `curl` is installed in the image).

---

## Prerequisites

- Docker engine (Docker Desktop or Docker Engine)
- Docker Compose v2 (the `docker compose` command)
- Git (if pulling this repo)

---

## Files of interest

- `Dockerfile.cicd` — multi-stage image build (maven build stage + WildFly packaging)
- `docker-compose.yml` — Compose service using named volumes
- `scripts/install/wildfly-11.0/laurentius-demo.sh` (installed into the image as `laurentius-demo.sh`) — original init script
- `scripts/install/wildfly-11.0/laurentius-entrypoint.sh` — wrapper that runs init once (marker) and then starts WildFly
- Named volumes: `laurentius-data` and `laurentius-logs`

---

## Build & run (recommended)

1. From repository root, stop any running stack:
```bash
docker compose down
```

2. Build image (no cache to ensure changes are included):
```bash
docker compose build --no-cache
```
(or)
```bash
docker build -f Dockerfile.cicd -t laurentius:develop . --progress=plain
```

3. Start stack:
```bash
docker compose up -d --force-recreate --remove-orphans
```

4. Follow logs:
```bash
docker logs -f --tail 200 laurentius
```

5. Confirm the application is reachable:
```bash
curl -I http://localhost:8080/
curl -I http://localhost:9990/management
```

---

## First-run initialization behavior

The image includes an entrypoint wrapper that will run a one-time initialization pass on first container start:

- It checks for a marker file at:
  `/opt/jboss/wildfly/standalone/data/laurentius-home/.initialized`
- If the marker is absent and `LAU_AUTO_INIT` is not set to `"false"`, the wrapper:
  - starts WildFly in background with `-Dlaurentius.hibernate.hbm2ddl.auto=create` and `-Dlaurentius.init=true` plus `-Dlaurentius.domain=$LAU_DOMAIN`,
  - waits for the server to report "WildFly ... started" in `server.log`,
  - issues a `:shutdown` via `jboss-cli.sh`,
  - creates the `.initialized` marker in the data volume,
  - then starts WildFly in the foreground normally.
- The marker lives in the `laurentius-data` named volume so it persists across restarts.

This guarantees the demo DB and sample data are created only once (unless you explicitly remove the marker).

---

## Relevant environment variables

Set these in `docker-compose.yml` or with `docker run -e ...`:

- `LAU_DOMAIN` (required for init): e.g. `court-laurentius.si`
- `LAU_AUTO_INIT` (default `true`): if `false`, the automatic first-run init is skipped
- `LAU_AUTO_ACCEPT` (default `false`): used by the legacy init script for non-interactive confirmation (safe to leave true)
- `LAU_INIT` (optional): legacy flag that triggers init when passed to the script directly
- `DB_INI_ACTION` / `DB_DIALECT` — optional overrides used by the entrypoint / script (defaults are set in the scripts)

Example compose environment (already used in this repo):
```yaml
environment:
  LAU_DOMAIN: 'court-laurentius.si'
  LAU_AUTO_INIT: 'true'
  LAU_AUTO_ACCEPT: 'true'
```

---

## docker-compose example

Your `docker-compose.yml` (kept in repo) should look similar to:

```yaml
version: '3.8'

services:
  laurentius:
    build:
      context: .
      dockerfile: Dockerfile.cicd
    image: laurentius:develop
    container_name: laurentius
    restart: unless-stopped
    ports:
      - '8080:8080'
      - '8443:8443'
      - '9990:9990'
    volumes:
      - laurentius-data:/opt/jboss/wildfly/standalone/data/laurentius-home
      - laurentius-logs:/opt/jboss/wildfly/standalone/log
    environment:
      LAU_DOMAIN: 'court-laurentius.si'
      LAU_AUTO_INIT: 'true'
      LAU_AUTO_ACCEPT: 'true'
    healthcheck:
      test: ["CMD-SHELL","curl -f http://localhost:8080/ || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5

volumes:
  laurentius-data:
  laurentius-logs:
```

Note: the image installs `curl` so the healthcheck using `curl` succeeds.

---

## Logs, volumes & permissions

- Logs are written to the named volume `laurentius-logs` (mounted at `/opt/jboss/wildfly/standalone/log`).
- Data and marker live in `laurentius-data` (mounted at `/opt/jboss/wildfly/standalone/data/laurentius-home`).
- If you encounter permission issues (e.g. `server.log: Permission denied`), run:
```bash
# use the image's jboss user UID/GID by running a helper container from the built image
docker run --rm -v laurentius-logs:/opt/jboss/wildfly/standalone/log laurentius:develop sh -c "chown -R jboss:jboss /opt/jboss/wildfly/standalone/log || true; chmod -R a+rwX /opt/jboss/wildfly/standalone/log || true"
```

---

## Re-running initialization (reset demo DB)

If you need a fresh demo DB (re-run init), either:

- Remove marker and restart the service (the entrypoint will run init again on next start):
```bash
docker exec -it laurentius sh -c "rm -f /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized"
docker restart laurentius
```

- Or run a one-off init container (safer; does not interfere with an already running service):
```bash
docker run --rm \
  -e LAU_AUTO_ACCEPT=true -e LAU_DOMAIN=court-laurentius.si \
  -v laurentius-data:/opt/jboss/wildfly/standalone/data/laurentius-home \
  -v laurentius-logs:/opt/jboss/wildfly/standalone/log \
  laurentius:develop \
  /opt/jboss/wildfly/bin/standalone.sh -c standalone-laurentius.xml \
    -Dlaurentius.home=/opt/jboss/wildfly/standalone/data/laurentius-home/ \
    -Dlaurentius.hibernate.hbm2ddl.auto=create \
    -Dlaurentius.hibernate.dialect=org.hibernate.dialect.H2Dialect \
    -Dlaurentius.init=true -Dlaurentius.domain=court-laurentius.si \
    -b 0.0.0.0 -bmanagement 0.0.0.0
```

---

## Troubleshooting & debug tips

- Container restarts immediately with no logs:
  - Run a debug container and execute the entrypoint/init script manually to see the failure:
    ```bash
    docker run -d --name laurentius-debug \
      -v laurentius-data:/opt/jboss/wildfly/standalone/data/laurentius-home \
      -v laurentius-logs:/opt/jboss/wildfly/standalone/log \
      laurentius:develop sleep infinity

    docker exec -it laurentius-debug /bin/sh
    # then run (inside container)
    env LAU_AUTO_ACCEPT=true LAU_DOMAIN=court-laurentius.si /opt/jboss/wildfly/bin/laurentius-demo.sh --init -d court-laurentius.si
    ```
- Check container health:
  ```bash
  docker inspect --format '{{json .State.Health}}' laurentius
  ```
- Check last exit code & state:
  ```bash
  docker inspect --format '{{json .State}}' laurentius
  ```
- If the `COPY --from=build` step fails during build:
  - Ensure the file exists in the build context, run the build from the repo root, and use `--no-cache`.
  - If needed, run `docker builder prune --force` before rebuilding.

---

## Back up and restore volumes

### PowerShell (Windows) commands

1. Back up the current working instance (creates `laurentius-data-backup.tgz` / `laurentius-logs-backup.tgz` in the repo root):
  ```powershell
  cd c:\Repos\Laurentius
  docker compose down
  docker run --rm -v laurentius-data:/data -v ${PWD}:/backup busybox tar czf /backup/laurentius-data-backup.tgz -C /data .
  docker run --rm -v laurentius-logs:/data -v ${PWD}:/backup busybox tar czf /backup/laurentius-logs-backup.tgz -C /data .
  ```

2. Restore from that backup later:
  ```powershell
  cd c:\Repos\Laurentius
  docker compose down
  docker volume rm laurentius-data laurentius-logs
  docker volume create laurentius-data
  docker run --rm -v laurentius-data:/data -v ${PWD}:/backup busybox sh -c "cd /data && tar xzf /backup/laurentius-data-backup.tgz"
  docker volume create laurentius-logs
  docker run --rm -v laurentius-logs:/data -v ${PWD}:/backup busybox sh -c "cd /data && tar xzf /backup/laurentius-logs-backup.tgz"
  docker compose up -d laurentius
  ```

3. Test a clean auto-initialized install (drops the volumes, rebuilds, and starts fresh):
  ```powershell
  cd c:\Repos\Laurentius
  docker compose down
  docker compose build laurentius
  docker volume rm laurentius-data laurentius-logs
  docker compose up -d laurentius
  docker logs -f laurentius
  ```
  The logs should print `Initialization complete` exactly once. On subsequent restarts, the entrypoint sees the `.initialized` marker in `laurentius-data` and skips the init phase.

### Generic Linux/macOS commands

- Back up:
  ```bash
  docker run --rm -v laurentius-data:/data -v "$(pwd)":/backup alpine sh -c "tar -C /data -cf /backup/laurentius-data.tar ."
  ```

- Restore:
  ```bash
  docker run --rm -v laurentius-data:/data -v "$(pwd)":/backup alpine sh -c "tar -C /data -xf /backup/laurentius-data.tar"
  ```

---

## Committing changes

- Make sure the following are committed so CI and others get the same behavior:
  - `Dockerfile.cicd`
  - `docker-compose.yml`
  - `scripts/install/wildfly-11.0/laurentius-entrypoint.sh`
  - `scripts/install/wildfly-11.0/laurentius-init.sh`

Example commit (from repo root):
```bash
git add Dockerfile.cicd docker-compose.yml scripts/install/wildfly-11.0/laurentius-entrypoint.sh scripts/install/wildfly-11.0/laurentius-init.sh
git update-index --add --chmod=+x scripts/install/wildfly-11.0/laurentius-entrypoint.sh
git commit -m "Add first-run entrypoint and ensure non-interactive init + correct volume perms"
git push origin develop
```

---

## Notes & recommendations

- For production usage, consider running the DB in a dedicated database container (Postgres, Oracle, etc.) rather than the in-memory/demo H2 mode.
- Keep LAU_AUTO_INIT OFF in production and run initialization via a controlled migration pipeline.
- If you want Java to be PID 1 (strictly), adjust the entrypoint to exec Java directly; current approach execs `standalone.sh` which ultimately launches Java (acceptable for normal Docker management).
- Add a README section that documents the `laurentius-demo.sh` script options (so operators know how to run manual init if needed).

---



REAL DEAL manual intervention that works:

docker run --rm --entrypoint /bin/sh --user 0 -v laurentius-data:/seed laurentius:develop -c "mkdir -p /seed && cp -a /opt/jboss/wildfly/standalone/data/laurentius-home/. /seed/"


1. Start the debug container.
````powershell
docker run -d --name laurentius-debug --entrypoint /bin/sh `
  -p 8080:8080 -p 8443:8443 -p 9990:9990 `
  -v laurentius-data:/opt/jboss/wildfly/standalone/data/laurentius-home `
  -v laurentius-logs:/opt/jboss/wildfly/standalone/log `
  laurentius:develop -c "sleep infinity"
````

2. Enter the container and run the init.
````powershell
docker exec -it laurentius-debug /bin/sh
/opt/jboss/wildfly/bin/laurentius-demo.sh --init -d mb-laurentius.si

touch /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized
#then (still in the container as root)
chown jboss:jboss /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized


exit # remove the debug container, and start the normal service. The entrypoint will find the marker and skip reinitialisation.
````

STOP HERE!
3. Remove the debug container.
````powershell
docker rm -f laurentius-debug
````

4. Start the service normally.
````powershell
docker compose up -d laurentius
````



Completed (1/3) *Verify manual init steps*

Nice — below are the exact PowerShell-ready commands for running the manual init and creating the `.initialized` marker as root, with a couple of safe alternatives if the debug container was started as non-root or already removed.

Pick the flow you need.

1) Start the debug container as root (recommended — you’ll be able to run init and create the marker without extra exec flags)
```powershell
docker run -d --name laurentius-debug --entrypoint /bin/sh --user 0 `
  -p 8080:8080 -p 8443:8443 -p 9990:9990 `
  -v laurentius-data:/opt/jboss/wildfly/standalone/data/laurentius-home `
  -v laurentius-logs:/opt/jboss/wildfly/standalone/log `
  laurentius:develop -c "sleep infinity"
```

2) Exec into the debug container as root and run the init
```powershell
# open a root shell in the debug container
docker exec -it --user 0 laurentius-debug /bin/sh

# inside container (root): run the legacy init
/opt/jboss/wildfly/bin/laurentius-demo.sh --init -d mb-laurentius.si

# verify success (inside container)
/bin/sh -c "tail -n 200 /opt/jboss/wildfly/standalone/log/server.log"
```

3) Still inside as root: create the marker and fix ownership
```sh
# create marker
touch /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized

# set ownership to the jboss user inside container
chown jboss:jboss /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized
```

4) Exit, remove debug container and start the normal service
```powershell
exit
docker rm -f laurentius-debug
docker compose up -d laurentius
```

If you already started the debug container as non-root (or you started it as jboss), use these alternatives:

A) Exec as root into an existing running container (no need to restart it)
```powershell
# run the init as the jboss user if you prefer (no ownership change possible if init writes files as jboss):
docker exec -it laurentius-debug /bin/sh
# inside (jboss): run init
/opt/jboss/wildfly/bin/laurentius-demo.sh --init -d mb-laurentius.si

# then from host, create the marker as root inside the container:
docker exec --user 0 laurentius-debug sh -c "touch /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized && chown jboss:jboss /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized"
```

B) If the debug container was removed already (marker missing), create the marker using a short one-shot root container that mounts the same volume:
```powershell
docker run --rm --user 0 -v laurentius-data:/opt/jboss/wildfly/standalone/data/laurentius-home laurentius:develop `
  sh -c "mkdir -p /opt/jboss/wildfly/standalone/data/laurentius-home && touch /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized && chown jboss:jboss /opt/jboss/wildfly/standalone/data/laurentius-home/.initialized"
```

Verification after bringing the normal service up
```powershell
# Follow recent logs (look for absence of init messages or a successful 'Initialization complete' earlier during manual steps)
docker logs -f --tail 200 laurentius

# Or inspect the marker directly in a one-off root container
docker run --rm --user 0 -v laurentius-data:/data busybox sh -c "ls -l /data | grep .initialized || true"
```

Notes and tips
- Use `--user 0` when you need root privileges inside a container. `docker exec --user 0` is the usual way to run a single command as root in an existing container.
- Running the init as root is convenient because the script and subsequent touches/chowns succeed. If you run the init as `jboss` user and it writes files, you may still need to fix some ownership as root.
- The safer approach for automated CI/ops is the one-off init container or the entrypoint automated init — both avoid leaving a debugging container around.
- If you want, I can add the exact snippet (the recommended root flow plus the exec fallback) into README_docker.md at the manual-init section and commit it for you.