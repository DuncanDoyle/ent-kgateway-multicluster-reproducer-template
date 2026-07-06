#!/bin/sh
# Delete both minikube profiles used by this reproducer (full teardown to empty clusters).
# For a lighter reset that keeps the linked mesh and only removes the setup.sh workload/gateway
# layer, use ./teardown.sh instead.
minikube delete -p mc-1
minikube delete -p mc-2
echo "==> Deleted profiles mc-1 and mc-2."
