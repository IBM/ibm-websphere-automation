#### Example 1: Deploying GA Operator with values overriden
Overrides to accept the license for WebSphereSecure CR
```
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ibm-websphere-automation
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/instance: ibm-websphere-automation
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  destination:
    namespace: websphere-automation
    server: 'https://kubernetes.default.svc'
  source:
    repoURL: 'https://github.com/IBM/ibm-websphere-automation'
    path: gitops-deployment/wsa
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
      valuesObject:
        wsaSecure:
          spec:
            license:
              accept: true
  syncPolicy:
      retry:
        limit: 10
        backoff:
          duration: 5s
          factor: 2
          maxDuration: 1m
  project: default
EOF
```

#### Example 2: Deploying GA operator using pre-confgured values from a values file
Apply the following configuration to accept the license for WebSphereSecure & WebSphereAutomation CRs
```
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ibm-websphere-automation
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/instance: ibm-websphere-automation
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  destination:
    namespace: websphere-automation
    server: 'https://kubernetes.default.svc'
  source:
    repoURL: 'https://github.com/IBM/ibm-websphere-automation'
    path: gitops-deployment/wsa
    targetRevision: main
    helm:
      valueFiles:
        - values.wsa-secure.yaml
  syncPolicy:
      retry:
        limit: 10
        backoff:
          duration: 5s
          factor: 2
          maxDuration: 1m
  project: default
EOF
```