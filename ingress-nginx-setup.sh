#!/usr/bin/env bash
set -euo pipefail

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

release_name="ingress-nginx"
namespace="ingress-nginx"
chart="ingress-nginx/ingress-nginx"

if helm status "$release_name" --namespace "$namespace" >/dev/null 2>&1; then
  helm upgrade "$release_name" "$chart" \
    --namespace "$namespace"
else
  helm install "$release_name" "$chart" \
    --namespace "$namespace" \
    --create-namespace
fi
