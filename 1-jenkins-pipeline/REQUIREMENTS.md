# Requirements — Task 1: Jenkins pipeline

## Assignment text (verbatim)

> Groovy
> Write a pipeline from scratch that will do the following:
> Trigger from SCM change -> build an artifact -> pack the artifact and upload to repo.
> Please use Groovy Shared-Libraries and create a function called prepareEnv. This function
> should be able to pass SCM trigger parameters into the groovy pipeline (for example, who
> was the code committer in the SCM)

## Requirements matrix

| ID  | Requirement (from the task text) | Implementation | Decision | How to verify | Status |
|-----|----------------------------------|----------------|----------|---------------|--------|
| R-1 | Pipeline written from scratch, in Groovy | Declarative `Jenkinsfile` | D-007 | Job runs green | Done (clean run from README: manual build #1 and webhook build #2, SUCCESS) |
| R-2 | Trigger from SCM change | GitHub webhook → smee.io → Generic Webhook Trigger (defined in Job DSL), `main` only | D-002 | `git push` starts a build with no manual action | Done (clean run: real push → build #2, cause `Push to main by reutyadid`) |
| R-3 | Build an artifact | `./mvnw clean test` on the agent | D-003, D-005, D-008 | Test results in the build log | Done (clean run #2: `Tests run: 1, Failures: 0`) |
| R-4 | Pack the artifact | `./mvnw package` → `hello-app-1.0.<build>.jar` | D-003, D-009 | Jar created in the workspace | Done (clean run #2: `hello-app-1.0.2.jar`) |
| R-5 | Upload to repo | `./mvnw deploy` → Nexus `maven-releases`, dedicated deploy user | D-003, D-010, D-011, D-012 | Jar + POM visible in Nexus with the build version | Done (clean run #2: jar + POM `1.0.2` in Nexus, uploader `jenkins-deploy`; password masked) |
| R-6 | Use Groovy Shared Libraries | Global Pipeline Library in `shared-library/`, loaded with `@Library` + `libraryPath` | D-001 | `Loading library tase-shared-lib` in the build log | Done (clean run: `Loading library tase-shared-lib@main`) |
| R-7 | Create a function called `prepareEnv` | `shared-library/vars/prepareEnv.groovy` | D-001 | Called in the Prepare stage | Done (clean run #1 and #2) |
| R-8 | `prepareEnv` passes SCM trigger parameters into the pipeline (e.g. the committer) | Webhook payload → 7 `SCM_*` env vars (git fallback on manual run); build description; 6 fields in `MANIFEST.MF` | D-002, D-003, D-004 | Webhook run (push to `main`): Prepare log shows `source: webhook`, `SCM_PUSHER=<GitHub user>`; build history and manifest as below. Manual run: Prepare log shows `source: git (manual run)`, `SCM_BRANCH=main`, `SCM_COMMITTER=<your name>`, `SCM_PUSHER=manual`, `SCM_REPO=<owner>/<repo>`; build history shows `<short sha> by <committer>`; `unzip -p hello-app-1.0.<build>.jar META-INF/MANIFEST.MF` shows the same `SCM-*` values | Done (clean run: manual #1 values from git, `SCM_PUSHER=manual`; webhook #2 values from the payload, `SCM_PUSHER=reutyadid`; same values in the jar manifest from Nexus) |

## Interpretations

The ambiguous parts of the task text and the chosen interpretation are recorded in
[DECISIONS.md — D-003](DECISIONS.md#d-003-interpretation-of-the-task-wording).
