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
    GIT_BRANCH_NAME = 'main'
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
                apk add --no-cache git >/dev/null
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
              env.GIT_COMMIT_SHORT = sh(
                script: "git rev-parse --short HEAD",
                returnStdout: true
              ).trim()

              env.IMAGE_TAG = "build-${env.BUILD_NUMBER}-${env.GIT_COMMIT_SHORT}"
              env.IMAGE_URI = "${env.IMAGE_REPOSITORY}:${env.IMAGE_TAG}"

              echo "Image tag: ${env.IMAGE_TAG}"
              echo "Image URI: ${env.IMAGE_URI}"
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
                --destination "${IMAGE_URI}" \
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
              apk add --no-cache yq >/dev/null

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
                apk add --no-cache git yq >/dev/null

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
                  git fetch origin "${GIT_BRANCH_NAME}"
                  git checkout -B "${GIT_BRANCH_NAME}" "origin/${GIT_BRANCH_NAME}"

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
                git push origin HEAD:"${GIT_BRANCH_NAME}"
              '''
            }
          }
        }
      }
    }
  }

  post {
    success {
      script {
        if (env.SKIP_PIPELINE == 'true') {
          echo "Pipeline skipped for Jenkins GitOps deploy commit. No Slack notification sent."
        } else {
          container('tools') {
            dir("${WORKSPACE}") {
              withCredentials([string(credentialsId: 'slack-webhook-url', variable: 'SLACK_WEBHOOK_URL')]) {
                sh '''
                  apk add --no-cache curl >/dev/null

                  cat > /tmp/slack-payload.json <<EOF
{
  "text": ":white_check_mark: *Jenkins GitOps deployment succeeded*\\n*Job:* ${JOB_NAME}\\n*Build:* #${BUILD_NUMBER}\\n*Branch:* ${GIT_BRANCH_NAME}\\n*Commit:* ${GIT_COMMIT_SHORT}\\n*Image:* ${IMAGE_URI}\\n*Argo CD App:* gitops-demo-app\\n*App URL:* http://myapp.127.0.0.1.nip.io\\n*Build URL:* ${BUILD_URL}"
}
EOF

                  curl -sS -X POST \
                    -H 'Content-type: application/json' \
                    --data @/tmp/slack-payload.json \
                    "${SLACK_WEBHOOK_URL}" || true
                '''
              }
            }
          }
        }
      }
    }

    failure {
      script {
        container('tools') {
          dir("${WORKSPACE}") {
            withCredentials([string(credentialsId: 'slack-webhook-url', variable: 'SLACK_WEBHOOK_URL')]) {
              sh '''
                apk add --no-cache curl >/dev/null

                IMAGE_VALUE="${IMAGE_URI:-not-created-yet}"
                COMMIT_VALUE="${GIT_COMMIT_SHORT:-unknown}"

                cat > /tmp/slack-payload.json <<EOF
{
  "text": ":x: *Jenkins GitOps pipeline failed*\\n*Job:* ${JOB_NAME}\\n*Build:* #${BUILD_NUMBER}\\n*Branch:* ${GIT_BRANCH_NAME}\\n*Commit:* ${COMMIT_VALUE}\\n*Image:* ${IMAGE_VALUE}\\n*Build URL:* ${BUILD_URL}"
}
EOF

                curl -sS -X POST \
                  -H 'Content-type: application/json' \
                  --data @/tmp/slack-payload.json \
                  "${SLACK_WEBHOOK_URL}" || true
              '''
            }
          }
        }
      }
    }
  }
}