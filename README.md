To use this setup:

1. Replace `<your-git-repo-url>` with your Git repository URL
2. Replace `<node1-hostname>` and `<node2-hostname>` with your actual node hostnames
3. Apply the ArgoCD application:
```bash
kubectl apply -f network-test-app.yaml
```

4. Access Grafana:
```bash
kubectl port-forward svc/grafana -n network-tests 3000:3000
```

The workflow will:
1. Run a 10 Mbps bandwidth test for 60 seconds
2. Run a 100 Mbps bandwidth test for 60 seconds
3. Run a 1 Gbps bandwidth test for 60 seconds

Each test will:
- Deploy an iperf3 server on node1
- Run an iperf3 client on node2
- Collect metrics and store them in Prometheus
- Display results in Grafana

The results will be visible in the Grafana dashboard, showing the bandwidth measurements for each test phase.
