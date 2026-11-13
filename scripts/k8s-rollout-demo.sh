#!/usr/bin/env bash
# Requires kubectl on PATH, the local cluster, and both image tags loaded into kind.
set -euo pipefail
mkdir -p docs/evidence
kubectl -n devops-task delete job rollout-probe --ignore-not-found
kubectl apply -f k8s/rollout-probe.yaml
kubectl -n devops-task wait --for=condition=Ready pod -l job-name=rollout-probe --timeout=60s
sleep 2
kubectl -n devops-task set image deployment/app app=devops-observable-service:1.0.1
kubectl -n devops-task rollout status deployment/app --timeout=120s
kubectl -n devops-task rollout undo deployment/app
kubectl -n devops-task rollout status deployment/app --timeout=120s
kubectl -n devops-task wait --for=condition=complete job/rollout-probe --timeout=150s
kubectl -n devops-task logs job/rollout-probe > docs/evidence/kubernetes-requests.txt
kubectl -n devops-task rollout history deployment/app
kubectl -n devops-task get pods,hpa
tail -1 docs/evidence/kubernetes-requests.txt
