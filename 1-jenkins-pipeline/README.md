# <Task name>

One-paragraph summary: what this does and how it meets the assignment.

## Architecture

Short description (+ simple diagram if it helps).

## Prerequisites

- Tool — version

## Quick start

```bash
# exact commands, copy-paste ready
```

## How to verify

```bash
# command
# expected output
```

## Project structure

```
.
├── ...
```

## Requirements coverage

See [REQUIREMENTS.md](REQUIREMENTS.md) — every requirement and where it is implemented.

## Design decisions

See [DECISIONS.md](DECISIONS.md). Key points:
- ...

## Security notes

- How secrets are handled
- ...

## Known limitations / what I'd add in production

- **Host provisioning with Terraform + Ansible.** Here Jenkins runs on a laptop with
  `docker compose up`. On a real server: Terraform creates the host, Ansible installs Docker,
  copies the Compose files and manages secrets (e.g. Ansible Vault). Jenkins itself is still
  configured by JCasC + Job DSL (see D-007). Ansible was left out of this task on purpose: it
  would only wrap `docker compose up` and add a prerequisite for the reviewer.
- **Internal proxy for downloads.** Here `mvnw` downloads Maven and dependencies directly from
  Maven Central (checksum-verified, see D-008). In production: route them through an internal
  proxy repository (e.g. Nexus, `MVNW_REPOURL` + a `settings.xml` mirror).
- **Build metadata.** Fail the build if an `SCM_*` value is missing (Maven Enforcer) and publish
  signed build provenance (SLSA). Here, local builds leave `${env.SCM_*}` as text in the manifest.
- ...
