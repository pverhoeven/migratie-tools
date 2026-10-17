{{- define "app.naam" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "app.labels" -}}
app.kubernetes.io/name: {{ include "app.naam" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.naam" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
