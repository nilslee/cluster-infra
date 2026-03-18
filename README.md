This is the primary repo for setting up k8s-lab.

## Steps to setup

### 1. Ensure minikube is running

```
minikube start
```

If the cluster is running already, run the following to do a clean restart

```
minikube stop && minikube delete && minikube start
```

### 2. Run bootstrap to set up application repos

This will pull the code base for all applications that will be in the cluster by setting them up as sibling directories.

```
./bootstrap.sh
```

### 3. Run Skaffold

This will the cluster based on the manifests stored in `k8s` directory using `skaffold.yaml`

```
skaffold run
```
