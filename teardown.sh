#!/bin/sh
# Delete both minikube profiles used by this reproducer.
minikube delete -p mc-1
minikube delete -p mc-2
echo "==> Deleted profiles mc-1 and mc-2."
