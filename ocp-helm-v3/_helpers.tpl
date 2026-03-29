{{/*
Expand the name of the chart.
*/}}
{{- define "k3s.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "k3s.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "k3s.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "-" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
OpenShift-compatible: simple keys, no special chars in values, max 63 chars
*/}}
{{- define "k3s.labels" -}}
app: {{ include "k3s.name" . }}
chart: {{ include "k3s.chart" . }}
release: {{ .Release.Name | trunc 63 | trimSuffix "-" }}
heritage: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
version: {{ .Chart.AppVersion | replace "+" "-" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Selector labels - used for selecting resources.
*/}}
{{- define "k3s.selectorLabels" -}}
app: {{ include "k3s.name" . }}
release: {{ .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Generate cluster token (consistent across template rendering).
Checks if secret already exists to maintain same token on upgrades.
*/}}
{{- define "k3s.clusterToken" -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace (printf "%s-token" .Release.Name) -}}
{{- if $secret -}}
{{- index $secret.data "token" | b64dec -}}
{{- else -}}
{{- randAlphaNum 64 -}}
{{- end -}}
{{- end }}

{{/*
Master node selector labels.
*/}}
{{- define "k3s.masterSelectorLabels" -}}
{{ include "k3s.selectorLabels" . }}
component: master
cluster: {{ .Values.clusterName | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Worker node selector labels.
*/}}
{{- define "k3s.workerSelectorLabels" -}}
{{ include "k3s.selectorLabels" . }}
component: worker
cluster: {{ .Values.clusterName | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Service name for K3s API.
*/}}
{{- define "k3s.serviceName" -}}
{{- printf "%s-k3s-api" .Release.Name -}}
{{- end }}
