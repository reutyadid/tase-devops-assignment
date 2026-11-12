// Job DSL: the pipeline job for task 1. Run by JCasC (`jobs:` in casc.yaml) on every start (D-007).
// The job reads the Jenkinsfile from GitHub, branch main.
pipelineJob('hello-app') {
    description('Task 1: build, pack and upload hello-app to Nexus. Created by Job DSL - do not edit in the UI.')

    // GitHub push webhook -> smee -> Generic Webhook Trigger (D-002).
    // Each JSONPath value becomes an env var that prepareEnv reads (D-004).
    triggers {
        genericTrigger {
            genericVariables {
                genericVariable { key('WEBHOOK_REF');       value('$.ref') }
                genericVariable { key('WEBHOOK_AFTER');     value('$.after') }
                genericVariable { key('WEBHOOK_COMMITTER'); value('$.head_commit.committer.name') }
                genericVariable { key('WEBHOOK_AUTHOR');    value('$.head_commit.author.name') }
                genericVariable { key('WEBHOOK_PUSHER');    value('$.pusher.name') }
                genericVariable { key('WEBHOOK_REPO');      value('$.repository.full_name') }
                genericVariable { key('WEBHOOK_MESSAGE');   value('$.head_commit.message') }
            }
            // Only jobs with this token are triggered (Secret text credential from JCasC).
            tokenCredentialId('gwt-token')
            // Build only pushes to main, and not a branch deletion (after = 40 zeros).
            regexpFilterText('$WEBHOOK_REF $WEBHOOK_AFTER')
            regexpFilterExpression('^refs/heads/main (?!0{40})[0-9a-f]{40}$')
            causeString('Push to main by $WEBHOOK_PUSHER')
            // Do not write the payload to the log; prepareEnv prints the values it uses.
            printPostContent(false)
            printContributedVariables(false)
            silentResponse(false)
        }
    }
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(System.getenv('GIT_REPO_URL'))
                    }
                    branch('*/main')
                }
            }
            scriptPath('1-jenkins-pipeline/Jenkinsfile')
            // Read only the Jenkinsfile first; the full checkout happens on the agent.
            lightweight(true)
        }
    }
}
