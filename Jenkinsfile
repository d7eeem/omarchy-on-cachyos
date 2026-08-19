// Jenkins port of .github/workflows/lint.yml — runs on the docker-host agent.
pipeline {
  agent { label 'docker' }

  options {
    disableConcurrentBuilds(abortPrevious: true)
  }

  stages {
    stage('Bash syntax check') {
      steps {
        sh '''
          set -e
          for f in bin/*.sh; do
            bash -n "$f"
            echo "OK: $f"
          done
        '''
      }
    }

    stage('ShellCheck') {
      steps {
        sh 'shellcheck --severity=error bin/*.sh'
      }
    }
  }
}
