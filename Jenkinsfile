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
    ENVIRONMENT_NAME = 'local-kind'
    ARGOCD_APP = 'gitops-demo-app'
    APP_URL = 'http://myapp.127.0.0.1.nip.io'
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

              env.LAST_COMMIT_MESSAGE = sh(
                script: "git log -1 --pretty=%s",
                returnStdout: true
              ).trim()

              env.COMMIT_AUTHOR = sh(
                script: "git log -1 --pretty=%an",
                returnStdout: true
              ).trim()

              echo "Last commit message: ${env.LAST_COMMIT_MESSAGE}"
              echo "Commit author: ${env.COMMIT_AUTHOR}"

              if (env.LAST_COMMIT_MESSAGE.startsWith("ci: deploy") || env.LAST_COMMIT_MESSAGE.contains("[skip ci]")) {
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
  "text": "Jenkins GitOps deployment succeeded for ${APP_NAME}. Image: ${IMAGE_URI}",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "✅ Jenkins GitOps Deployment Succeeded",
        "emoji": true
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*${APP_NAME}* was successfully built, pushed, committed to GitOps, and handed off to Argo CD."
      }
    },
    {
      "type": "divider"
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Environment:*\\n${ENVIRONMENT_NAME}"
        },
        {
          "type": "mrkdwn",
          "text": "*Status:*\\nSucceeded"
        },
        {
          "type": "mrkdwn",
          "text": "*Branch:*\\n${GIT_BRANCH_NAME}"
        },
        {
          "type": "mrkdwn",
          "text": "*Build:*\\n#${BUILD_NUMBER}"
        },
        {
          "type": "mrkdwn",
          "text": "*Commit:*\\n${GIT_COMMIT_SHORT}"
        },
        {
          "type": "mrkdwn",
          "text": "*Author:*\\n${COMMIT_AUTHOR}"
        },
        {
          "type": "mrkdwn",
          "text": "*Argo CD App:*\\n${ARGOCD_APP}"
        },
        {
          "type": "mrkdwn",
          "text": "*Registry:*\\nFloci ECR local"
        }
      ]
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*New Image:*\\n`${IMAGE_URI}`"
      }
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "*Pipeline:* ${JOB_NAME} • *GitOps commit pushed to:* ${GIT_BRANCH_NAME}"
        }
      ]
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "style": "primary",
          "text": {
            "type": "plain_text",
            "text": "Open Jenkins Build",
            "emoji": true
          },
          "url": "${BUILD_URL}"
        },
        {
          "type": "button",
          "text": {
            "type": "plain_text",
            "text": "Open Application",
            "emoji": true
          },
          "url": "${APP_URL}"
        }
      ]
    }
  ]
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
                AUTHOR_VALUE="${COMMIT_AUTHOR:-unknown}"
                MESSAGE_VALUE="${LAST_COMMIT_MESSAGE:-unknown}"

                cat > /tmp/slack-payload.json <<EOF
{
  "text": "Jenkins GitOps pipeline failed for ${APP_NAME}. Build: #${BUILD_NUMBER}",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "❌ Jenkins GitOps Deployment Failed",
        "emoji": true
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*${APP_NAME}* pipeline execution failed. Review the Jenkins build logs for details."
      }
    },
    {
      "type": "divider"
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Environment:*\\n${ENVIRONMENT_NAME}"
        },
        {
          "type": "mrkdwn",
          "text": "*Status:*\\nFailed"
        },
        {
          "type": "mrkdwn",
          "text": "*Branch:*\\n${GIT_BRANCH_NAME}"
        },
        {
          "type": "mrkdwn",
          "text": "*Build:*\\n#${BUILD_NUMBER}"
        },
        {
          "type": "mrkdwn",
          "text": "*Commit:*\\n${COMMIT_VALUE}"
        },
        {
          "type": "mrkdwn",
          "text": "*Author:*\\n${AUTHOR_VALUE}"
        },
        {
          "type": "mrkdwn",
          "text": "*Image:*\\n${IMAGE_VALUE}"
        },
        {
          "type": "mrkdwn",
          "text": "*Argo CD App:*\\n${ARGOCD_APP}"
        }
      ]
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Last Commit Message:*\\n`${MESSAGE_VALUE}`"
      }
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "style": "danger",
          "text": {
            "type": "plain_text",
            "text": "Open Jenkins Build",
            "emoji": true
          },
          "url": "${BUILD_URL}"
        }
      ]
    }
  ]
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