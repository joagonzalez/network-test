Looking at your workflow, the issue might be in the `kubectl wait` command in the iperf3-client-step. The workflow is waiting for pods to reach a "complete" condition, but this condition might never be met. Let's analyze and fix this:

1. Current problematic part in the workflow:
```yaml
# Wait for all tests to complete
echo "Waiting for all tests to complete..."
kubectl wait --for=condition=complete pod -l test-type=iperf3-client -n argocd --timeout=300s || true
```

2. The issue occurs because:
- The `complete` condition isn't a standard pod condition
- The `|| true` makes the command always succeed even if waiting fails
- There's no guarantee that pods will terminate properly

Here's how to fix it:

```yaml
- name: iperf3-client-step
  inputs:
    parameters:
      - name: bandwidth
      - name: test-name
      - name: client-nodes
      - name: server-nodes
      - name: test-duration
  script:
    image: bitnami/kubectl
    command: [bash]
    source: |
      set -ex

      # Generate test pairs
      CLIENTS=$(echo '{{inputs.parameters.client-nodes}}' | jq -r '.[]')
      SERVERS=$(echo '{{inputs.parameters.server-nodes}}' | jq -r '.[]')

      # Create all client pods
      for CLIENT in $CLIENTS; do
        for SERVER in $SERVERS; do
          TEST_NAME="iperf3-client-{{inputs.parameters.test-name}}-${CLIENT}-to-${SERVER}"
          cat <<EOF | kubectl apply -f -
      # ... pod definition as before ...
EOF
        done
      done

      # Wait for pods to be created
      sleep 10

      # Wait for all pods with specific test name to complete
      echo "Waiting for tests to complete..."
      TOTAL_WAIT=0
      MAX_WAIT=600  # 10 minutes maximum wait time

      while true; do
        RUNNING=$(kubectl get pods -n argocd -l "test-type=iperf3-client,test_name={{inputs.parameters.test-name}}" --no-headers | grep -v "Completed" | wc -l)
        if [ "$RUNNING" -eq 0 ]; then
          echo "All test pods completed"
          break
        fi

        if [ "$TOTAL_WAIT" -ge "$MAX_WAIT" ]; then
          echo "Timeout waiting for pods to complete"
          kubectl get pods -n argocd -l "test-type=iperf3-client,test_name={{inputs.parameters.test-name}}"
          exit 1
        fi

        echo "Still waiting for $RUNNING pods to complete..."
        sleep 30
        TOTAL_WAIT=$((TOTAL_WAIT + 30))
      done

      # Verify results
      FAILED=$(kubectl get pods -n argocd -l "test-type=iperf3-client,test_name={{inputs.parameters.test-name}}" --no-headers | grep -v "Completed" | wc -l)
      if [ "$FAILED" -ne 0 ]; then
        echo "Some tests failed:"
        kubectl get pods -n argocd -l "test-type=iperf3-client,test_name={{inputs.parameters.test-name}}"
        exit 1
      fi
```

Also, ensure the client pods have a proper termination condition by modifying their command:

```yaml
command:
  - /bin/bash
  - -c
  - |
    set -x
    SERVER_POD="iperf3-server-${SERVER}"
    echo "Server pod name: ${SERVER_POD}"

    # ... existing DNS and connectivity checks ...

    # Run test with explicit exit
    echo "Running iperf3 test..."
    if ! iperf3 -c ${SERVER_POD}.argocd.svc.cluster.local \
          -b {{inputs.parameters.bandwidth}} \
          -t {{inputs.parameters.test-duration}} \
          -J > /tmp/iperf_result.json 2>/tmp/iperf_error.log; then
      echo "iperf3 test failed"
      exit 1
    fi

    # ... rest of the command ...

    # Explicitly exit after successful completion
    echo "Test completed successfully"
    exit 0
```

Additional improvements:

1. Add activeDeadlineSeconds to the client pods:
```yaml
spec:
  activeDeadlineSeconds: 3600  # 1 hour maximum runtime
```

2. Add proper termination grace period:
```yaml
spec:
  terminationGracePeriodSeconds: 30
```

3. Add a lifecycle hook:
```yaml
containers:
- name: client
  lifecycle:
    preStop:
      exec:
        command: ["/bin/sh", "-c", "pkill iperf3; sleep 5"]
```

4. Add proper status check in the workflow:
```yaml
- name: verify-test-completion
  template: verify-test-results
  arguments:
    parameters:
    - name: test-name
      value: "{{inputs.parameters.test-name}}"

- name: verify-test-results
  inputs:
    parameters:
    - name: test-name
  script:
    image: bitnami/kubectl
    command: [bash]
    source: |
      set -ex
      FAILED=$(kubectl get pods -n argocd -l "test-type=iperf3-client,test_name={{inputs.parameters.test-name}}" \
               --no-headers | grep -v "Completed" | wc -l)
      if [ "$FAILED" -ne 0 ]; then
        echo "Test failures detected"
        kubectl get pods -n argocd -l "test-type=iperf3-client,test_name={{inputs.parameters.test-name}}"
        exit 1
      fi
```

These changes will:
1. Add proper timeout handling
2. Ensure pods terminate correctly
3. Add explicit success/failure conditions
4. Improve error handling and reporting
5. Add maximum runtime limits
6. Properly clean up resources

The workflow should now complete properly instead of running indefinitely.
