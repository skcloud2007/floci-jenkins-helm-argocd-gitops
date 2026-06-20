{{- define "myapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "myapp.fullname" -}}
{{- printf "%s" (include "myapp.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "myapp.labels" -}}
{{ include "myapp.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: floci-jenkins-helm-argocd-gitops
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
