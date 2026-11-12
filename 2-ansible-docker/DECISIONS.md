# Decisions

Each significant decision gets one entry. Newest at the bottom.

---

## D-001: Interpretation of "two services" — three containers

- **Date:** 2026-11-10
- **Context:** The task asks for "two services: 1. Web server ... 2. Stateful service that will
  keep a counter-hit from the web server in a separate DB container" (R-3, R-5, R-6).
  It is not clear whether the DB container is the second service, or a separate container
  used by the second service.
- **Options considered:**
  1. Two containers: `web` counts hits itself, the DB is "the stateful service".
     Pros: matches "two services" if the DB is counted as a service. Cons: there is no
     separate counter service; a reviewer who expects one will see a missing service.
  2. Three containers: `web` → `counter` (stateful service) → `redis` (DB container).
     Pros: reads "keep a counter ... in a separate DB container" literally: the service keeps
     the counter *in* a container that is separate from it. It also covers reading 1 (there
     is a web server, a stateful service and a separate DB). Cons: one more small app,
     service-to-service HTTP call, one more healthcheck.
- **Decision:** Option 2. Compose services: `web`, `counter`, `redis`.
  The page shows "Hello World" and the current hit count.
- **Why:** It satisfies both readings. Building more than one reading needs is a smaller risk
  than missing a service that a reviewer expects.
- **Trade-offs:** More code to explain (two Flask apps, two Dockerfiles).
- **Sources:** Assignment text in [REQUIREMENTS.md](REQUIREMENTS.md).

---

## D-002: Web server — Flask renders the page

- **Date:** 2026-11-10
- **Context:** R-4 needs a web server that serves a "Hello World" HTML page and triggers a hit.
- **Options considered:**
  1. Flask: every page request calls `counter` and renders HTML with the count.
     Pros: the hit comes "from the web server" exactly as written; `curl` counts too, so the
     self-check is simple; same language and Dockerfile shape as `counter`.
     Cons: not a "classic" web server; in production it would sit behind a reverse proxy.
  2. Nginx serving static HTML + JavaScript calling `/api/hit` through a proxy.
     Pros: a real web server, no Python in the web container.
     Cons: the browser sends the hit, not the web server; `curl` does not run JavaScript, so it
     does not count; three technologies (Nginx config, proxy, JS) to explain.
- **Decision:** Option 1 — Flask.
  - `GET /` calls `counter` with a 2-second timeout. If `counter` fails or times out, `web`
    returns HTTP 503 with a short message (a visible failure, not a hidden one).
  - `GET /healthz` returns `ok` without calling `counter`, so healthchecks never add hits.
    `counter` has its own `/healthz` for the same reason.
- **Why:** Closest to the task wording, simplest to verify, one technology for both apps.
  Without a timeout, `urllib` waits forever, so a stuck `counter` would block both gunicorn
  workers and take the whole page down.
- **Trade-offs:** No reverse proxy. Production note in the README: put Nginx in front.
  - No exactly-once counting: if `web` times out after 2s while `counter` still finishes
    `INCR`, the user sees 503 but the hit is counted. Exactly-once needs idempotency keys,
    which is out of scope. `counter` keeps its own Redis timeouts at 0.5s each (connect + read
    stay under 2s) and disables
    redis-py's automatic retries (default: 10 retries) to make this rare and to avoid
    counting one hit twice.
  - Flask answers `HEAD` on every `GET` route, so `HEAD /` also adds a hit. Nothing in this
    project sends `HEAD /` (healthchecks use `/healthz`, the self-check uses `GET`), so this
    is documented, not handled in code.
  - `web` calls `counter` through an opener with no proxy, so an `HTTP_PROXY` set by Docker
    Desktop on a corporate machine cannot break the internal call.
- **Sources:**
  - https://flask.palletsprojects.com/en/stable/deploying/

---

## D-003: Python framework and WSGI server — Flask + gunicorn

- **Date:** 2026-11-10
- **Context:** Both `web` and `counter` are small Python HTTP apps (R-4, R-5).
- **Options considered:**
  1. Flask + gunicorn — widely used, minimal code.
  2. FastAPI + uvicorn — modern, but async and Pydantic are not needed for one route.
  3. stdlib `http.server` — no dependencies, but not meant for production.
- **Decision:** Flask + gunicorn (2 workers) for both services. `web` calls `counter` with
  stdlib `urllib` and an explicit timeout (no `requests` dependency, see D-002). `counter` uses the `redis` client library.
  Versions are pinned in each app's `requirements.txt`.
- **Why:** The Flask docs say the development server must not be used in production.
  gunicorn is the first WSGI server listed in the Flask deployment docs.
- **Trade-offs:** Each service has its own fully pinned `requirements.txt` (separate build
  contexts), so the shared Flask/gunicorn pins appear in both files. An upgrade must update
  both.
  - The two Dockerfiles are identical, and the `web` and `counter` healthchecks in the
    Compose template are the same block. This duplication is on purpose: one shared
    Dockerfile or a YAML anchor would remove it, but adds a mechanism to explain for two
    small services.
- **Sources:**
  - https://flask.palletsprojects.com/en/stable/deploying/
  - https://flask.palletsprojects.com/en/stable/deploying/gunicorn/

---

## D-004: Redis persistence — AOF + RDB, no backups

- **Date:** 2026-11-10
- **Context:** The hit counter must survive container restart and recreation (R-6).
  Redis keeps data in memory, so a persistence mode is required.
- **Options considered:**
  1. RDB only (snapshots) — compact file, fast restart, easy to back up.
     Cons: writes between snapshots are lost on a crash.
  2. AOF only — every write is logged; with the default `appendfsync everysec`
     at most ~1 second of writes is lost on a crash.
     Cons: Redis docs discourage AOF alone (no snapshot for backups or as a
     safety net against AOF bugs).
  3. AOF + RDB — AOF for durability, RDB snapshots as a safety net.
- **Decision:** AOF + RDB: `redis-server --appendonly yes --save 60 1`
  (`appendfsync everysec` is the default, so it is not set explicitly).
  Data lives on a named volume mounted at `/data`
  (`/data/appendonlydir/` for the multi-part AOF, `/data/dump.rdb` for RDB).
- **Why:** Every page hit is a write, so AOF keeps the counter accurate.
  This is the combination recommended by the Redis docs. When both are
  enabled, Redis restores from the AOF on restart because it is the most complete.
  The save point is set explicitly so the config shows exactly what is on.
- **Not in scope:** Backups. The RDB file stays on the volume and is not copied
  anywhere. The volume protects against container restart/recreation, NOT
  against host disk loss or `docker compose down -v`.
- **What I would do in production:** Ship RDB snapshots off-host on a schedule,
  with a tested restore procedure; or use a managed Redis service.
- **Sources:**
  - https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/
  - https://hub.docker.com/_/redis

---

## D-005: Target host — localhost with a local connection

- **Date:** 2026-11-10
- **Context:** The playbook needs a target host (R-1). The reviewer must be able to run it
  quickly on one machine.
- **Options considered:**
  1. `localhost` with `ansible_connection=local` — zero setup. Cons: no SSH shown.
  2. A VM (Multipass / Vagrant) over SSH — most realistic. Cons: needs Hyper-V networking from
     WSL, SSH keys, Docker installation on the VM, and at least 1 GB RAM; the reviewer must
     reproduce all of it.
  3. SSH into a container — needs Docker-in-Docker; fragile.
- **Decision:** Option 1. `inventory.ini` has one host:
  `localhost ansible_connection=local ansible_python_interpreter="{{ ansible_playbook_python }}"`.
- **Why:** Simplest to run and review. The playbook copies files to a deploy folder and runs
  Compose there (D-013), so the same tasks work on a remote host.
- **Trade-offs:** SSH and a separate control node are not demonstrated. Moving to a real
  server needs these steps:
  1. Inventory: the server address and a dedicated SSH deploy user, instead of
     `ansible_connection=local`; drop the `ansible_python_interpreter` line (it points to the
     control node's Python and is only valid for a local connection).
  2. A role that installs Docker (D-006).
  3. Deploy folder `/opt/<app>` with `become` (D-013).
  4. Redis authentication with a password from Ansible Vault (D-009).
- **Sources:**
  - https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html
  - https://docs.ansible.com/ansible/latest/inventory_guide/connection_details.html

---

## D-006: Docker on the target — check only, do not install

- **Date:** 2026-11-10
- **Context:** The target must have Docker and the Compose plugin (N-4).
- **Options considered:**
  1. Check only: fail early with a clear message if Docker is not reachable.
  2. Install Docker Engine from the playbook. Cons: conflicts with Docker Desktop on WSL,
     needs `sudo`, changes the reviewer's system.
- **Decision:** Option 1. Docker is a documented prerequisite. The pre-flight task runs
  `docker info` and fails with a clear message (for example "Docker Desktop is not running or
  WSL integration is off"). The Compose version is not checked by us: the
  `docker_compose_v2` module already fails if Compose is older than 2.18.
  The check runs as `timeout -k 5 20 docker info` (20 = `docker_check_timeout`): in testing, with Docker Desktop stopped,
  `docker info` in WSL hung instead of failing, so the playbook never reached the message.
- **Why:** Safe for the reviewer's machine; no root needed.
- **Trade-offs:** Not a full "bare server" setup. Production note: a separate role installs
  Docker on real servers.
- **Sources:**
  - https://docs.ansible.com/ansible/latest/collections/community/docker/docker_compose_v2_module.html
    (requirement: Docker CLI with Compose plugin 2.18.0 or later)

---

## D-007: Compose from Ansible — `community.docker.docker_compose_v2`

- **Date:** 2026-11-10
- **Context:** The playbook must start the Compose application (R-2) and be idempotent (N-2).
- **Options considered:**
  1. `community.docker.docker_compose_v2` module — reports `changed` only when Compose
     actually changed something.
  2. `ansible.builtin.command: docker compose up -d` — always reports `changed`; needs a
     `changed_when` parser to fake idempotency.
- **Decision:** Option 1. Collection pinned in `requirements.yml`: `community.docker` 5.4.0.
- **Why:** Correct change reporting with no tricks.
- **Trade-offs:** Needs ansible-core >= 2.17 (collection 5.x) and Compose >= 2.18.
- **Sources:**
  - https://docs.ansible.com/ansible/latest/collections/community/docker/docker_compose_v2_module.html
  - https://galaxy.ansible.com/ui/repo/published/community/docker/

---

## D-008: Playbook structure — one playbook, Compose as a template, build on target

- **Date:** 2026-11-10
- **Context:** How to organize the Ansible code and how images get to the target (R-1, R-2, N-6).
- **Options considered:**
  1. One playbook (~10 tasks) vs. a role. A role adds folders that hold one file each; it pays
     off only when logic is shared between playbooks.
  2. Compose file as a Jinja2 template vs. a static copy. A static file duplicates the web port
     (once in Compose, once in the self-check task).
  3. Build images on the target with Compose vs. push to a registry. A registry would make this
     task depend on task 1 (Nexus).
- **Decision:**
  - One `playbook.yml`; variables in `group_vars/all.yml` (Ansible convention).
  - `templates/compose.yaml.j2` with only a few variables (web port, Redis image tag).
  - Images built on the target by Compose, module option `build: always`.
  - Module options `wait: true` + `wait_timeout` so the task returns only when all services
    are healthy. Then the self-check (`uri` + `assert`) runs.
- **Why:** Smallest structure that still deploys properly. `build: always` is needed because
  the default `build: policy` only builds when the image is missing, so code changes would not
  be deployed. With an unchanged build context Docker's build cache returns the same image, the
  containers are not recreated, and the run reports `changed=0` (confirmed: second run
  `changed=0`). This relies on the module option `ignore_build_events` (default `true`),
  so a cached build alone is not reported as a change.
  Without `wait`, `docker compose up` returns when the containers have started, not when
  gunicorn listens, so the first self-check could get "Connection refused".
- **Trade-offs:** Not reusable as a role. The self-check asserts that the second count is
  higher than the first (not exactly +1), so a visitor refreshing the page during the run
  does not fail a healthy deployment. The self-check sends 2 real page requests, so every
  run adds 2 hits to the counter, while Ansible still reports `changed=0` (`uri` does not
  report changes). This is intended: it tests the real path. A read-only endpoint would avoid
  it, but it is a feature the task does not need.
- **Sources:**
  - https://docs.ansible.com/ansible/latest/tips_tricks/sample_setup.html
  - https://docs.ansible.com/ansible/latest/collections/community/docker/docker_compose_v2_module.html

---

## D-009: Secrets — none needed; Redis is isolated by the network

- **Date:** 2026-11-10
- **Context:** Rule: no secrets in the repo (N-5). Redis could use a password.
- **Options considered:**
  1. No Redis password; Redis is only on the internal `backend` network and publishes no port.
  2. Password generated at deploy time with the `ansible.builtin.password` lookup, stored in a
     git-ignored file.
  3. Ansible Vault — the reviewer would need the vault password, which breaks "one command".
- **Decision:** Option 1.
- **Why:** No other container (only `counter` is on `backend`) and no remote host can reach
  Redis, so there is no secret to manage.
- **Trade-offs:** Any container attached to `backend` can use Redis without authentication.
  On the Docker host itself, local processes and users with Docker access (`docker exec`) can
  still reach Redis; network isolation does not protect against them.
- **What I would do in production:** Redis ACL user + password from Ansible Vault (or a secrets
  manager), TLS between services.
- **Sources:**
  - https://redis.io/docs/latest/operate/oss_and_stack/management/security/
  - https://docs.docker.com/reference/compose-file/networks/

---

## D-010: Security defaults for containers and networks

- **Date:** 2026-11-10
- **Context:** Working rules require pinned versions, least privilege and minimal exposed
  ports (N-5). The host is limited in RAM.
- **Decision:**
  - Pinned image tags and package versions (no `latest`).
  - `web` and `counter` run as a non-root user (`USER` in the Dockerfile) and listen on port
    8000, the gunicorn convention. Docker (20.10+) lets non-root processes in a container
    bind low ports, but a high port also works in runtimes that do not (for example rootless
    setups). The official Redis image already drops to the `redis` user.
  - Only `web` is published to the host (`8080:8000`). `counter` and `redis` publish nothing.
  - Two networks: `frontend` (`web`, `counter`) and `backend` (`counter`, `redis`), with
    `backend` marked `internal: true`. `web` cannot reach Redis at all; Redis has no outbound
    access. `frontend` cannot be internal because the published port needs it.
  - Healthchecks on all services; `depends_on` with `condition: service_healthy`
    (start order: `redis` → `counter` → `web`). App healthchecks use `/healthz` (D-002), so
    they do not add hits.
  - Pinned tags: base image `python:3.12.16-slim-trixie` for `web` and `counter`,
    `redis:8.10.3-alpine` for Redis (small image, official variant).
  - Memory limit `mem_limit: 128m` on every container. Measured idle usage with
    `docker stats --no-stream` (2026-11-12): `web` 64 MiB, `counter` 80 MiB, `redis` 15 MiB.
    One value for all services keeps it simple; Redis keeps headroom because a background
    save forks the process.
  - `restart: unless-stopped` on every service: a crashed or OOM-killed container, and the
    whole app after a Docker restart, come back on their own. Not required by the task;
    approved as a one-line resilience default.
  - No `become`/`sudo` in the playbook (D-013).
- **Why:** Least privilege at every layer with only a few lines of YAML.
- **Trade-offs:** None significant.
- **Sources:**
  - https://docs.docker.com/compose/how-tos/startup-order/
  - https://docs.docker.com/reference/compose-file/services/#restart
  - https://docs.docker.com/reference/compose-file/networks/
  - https://docs.docker.com/engine/security/#docker-daemon-attack-surface
  - https://hub.docker.com/_/redis

---

## D-011: Installing Ansible — Python venv with pinned versions

- **Date:** 2026-11-10
- **Context:** Ansible is needed on the control node (N-1). Ubuntu 24.04 ships Python 3.12.
- **Options considered:**
  1. venv + `requirements.txt` with a pinned `ansible-core` — exact version, no `sudo`, no
     system changes.
  2. apt — Ubuntu 24.04 ships ansible-core 2.16, too old for `community.docker` 5.x.
  3. pipx — isolated, but must be installed first, and adding `ansible-lint` next to it is harder.
  4. The full `ansible` package — hundreds of collections; the `community.docker` version is
     chosen by the package, not by us.
- **Decision:** Option 1. `ansible-core==2.21.6` (the latest 2.22 needs Python >= 3.13).
  The lint tool goes in `requirements-dev.txt` because the reviewer does not need it to run
  the playbook. `.venv/` is git-ignored.
- **Linters:**
  - `ansible-lint==26.11.0` (passes the `production` profile). It already runs the
    `yamllint` rules with Ansible-friendly settings, so `yamllint` is not run on its own
    (run alone with defaults it flags 80-char lines and scans `.venv/`).
  - `hadolint` runs from its pinned image `hadolint/hadolint:v2.15.1`, so nothing extra is
    installed. Its rule DL3066 led to a numeric user and group in the Dockerfiles
    (`USER 10001:10001`): platforms such as Kubernetes can verify "not root" only for a
    numeric UID. The GID is fixed too, otherwise `useradd` picks a free one (it picked 999).
- **Pinning level:** The full environment is pinned, not only direct dependencies.
  1. Direct only (`ansible-core==2.21.6`) — the right style for a library, but a later install
     can pull newer, untested versions of Jinja2, cryptography, etc.
  2. Full environment — `requirements.txt` is the `pip freeze` output of the tested venv.
     Python Packaging docs: requirements files for an environment "often contain an
     exhaustive listing of pinned versions".
  3. Full environment + hashes (`--require-hashes`) — also protects against a replaced
     package on PyPI; more tooling than this task needs.

  Chosen: level 2. `ansible-galaxy` has no lock file, so `requirements.yml` pins
  `community.docker` and also its dependency `community.library_inventory_filtering_v1`.
- **Why:** Reproducible versions with no root access: the reviewer installs exactly what was
  tested.
- **Trade-offs:** Three one-time setup commands in the README. Upgrading means regenerating
  `requirements.txt` with `pip freeze`.
- **What I would do in production:** Keep direct dependencies in `requirements.in` and generate
  a hashed `requirements.txt` with `pip-tools` (or `uv`), updated by a bot such as Dependabot.
- **Sources:**
  - https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
  - https://pypi.org/project/ansible-core/
  - https://pip.pypa.io/en/stable/topics/repeatable-installs/
  - https://packaging.python.org/en/latest/discussions/install-requires-vs-requirements/
  - https://ansible.readthedocs.io/projects/lint/
  - https://github.com/hadolint/hadolint

---

## D-012: Entry point — `ansible.cfg` and one command

- **Date:** 2026-11-10
- **Context:** The reviewer should run the deployment with one command (N-1).
- **Options considered:**
  1. `ansible.cfg` sets the inventory → `ansible-playbook playbook.yml`.
  2. A Makefile (`make deploy`) — one more tool and file; `make` is not always installed.
- **Decision:** Option 1. One-time setup (venv, collections) is documented in the README.
- **Why:** Standard Ansible convention, nothing extra to learn.
- **Trade-offs:** Ansible reads `ansible.cfg` from the current working directory, so every
  command (`ansible-galaxy`, `ansible-playbook`) must run from inside `2-ansible-docker/`.
  From the repo root the inventory and `collections_path` are not applied. Ansible also
  ignores `ansible.cfg` in a world-writable directory (for example a repo cloned under
  `/mnt/c` in WSL). The README covers both points.
- **Sources:**
  - https://docs.ansible.com/ansible/latest/reference_appendices/config.html

---

## D-013: Deploy folder on the target — `~/hello-counter`, no sudo

- **Date:** 2026-11-10
- **Context:** The playbook copies the app source and renders the Compose file to a folder on
  the target, then runs Compose there (R-1).
- **Options considered:**
  1. A folder in the user's home (`~/hello-counter`) — no `sudo` needed.
  2. `/opt/hello-counter` — usual on servers, but owned by root, so the playbook needs
     `become` and the reviewer must type a sudo password.
  3. Run Compose directly from the repo — simplest, but it is not a real deployment and only
     works on localhost.
- **Decision:** Option 1.
- **Why:** Least privilege: the playbook only writes files and talks to Docker, and neither
  needs root. Keeps "one command" with no password prompt.
- **Trade-offs:** The app belongs to a personal user. Note: access to the Docker daemon is
  root-equivalent anyway, so on real servers Docker group membership must be restricted.
- **What I would do in production:** `/opt/<app>` with `become`, run by a dedicated deploy
  user over SSH.
- **Sources:**
  - https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html
  - https://docs.docker.com/engine/security/#docker-daemon-attack-surface
