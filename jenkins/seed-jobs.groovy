pipelineJob('my-redis') {
    description('Build and promote my-redis to cluster via GitOps')
    definition {
        cps {
            script(readFileFromWorkspace('/jenkins/pipelines/my-redis.Jenkinsfile'))
            sandbox(false)
        }
    }
    triggers {
        pollSCM('H/2 * * * *')
    }
}

pipelineJob('redis-gui-tester') {
    description('Build and promote redis-gui-tester to cluster via GitOps')
    definition {
        cps {
            script(readFileFromWorkspace('/jenkins/pipelines/redis-gui-tester.Jenkinsfile'))
            sandbox(false)
        }
    }
    triggers {
        pollSCM('H/2 * * * *')
    }
}

pipelineJob('mcp-server') {
    description('Build and deploy MCP server container')
    definition {
        cps {
            script(readFileFromWorkspace('/jenkins/pipelines/mcp-server.Jenkinsfile'))
            sandbox(false)
        }
    }
    triggers {
        pollSCM('H/5 * * * *')
    }
}
