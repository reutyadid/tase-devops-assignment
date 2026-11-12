// Job DSL: the pipeline job for task 1. Run by JCasC (`jobs:` in casc.yaml) on every start (D-007).
// The job reads the Jenkinsfile from GitHub, branch main.
pipelineJob('hello-app') {
    description('Task 1: build, pack and upload hello-app to Nexus. Created by Job DSL - do not edit in the UI.')
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
