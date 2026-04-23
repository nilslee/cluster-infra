pipeline {
    agent any
    triggers {
        pollSCM('H/5 * * * *')
        cron('H/15 * * * *')
    }
    environment {
        CONTAINER_NAME  = 'mcp-server'
        IMAGE_NAME      = 'mcp-server:latest'
        MCP_PORT        = '9000'
        KUBECONFIG_PATH = '/vagrant/kubeconfig'
        GRAFANA_LOKI    = credentials('mcp-grafana-loki')
        POSTGRES        = credentials('mcp-postgres')
    }
    stages {
        stage('Preflight -- Kubeconfig') {
            steps {
                // Fail fast if the kubeconfig hasn't been written by k3s-master yet
                sh '''
                    if [ ! -f "${KUBECONFIG_PATH}" ]; then
                        echo "ERROR: ${KUBECONFIG_PATH} not found. Is the k3s cluster up?"
                        exit 1
                    fi
                '''
            }
        }
        stage('Checkout') {
            steps {
                git url: 'https://github.com/nilslee/k8s-lab-mcp.git', branch: 'main', credentialsId: 'github-pat'
            }
        }
        stage('Test') {
            agent {
                docker {
                    image 'maven:3-eclipse-temurin-25'
                    reuseNode true
                }
            }
            steps {
                sh 'mvn -B -Dmaven.repo.local="${WORKSPACE}/.m2" test'
            }
            post {
                always {
                    // Record the results even if tests fail
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }
        stage('Build Image') {
            steps {
                sh "docker build -t ${IMAGE_NAME} ."
            }
        }
        stage('Deploy Stack') {
            steps {
                sh '''
                    # Remove any legacy standalone container (no-op on subsequent runs)
                    docker stop ${CONTAINER_NAME} 2>/dev/null || true
                    docker rm   ${CONTAINER_NAME} 2>/dev/null || true

                    # Bring up full stack; force-recreate only mcp-server to avoid
                    # disrupting postgres/pgadmin between deploys (db creds: compose.yaml + POSTGRES_* env from Jenkins)
                    docker compose up -d --force-recreate mcp-server
                '''
            }
        }
        stage('Health Check') {
            steps {
                // Retry for up to 60 seconds waiting for Spring Boot actuator health endpoint
                sh '''
                    echo "Waiting for MCP server to become healthy..."
                    for i in $(seq 1 12); do
                        if curl -sf http://localhost:${MCP_PORT}/actuator/health > /dev/null 2>&1; then
                            echo "MCP server is healthy"
                            exit 0
                        fi
                        sleep 5
                    done
                    echo "ERROR: MCP server did not become healthy within 60 seconds"
                    docker logs ${CONTAINER_NAME} --tail 30
                    exit 1
                '''
            }
        }
    }
    post {
        success {
            echo "MCP server deployed successfully."
            echo "  Health check : http://192.168.56.10:${MCP_PORT}/actuator/health"
            echo "  MCP endpoint : http://192.168.56.10:${MCP_PORT}/mcp"
            echo "  pgAdmin      : http://192.168.56.10:8080"
        }
        failure {
            echo "MCP server deployment failed. Check docker logs mcp-server for details."
        }
    }
}
