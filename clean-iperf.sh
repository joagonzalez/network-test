#!/bin/bash
# cleanup-iperf.sh

# Delete pods with force
echo "Force deleting iperf3 pods..."
kubectl delete pods,svc -n argocd -l "app in (iperf3-server, iperf3-client)" --force --grace-period=0 --wait=false

# Remove finalizers from any stuck pods
echo "Removing finalizers from stuck pods..."
kubectl get pods -n argocd | grep ^iperf3- | awk '{print $1}' | while read pod; do
  echo "Removing finalizers from $pod"
  kubectl patch pod $pod -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge
done

# Final force delete
echo "Final cleanup..."
kubectl delete pods -n argocd $(kubectl get pods -n argocd | grep ^iperf3- | awk '{print $1}') --force --grace-period=0

# Verify
echo "Verifying cleanup..."
REMAINING=$(kubectl get pods -n argocd | grep ^iperf3- | wc -l)
if [ $REMAINING -eq 0 ]; then
  echo "All iperf3 pods successfully removed"
else
  echo "Warning: $REMAINING iperf3 pods still remain"
fi
