#!/bin/bash
set -ex

# Generate test pairs
CLIENTS=$(echo "$1" | jq -r '.[]')
SERVERS=$(echo "$2" | jq -r '.[]')
TEST_NAME="$3"
TEST_ID="$4"
BANDWIDTH="$5"
TEST_DURATION="$6"

for CLIENT in $CLIENTS; do
  for SERVER in $SERVERS; do
    POD_NAME="iperf3-client-${TEST_NAME}-${CLIENT}-to-${SERVER}"

    # Delete existing pod if it exists
    kubectl delete pod $POD_NAME -n argocd --ignore-not-found

    # Wait a moment for the deletion to complete
    sleep 2

    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: argocd
  labels:
    test-type: iperf3-client
    workflow: iperf3-test
    test-id: "$TEST_ID"
spec:
  nodeSelector:
    kubernetes.io/hostname: "$CLIENT"
  volumes:
    - name: script-volume
      configMap:
        name: iperf3-client-script
        defaultMode: 0777
  containers:
  - name: client
    image: nicolaka/netshoot
    env:
      - name: SERVER
        value: "$SERVER"
      - name: CLIENT
        value: "$CLIENT"
      - name: TEST_NAME
        value: "$TEST_NAME"
      - name: TEST_ID
        value: "$TEST_ID"
      - name: BANDWIDTH
        value: "$BANDWIDTH"
      - name: TEST_DURATION
        value: "$TEST_DURATION"
    command:
      - /scripts/run-test.sh
    volumeMounts:
      - name: script-volume
        mountPath: /scripts
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
  restartPolicy: Never
EOF
  done
done

# Wait for all tests to complete
echo "Waiting for all tests to complete..."
kubectl wait --for=condition=complete pod -l test-type=iperf3-client,test-id=$TEST_ID -n argocd --timeout=300s || true
