pipelineJob('my-redis') {
    definition {
        cps {
            script(readFileFromWorkspace('/jenkins/pipelines/my-redis.Jenkinsfile'))
            sandbox(true)
        }
    }
    triggers {
        scm('H/2 * * * *')
    }
}

pipelineJob('redis-gui-tester') {
    definition {
        cps {
            script(readFileFromWorkspace('/jenkins/pipelines/redis-gui-tester.Jenkinsfile'))
            sandbox(true)
        }
    }
    triggers {
        scm('H/2 * * * *')
    }
}

pipelineJob('mcp-server') {
    definition {
        cps {
            script(readFileFromWorkspace('/jenkins/pipelines/mcp-server.Jenkinsfile'))
            sandbox(true)
        }
    }
    triggers {
        scm('H/5 * * * *')
    }
}
