#!/bin/bash
export KUBECONFIG="/root/repos/regional-dr-example/artifacts/cluster1/kubeconfig"
if oc api-resources 2>/dev/null | grep -q "operatorpolicies"; then
  echo "available"
else
  echo "unavailable"
fi
