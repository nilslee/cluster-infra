pipeline {
    agent any
    triggers {
        pollSCM('H/5 * * * *')
        cron('H/15 * * * *')
    }
    environment {
        CONTAINER_NAME  = 'mcp-server'
        IMAGE_NAME      = 'mcp-server:latest'
        MCP_PORT            = '9000'
        PGADMIN_PORT        = '8090'
        PGADMIN_HOST_PORT   = '8090'
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
                    set -e

                    # mcp-server depends_on db; pgadmin is not a dependency of mcp-server — list it explicitly so it runs.
                    # Force-recreate app + GUI only; leave db volume/data intact.
                    if ! docker compose up -d --force-recreate mcp-server pgadmin; then
                        echo "ERROR: docker compose up failed"
                        echo "=== docker compose ps -a ==="
                        docker compose ps -a 2>&1 || true
                        echo "=== docker compose logs (all services, tail 150) ==="
                        docker compose logs --no-color --tail=150 2>&1 || true
                        exit 1
                    fi
                '''
            }
        }
        stage('Health Check') {
            steps {
                // Wait for mcp-server (Spring actuator), Postgres (pg_isready in db container), pgAdmin (/misc/ping).
                sh '''
                    set -u
                    echo "Waiting for mcp-server, postgres (db), and pgadmin to become healthy..."
                    for i in $(seq 1 24); do
                        mcp_ok=0
                        pg_ok=0
                        pga_ok=0

                        if curl -sf --max-time 5 "http://127.0.0.1:${MCP_PORT}/actuator/health" > /dev/null 2>&1; then
                            mcp_ok=1
                        fi
                        if docker compose exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > /dev/null 2>&1; then
                            pg_ok=1
                        fi
                        if curl -sf --max-time 5 "http://127.0.0.1:${PGADMIN_PORT}/misc/ping" > /dev/null 2>&1; then
                            pga_ok=1
                        fi

                        if [ "$mcp_ok" = 1 ] && [ "$pg_ok" = 1 ] && [ "$pga_ok" = 1 ]; then
                            echo "All checks passed: mcp-server actuator, postgres pg_isready, pgadmin /misc/ping"
                            exit 0
                        fi

                        echo "  attempt ${i}/24: mcp_server=${mcp_ok} postgres=${pg_ok} pgadmin=${pga_ok} (sleep 5s)"
                        sleep 5
                    done

                    echo "ERROR: stack not healthy within ~120s (see flags above: 1=ok)"
                    echo "=== docker compose ps -a ==="
                    docker compose ps -a 2>&1 || true
                    echo "=== docker compose logs (db, tail 120) ==="
                    docker compose logs --no-color --tail=120 db 2>&1 || true
                    echo "=== docker compose logs (mcp-server, tail 200) ==="
                    docker compose logs --no-color --tail=200 mcp-server 2>&1 || true
                    echo "=== docker compose logs (pgadmin, tail 120) ==="
                    docker compose logs --no-color --tail=120 pgadmin 2>&1 || true
                    echo "=== docker logs ${CONTAINER_NAME} (fallback) ==="
                    docker logs "${CONTAINER_NAME}" --tail 200 2>&1 || true
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
            echo "  pgAdmin      : http://192.168.56.10:${PGADMIN_PORT}"
        }
        failure {
            // post {} runs outside the main agent workspace — sh needs node { } for FilePath context
            script {
                node {
                    def ws = env.WORKSPACE ?: ''
                    def cname = env.CONTAINER_NAME ?: 'mcp-server'
                    sh """
                        set +e
                        echo "========== MCP deploy failure — diagnostics =========="
                        echo "=== docker logs ${cname} (tail 200) ==="
                        docker logs "${cname}" --tail 200 2>&1 || true
                        if [ -n '${ws}' ] && { [ -f '${ws}/compose.yaml' ] || [ -f '${ws}/docker-compose.yml' ]; }; then
                          cd '${ws}'
                          echo "=== docker compose ps -a ==="
                          docker compose ps -a 2>&1 || true
                          echo "=== docker compose logs (all services, tail 250) ==="
                          docker compose logs --no-color --tail=250 2>&1 || true
                        else
                          echo "(Skipping compose: no WORKSPACE or no compose.yaml at job root — failure may be before k8s-lab-mcp checkout.)"
                        fi
                        echo "================================================================"
                    """
                }
            }
            echo "MCP server deployment failed. Logs printed above where applicable."
        }
    }
}
