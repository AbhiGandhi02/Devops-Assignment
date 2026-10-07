{{- define "readtrack.fullname" -}}
{{- .Release.Name | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{- define "readtrack.labels" -}}
app.kubernetes.io/part-of: readtrack
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
environment: {{ .Values.global.environment }}
{{- end -}}

{{/* selector labels: <component> is backend | frontend | postgres */}}
{{- define "readtrack.selector" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{- define "readtrack.secretName" -}}
{{- default (printf "%s-db" (include "readtrack.fullname" .)) .Values.database.existingSecret -}}
{{- end -}}

{{- define "readtrack.podSecurity" -}}
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
{{- end -}}

{{- define "readtrack.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
{{- end -}}
