pipeline {
    agent any
    stages {
        stage('Seed') {
            steps {
                jobDsl targets: 'jenkins/seed_jobs.groovy',
                       removedJobAction: 'DELETE',
                       removedViewAction: 'DELETE',
                       lookupStrategy: 'SEED_JOB',
                       sandbox: true
            }
        }
    }
}
