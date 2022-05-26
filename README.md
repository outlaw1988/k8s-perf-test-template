# Kubernetes

## Running cluster's dashboard

[k8s dashboard repo](https://github.com/kubernetes/dashboard)

```sh
# Create pods
kubectl apply -f k8s-dashboard/dashboard.yaml
kubectl apply -f k8s-dashboard/auth.yaml

# Listen on localhost:8001
kubectl proxy

# Generate token
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
```

- Copy token to notepad
- Visit [dashboard](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/) and paste token to log in

## Initializing pods

```sh
kubectl create -R -f resources/
```

## Grafana

`username:` admin

`password:` XhXUdmQ576H6e7

## Running test

```sh
./run_test.sh -j <filename.jmx> -n <namespace> -c -m -i <slaves_number> -r
# (c) - csv flag
# (m) - flag dedicated for copying test fragment
# (r) - generate report after test
```

## Stopping test

```sh
./stop_test.sh
```

## HTML report

```sh
# If a master pod is not available, create one
kubectl apply -f resources/jmeter/jmeter-master.yaml
# Wait for the pod is Running, then
kubectl cp -n <namespace> <master-pod-id>:/report/<result_tag> result/<result_tag>
# To copy the content of the report from the pod to your local
```

## Performance test script

You need to put your JMeter project inside the `scenario` folder, inside a folder named after the JMX (without the extension).
Put your CSV file inside the `dataset` folder, child of `scenario`
Put your JMeter modules (include controllers) inside the `module` folder, child of `scenario`

`dataset` and `module`are in `scenario` and not below inside the `<project>` folder because, in some cases, you can have multiple JMeter projects that are sharing the JMeter modules (that's the goal of using modules after all).


*Below a visual representation of the file structure*

```bash
+-- scenario
|   +-- dataset
|   +-- module
|   +-- my-scenario
|       +-- my-scenario.jmx
|       +-- .env
```

In order to change test parameters, please edit `.env` file

## Deployment

### Google Cloud Platform

**Prerequisites**

Cluster with nodes shall be created on Google Cloud Platform account

**Connection with cluster**

[tutorial](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl)

```sh
# Get current cluster info
kubectl config current-context
 
# Connect with cluster
gcloud container clusters get-credentials <CLUSTER_NAME>
```

**Grafana**

Please visit grafana's service external endpoint and log in using provided credentials.

### Minikube (local machine cluster)

**Running minikube cluster**

```sh
minikube start --driver <DRIVER> --memory <RAM_AMOUNT_MB> --cpus <CPUS_NUMBER>
# DRIVER: hyperv, docker
```

**Grafana**

```sh
# Port forwarding
kubectl port-forward <grafana_pod_id> 3000
```

Please visit [localhost:3000](http://localhost:3000) and log in using provided credentials.

## References

[Good tutorial](https://faun.pub/ultimate-jmeter-kubernetes-starter-kit-7eb1a823649b)

[Tutorial repo](https://github.com/Rbillon59/jmeter-k8s-starterkit)