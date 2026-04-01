pipelineJob('my-redis') {
    definition {
        cps {
            script(new File('/jenkins/pipelines/my-redis.Jenkinsfile').text)
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
            script(new File('/jenkins/pipelines/redis-gui-tester.Jenkinsfile').text)
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
            script(new File('/jenkins/pipelines/mcp-server.Jenkinsfile').text)
            sandbox(true)
        }
    }
    triggers {
        scm('H/2 * * * *')
    }
}
