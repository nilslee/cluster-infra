pipeline {
    agent any
    environment {
        REGISTRY    = '192.168.56.10:5000'
        APP         = 'redis-gui-tester'
        INFRA_CREDS = credentials('github-pat')
    }
    stages {
        stage('Checkout') {
            steps {
                git url: "https://github.com/aaronlee232/${APP}.git", branch: 'main'
            }
        }
        stage('Build and Push') {
            steps {
                script {
                    def tag = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                    sh "docker build -t ${REGISTRY}/${APP}:${tag} ."
                    sh "docker push ${REGISTRY}/${APP}:${tag}"
                    env.IMAGE_TAG = tag
                }
            }
        }
        stage('Promote via GitOps') {
            steps {
                sh """
                    rm -rf /tmp/cluster-infra
                    git clone https://x-access-token:${INFRA_CREDS_PSW}@github.com/aaronlee232/cluster-infra.git /tmp/cluster-infra
                    cd /tmp/cluster-infra/k8s/apps/${APP}
                    kustomize edit set image ${APP}=${REGISTRY}/${APP}:${IMAGE_TAG}
                    git config user.email 'ci@k8s-lab'
                    git config user.name 'k8s-lab CI'
                    git add kustomization.yaml
                    git commit -m 'promote ${APP} to ${IMAGE_TAG}'
                    git push
                """
            }
        }
    }
    post {
        success {
            echo "redis-gui-tester promoted to ${IMAGE_TAG}. ArgoCD will sync shortly."
        }
        failure {
            echo "Pipeline failed. Check the build log above for details."
        }
    }
}
