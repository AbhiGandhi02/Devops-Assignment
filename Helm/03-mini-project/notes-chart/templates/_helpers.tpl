{{/* Common labels used on every object */}}
{{- define "notes.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.app.environment }}
{{- end -}}

{{- define "notes.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end -}}
