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
| R-1 | Pipeline written from scratch, in Groovy | Declarative `Jenkinsfile` | D-007 | Job runs green | Planned |
| R-2 | Trigger from SCM change | GitHub webhook → smee.io → Generic Webhook Trigger (defined in Job DSL), `main` only | D-002 | `git push` starts a build with no manual action | Planned |
| R-3 | Build an artifact | `./mvnw compile test` on the agent | D-003, D-005, D-008 | Test results in the build log | In progress (local build on the agent image passes) |
| R-4 | Pack the artifact | `./mvnw package` → `hello-app-1.0.<build>.jar` | D-003, D-009 | Jar created in the workspace | In progress (local build on the agent image passes) |
| R-5 | Upload to repo | `./mvnw deploy` → Nexus `maven-releases`, dedicated deploy user | D-003, D-010, D-011, D-012 | Jar + POM visible in Nexus with the build version | In progress (manual `mvnw -s settings.xml deploy` uploads jar + POM to Nexus) |
| R-6 | Use Groovy Shared Libraries | Global Pipeline Library in `shared-library/`, loaded with `@Library` + `libraryPath` | D-001 | `Loading library tase-shared-lib` in the build log | In progress (library configured by JCasC) |
| R-7 | Create a function called `prepareEnv` | `shared-library/vars/prepareEnv.groovy` | D-001 | Called in the Prepare stage | Planned |
| R-8 | `prepareEnv` passes SCM trigger parameters into the pipeline (e.g. the committer) | Webhook payload → 7 `SCM_*` env vars (git fallback on manual run); build description; 6 fields in `MANIFEST.MF` | D-002, D-003, D-004 | Prepare log shows the values; build history shows `<sha> by <committer>`; `unzip -p hello-app-1.0.<build>.jar META-INF/MANIFEST.MF` shows the `SCM-*` entries | Planned |

## Interpretations

The ambiguous parts of the task text and the chosen interpretation are recorded in
[DECISIONS.md — D-003](DECISIONS.md#d-003-interpretation-of-the-task-wording).
