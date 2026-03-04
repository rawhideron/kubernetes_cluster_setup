#!/usr/bin/env bash
set -euo pipefail

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

release_name="metrics-server"
namespace="metrics-server"
chart="metrics-server/metrics-server"
args="{--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}"

if helm status "$release_name" --namespace "$namespace" >/dev/null 2>&1; then
  helm upgrade "$release_name" "$chart" \
    --namespace "$namespace" \
    --set args="$args"
else
  helm install "$release_name" "$chart" \
    --namespace "$namespace" \
    --set args="$args"
fi
