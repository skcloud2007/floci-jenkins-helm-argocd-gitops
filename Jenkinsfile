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

  environment {
    IMAGE_REPOSITORY = 'host.docker.internal:5100/floci-cicd/gitops-demo-app'
    APP_NAME = 'gitops-demo-app'
    CHART_PATH = 'helm/myapp'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Prepare Tag') {
      steps {
        script {
          env.IMAGE_TAG = "build-${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
          echo "Image tag: ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Build and Push Image') {
      steps {
        container('kaniko') {
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

    stage('Lint Helm Chart') {
      steps {
        container('tools') {
          sh '''
            helm lint "${CHART_PATH}"
            helm template myapp "${CHART_PATH}" -n myapp
          '''
        }
      }
    }

    stage('Update Helm Values') {
      steps {
        container('tools') {
          sh '''
            apk add --no-cache git yq

            yq -i '.image.tag = strenv(IMAGE_TAG)' helm/myapp/values.yaml

            echo "Updated values.yaml:"
            grep -A 4 '^image:' helm/myapp/values.yaml
          '''
        }
      }
    }

    stage('Commit GitOps Change') {
      steps {
        container('tools') {
          withCredentials([usernamePassword(credentialsId: 'github-app', usernameVariable: 'GH_APP_ID', passwordVariable: 'GH_APP_TOKEN')]) {
            sh '''
              git config user.email "jenkins@example.local"
              git config user.name "Jenkins CI"

              git status

              if git diff --quiet; then
                echo "No GitOps changes to commit."
                exit 0
              fi

              git add helm/myapp/values.yaml
              git commit -m "ci: deploy ${IMAGE_TAG}"

              git remote set-url origin "https://x-access-token:${GH_APP_TOKEN}@github.com/skcloud2007/floci-jenkins-helm-argocd-gitops.git"
              git push origin HEAD:main
            '''
          }
        }
      }
    }
  }

  post {
    success {
      echo "Pipeline completed. Argo CD should sync the new image tag automatically."
    }
    failure {
      echo "Pipeline failed. Check Jenkins stage logs."
    }
  }
}
