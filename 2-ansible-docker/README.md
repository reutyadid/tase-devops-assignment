# Task 2 — Ansible and Docker: Hello World with a hit counter

An Ansible playbook deploys a Docker Compose application to `localhost`. The app serves a
"Hello World" HTML page. Every page view is counted by a separate stateful service, which
stores the count in a Redis container. The playbook then checks the deployment itself:
it loads the page twice and asserts that the count went up.

## Architecture

```
 browser / curl
       │  http://localhost:8080   (published on 127.0.0.1 only)
       ▼
 ┌──────────┐  POST /hit   ┌───────────┐   INCR hits   ┌─────────┐
 │   web    │ ───────────▶ │  counter  │ ────────────▶ │  redis  │
 │ Flask    │   frontend   │ Flask     │    backend    │ AOF+RDB │
 │ :8000    │   network    │ :8000     │   (internal)  │ volume  │
 └──────────┘              └───────────┘               └─────────┘
```

- **web** — the web server from the assignment. `GET /` asks `counter` for a new hit and
  returns the Hello World page with the count.
- **counter** — the stateful service from the assignment. `POST /hit` runs Redis `INCR`
  (atomic) and returns the new count.
- **redis** — the separate DB container. The data lives on the named volume `redis-data`,
  so the count survives container restarts and re-deployments.

Only `web` publishes a port. `redis` is on an internal network that `web` cannot reach.
Why three containers for "two services": [DECISIONS.md D-001](DECISIONS.md).

## Prerequisites

- Linux, or Windows with WSL2 (tested on Ubuntu 24.04 in WSL2).
- Docker with Compose v2.18 or newer, running, and usable by your user without `sudo`
  (tested with Docker Engine 29.9.3 from Docker Desktop). Docker Desktop on Windows:
  enable WSL integration for your distro. Check with `docker info`.
- Python 3.12 or newer with the `venv` module (`sudo apt install python3-venv` on Ubuntu).
- GNU coreutils `timeout` (standard on Linux and WSL; not installed by default on macOS).
- Free port `8080` on the host.

Ansible itself is **not** a prerequisite. It is installed into a local venv in the next step.

## Quick start

Run every command **from inside `2-ansible-docker/`**: Ansible reads `ansible.cfg` from the
current folder (inventory and collection path). Clone into the Linux file system (for
example `~/`), not under `/mnt/c`: Ansible ignores `ansible.cfg` in a world-writable folder.

One-time setup (about 1–2 minutes):

```bash
git clone https://github.com/reutyadid/tase-devops-assignment.git
cd tase-devops-assignment/2-ansible-docker
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

Deploy (the one command):

```bash
ansible-playbook playbook.yml
```

In a new terminal, activate the venv again first: `source .venv/bin/activate`.
If something fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

The first run builds the images and takes a few minutes. Expected end of the output
(`N` depends on earlier runs: the count is kept in a volume; `changed` is 4 on a new machine):

```
TASK [Check the page and the counter] ****
ok: [localhost] => {
    "msg": "OK: Hello World is served, hit count N -> N+1."
}

PLAY RECAP ****
localhost : ok=11   changed=4   unreachable=0   failed=0 ...
```

## How to verify

Open http://localhost:8080 in a browser, or:

```bash
curl -s localhost:8080
# <h1>Hello World</h1>
# <p>Page views: 3</p>      <- the number goes up on every request
```

Run the playbook a second time. Nothing changes, so it reports `changed=0` (the self-check
still adds 2 hits, see D-008):

```bash
ansible-playbook playbook.yml
# localhost : ok=11   changed=0   unreachable=0   failed=0 ...
```

Look at the running containers (3 healthy, only `web` has a port):

```bash
cd ~/hello-counter && docker compose ps
```

The count is kept in the DB container's volume. It survives a full stop and start:

```bash
cd ~/hello-counter && docker compose down && docker compose up -d --wait && curl -s localhost:8080
```

Containers do not run as root:

```bash
docker exec hello-counter-web-1 id
# uid=10001(app) gid=10001(app) groups=10001(app)
```

## Clean up

```bash
cd ~/hello-counter && docker compose down       # stop and remove containers, keep the count
cd ~/hello-counter && docker compose down -v    # also delete the volume (count is lost)
rm -rf ~/hello-counter                          # remove the deployed files
```

## Lint

```bash
pip install -r requirements-dev.txt
ansible-lint playbook.yml
for f in app/web/Dockerfile app/counter/Dockerfile; do
  docker run --rm -i hadolint/hadolint:v2.15.1 < "$f"
done
```

`ansible-lint` also runs the `yamllint` rules. `hadolint` runs from a pinned image, so it
needs no install. Details: D-011.

## What the playbook does

1. **Pre-flight** — `docker info` (with a 20s timeout, `docker_check_timeout`). If Docker is not reachable, it stops
   with a clear message. Docker is checked, not installed (D-006).
2. **Copy** — creates `~/hello-counter` and copies the source files of `web` and `counter`
   (no `sudo` needed, D-013).
3. **Template** — renders `templates/compose.yaml.j2` with the variables in
   `group_vars/all.yml` (web port, Redis image tag).
4. **Deploy** — `community.docker.docker_compose_v2` with `build: always` and `wait: true`:
   images are rebuilt only when the code changed (build cache), and the task waits until all
   healthchecks pass.
5. **Self-check** — two `GET /` requests; asserts that the page says Hello World and that the
   second count is higher than the first.

## Project structure

```
2-ansible-docker/
├── ansible.cfg              # inventory + local collections path
├── inventory.ini            # one host: localhost, local connection
├── playbook.yml             # the deployment (pre-flight, copy, compose, self-check)
├── group_vars/all.yml       # variables: deploy folder, web port, Redis tag, wait timeout
├── templates/
│   └── compose.yaml.j2      # Compose file: web, counter, redis, 2 networks, 1 volume
├── app/
│   ├── web/                 # Dockerfile, app.py (Flask), requirements.txt
│   └── counter/             # Dockerfile, app.py (Flask + redis-py), requirements.txt
├── requirements.txt         # pinned Python packages for Ansible (control node)
├── requirements-dev.txt     # + ansible-lint
├── requirements.yml         # pinned Ansible collections (community.docker)
├── REQUIREMENTS.md          # assignment text + requirements matrix
├── DECISIONS.md             # design decisions (D-001 … D-013)
└── TROUBLESHOOTING.md       # problems hit while building this
```

## Requirements coverage

See [REQUIREMENTS.md](REQUIREMENTS.md): every requirement, where it is implemented and how
to verify it.

## Design decisions

See [DECISIONS.md](DECISIONS.md). Key points:

- Three containers: web server, stateful counter service, separate Redis DB (D-001).
- Redis with AOF + RDB on a named volume, so the count is durable (D-004).
- Target is `localhost`; the same tasks work on a remote host with the changes in D-005.
- The `docker_compose_v2` module, not shell commands, so the playbook is idempotent (D-007).
- All versions pinned: Python packages, collections, base images (D-010, D-011).

## Security notes

- No secrets in the repo. Redis has no password: it publishes no port and sits on an
  `internal` network that only `counter` can reach (D-009).
- Only `web` is published, and only on `127.0.0.1`, so it is not reachable from the network.
- `web` and `counter` run as a non-root user with a numeric UID (`10001`).
- Every container has a memory limit (`128m`) and a healthcheck, plus
  `restart: unless-stopped`.
- No `sudo` / `become` in the playbook.

## Known limitations / what I'd add in production

- **Remote server:** inventory with an SSH deploy user, a role that installs Docker,
  deploy folder `/opt/hello-counter` with `become` (D-005).
- **Redis auth:** ACL user + password from Ansible Vault or a secrets manager (D-009).
- **Reverse proxy:** Nginx or a load balancer with TLS in front of `web` (D-002).
- **Docker access:** membership in the `docker` group is equal to root on the host; keep that
  group small on real servers.
- **Dependencies:** generate hashed lock files with `pip-tools` and update them with
  Dependabot (D-011).
- **Backups:** the Redis volume is not backed up (D-004).
- **Counting:** not exactly-once. If `web` times out while `counter` still finishes, the hit
  is counted but the user gets a 503 (D-002). The self-check adds 2 hits on every run (D-008).
