def infraRepo = 'https://github.com/aaronlee232/cluster-infra.git'

pipelineJob('my-redis') {
    description('Build and promote my-redis to cluster via GitOps')
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(infraRepo)
                        credentials('github-pat')
                    }
                    branch('*/main')
                }
            }
            scriptPath('jenkins/pipelines/my-redis.Jenkinsfile')
            lightweight(true)
        }
    }
}

pipelineJob('redis-gui-tester') {
    description('Build and promote redis-gui-tester to cluster via GitOps')
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(infraRepo)
                        credentials('github-pat')
                    }
                    branch('*/main')
                }
            }
            scriptPath('jenkins/pipelines/redis-gui-tester.Jenkinsfile')
            lightweight(true)
        }
    }
}

pipelineJob('mcp-server') {
    description('Build and deploy MCP server container')
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(infraRepo)
                        credentials('github-pat')
                    }
                    branch('*/main')
                }
            }
            scriptPath('jenkins/pipelines/mcp-server.Jenkinsfile')
            lightweight(true)
        }
    }
}
