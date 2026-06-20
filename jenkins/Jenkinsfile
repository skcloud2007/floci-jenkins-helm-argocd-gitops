pipeline {
  agent {
    kubernetes {
      label 'ci-kaniko-helm'
      defaultContainer 'tools'
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: jenkins-ci-agent
spec:
  restartPolicy: Never
  containers:
    - name: tools
      image: alpine/helm:3.17.0
      command:
        - cat
      tty: true
      securityContext:
        runAsUser: 0
      volumeMounts:
        - name: workspace
          mountPath: /workspace

    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.24.0-debug
      command:
        - /busybox/cat
      tty: true
      env:
        - name: DOCKER_CONFIG
          value: /kaniko/.docker
      volumeMounts:
        - name: kaniko-docker-config
          mountPath: /kaniko/.docker
        - name: workspace
          mountPath: /workspace

  volumes:
    - name: workspace
      emptyDir: {}
    - name: kaniko-docker-config
      configMap:
        name: floci-registry-docker-config
"""
    }
  }

  options {
    skipDefaultCheckout(true)
  }

  environment {
    IMAGE_REPOSITORY = 'host.docker.internal:5100/floci-cicd/gitops-demo-app'
    APP_NAME = 'gitops-demo-app'
    CHART_PATH = 'helm/myapp'
    GITHUB_REPO = 'skcloud2007/floci-jenkins-helm-argocd-gitops'
    GIT_BRANCH = 'main'
    SKIP_PIPELINE = 'false'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Detect CI Deploy Commit') {
      steps {
        container('tools') {
          dir("${WORKSPACE}") {
            script {
              sh '''
                apk add --no-cache git
                git config --global --add safe.directory "${WORKSPACE}"
              '''

              def lastCommitMessage = sh(
                script: "git log -1 --pretty=%s",
                returnStdout: true
              ).trim()

              echo "Last commit message: ${lastCommitMessage}"

              if (lastCommitMessage.startsWith("ci: deploy") || lastCommitMessage.contains("[skip ci]")) {
                env.SKIP_PIPELINE = "true"
                echo "Skipping pipeline because this is Jenkins' own GitOps deployment commit."
              } else {
                env.SKIP_PIPELINE = "false"
                echo "Normal source/config change detected. Pipeline will continue."
              }
            }
          }
        }
      }
    }

    stage('Prepare Tag') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        container('tools') {
          dir("${WORKSPACE}") {
            script {
              def shortCommit = sh(
                script: "git rev-parse --short HEAD",
                returnStdout: true
              ).trim()

              env.IMAGE_TAG = "build-${env.BUILD_NUMBER}-${shortCommit}"
              echo "Image tag: ${env.IMAGE_TAG}"
            }
          }
        }
      }
    }

    stage('Build and Push Image') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        container('kaniko') {
          dir("${WORKSPACE}") {
            sh '''
              /kaniko/executor \
                --context "${WORKSPACE}/app" \
                --dockerfile "${WORKSPACE}/app/Dockerfile" \
                --destination "${IMAGE_REPOSITORY}:${IMAGE_TAG}" \
                --insecure \
                --skip-tls-verify \
                --cache=false
            '''
          }
        }
      }
    }

    stage('Lint Helm Chart') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        container('tools') {
          dir("${WORKSPACE}") {
            sh '''
              helm lint "${CHART_PATH}"
              helm template myapp "${CHART_PATH}" -n myapp
            '''
          }
        }
      }
    }

    stage('Update Helm Values') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        container('tools') {
          dir("${WORKSPACE}") {
            sh '''
              apk add --no-cache yq

              yq -i '.image.tag = strenv(IMAGE_TAG)' helm/myapp/values.yaml

              echo "Updated values.yaml:"
              grep -A 4 '^image:' helm/myapp/values.yaml
            '''
          }
        }
      }
    }

    stage('Commit GitOps Change') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        container('tools') {
          dir("${WORKSPACE}") {
            withCredentials([usernamePassword(credentialsId: 'github-app', usernameVariable: 'GH_APP_ID', passwordVariable: 'GH_APP_TOKEN')]) {
              sh '''
                apk add --no-cache git yq

                echo "Current directory:"
                pwd

                echo "Workspace content:"
                ls -la

                git config --global user.email "jenkins@example.local"
                git config --global user.name "Jenkins CI"
                git config --global --add safe.directory "${WORKSPACE}"

                if [ ! -d .git ]; then
                  echo "No .git directory found. Reinitializing repository metadata."

                  git init
                  git remote add origin "https://x-access-token:${GH_APP_TOKEN}@github.com/${GITHUB_REPO}.git"
                  git fetch origin "${GIT_BRANCH}"
                  git checkout -B "${GIT_BRANCH}" "origin/${GIT_BRANCH}"

                  echo "Reapplying image tag after checkout:"
                  yq -i '.image.tag = strenv(IMAGE_TAG)' helm/myapp/values.yaml
                else
                  echo ".git directory found."
                  git remote set-url origin "https://x-access-token:${GH_APP_TOKEN}@github.com/${GITHUB_REPO}.git"
                fi

                echo "Git status:"
                git status

                if git diff --quiet; then
                  echo "No GitOps changes to commit."
                  exit 0
                fi

                git add helm/myapp/values.yaml
                git commit -m "ci: deploy ${IMAGE_TAG} [skip ci]"
                git push origin HEAD:"${GIT_BRANCH}"
              '''
            }
          }
        }
      }
    }
  }

  post {
    success {
      echo "Pipeline completed successfully."
    }
    failure {
      echo "Pipeline failed. Check Jenkins stage logs."
    }
  }
}
