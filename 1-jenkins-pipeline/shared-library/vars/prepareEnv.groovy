// prepareEnv: passes the SCM trigger parameters into the pipeline as SCM_* env vars
// (R-7, R-8, D-004).
//
// Webhook run: Generic Webhook Trigger sets WEBHOOK_* env vars from the GitHub push payload (D-002).
// Manual run:  there is no payload, so the values are read from the git checkout.
//
// Every value is untrusted data from the SCM. It is only stored in env vars and printed with
// `echo`; it is never put into a Groovy-interpolated shell string (D-001).
//
// gitVars: the map returned by the `checkout` step (GIT_COMMIT, GIT_BRANCH, GIT_URL).
def call(Map gitVars) {
    boolean fromWebhook = env.WEBHOOK_AFTER?.trim()

    Map scm
    if (fromWebhook) {
        scm = [
            SCM_BRANCH   : env.WEBHOOK_REF?.replaceFirst('^refs/heads/', ''),
            SCM_COMMIT   : env.WEBHOOK_AFTER,
            SCM_COMMITTER: env.WEBHOOK_COMMITTER,
            SCM_AUTHOR   : env.WEBHOOK_AUTHOR,
            SCM_PUSHER   : env.WEBHOOK_PUSHER,
            SCM_REPO     : env.WEBHOOK_REPO,
            SCM_MESSAGE  : env.WEBHOOK_MESSAGE,
        ]
    } else {
        scm = [
            SCM_BRANCH   : gitVars.GIT_BRANCH?.replaceFirst('^origin/', ''),
            SCM_COMMIT   : gitVars.GIT_COMMIT,
            SCM_COMMITTER: sh(script: 'git log -1 --format=%cn', returnStdout: true).trim(),
            SCM_AUTHOR   : sh(script: 'git log -1 --format=%an', returnStdout: true).trim(),
            SCM_PUSHER   : 'manual',
            SCM_REPO     : gitVars.GIT_URL?.replaceFirst('^https://[^/]+/', '')?.replaceFirst('\\.git$', ''),
            SCM_MESSAGE  : sh(script: 'git log -1 --format=%s', returnStdout: true).trim(),
        ]
    }

    // Without these two, the build cannot say what was built or who committed it (R-8).
    if (!scm.SCM_COMMIT?.trim() || !scm.SCM_COMMITTER?.trim()) {
        error("prepareEnv: SCM_COMMIT or SCM_COMMITTER is empty (source: ${fromWebhook ? 'webhook' : 'git'})")
    }

    scm.each { name, value -> env."${name}" = value ?: '' }

    echo "prepareEnv - source: ${fromWebhook ? 'webhook' : 'git (manual run)'}\n" +
         scm.collect { name, value -> "  ${name}=${value ?: ''}" }.join('\n')

    // Build history: "<short sha> by <committer>". Shown as plain text, no HTML (D-004).
    currentBuild.description = "${scm.SCM_COMMIT.take(7)} by ${scm.SCM_COMMITTER}"
}
