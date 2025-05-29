# Deploy IBM WebSphere Automation using GitOps
The use of GitOps enables IBM WebSphere Automation (WSA) to be deployed on a Red Hat OpenShift Container Platform (OCP) Cluster from a Git repository containing the installation manifests. At this time WSA supports OLM based install, with OLM resource manifests represented as a set of Helm Chart templates within a source Git repository.

For more information about GitOps, see [GitOps](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/gitops/index) in the Red Hat OpenShift documentation.

For more information about ArgoCD, see the [ArgoCD documentation](https://argo-cd.readthedocs.io/en/stable/).

## Contents

- [Prerequisites](#prerequisites)
- [Installing OpenShift GitOps](#installing-openshift-gitops)
- [Deploy ArgoCD Applications](#deploy-argocd-applications)
  - [Custom Health Checks](#custom-health-checks)
  - [WSA](#wsa)
- [Sync Applications](#sync-applications)

## Prerequisites

- Ensure the cluster meets the supported platform, sizing, persistent storage, and network requirements indended for WebSphere Automation. For more information, see [System Requirements](https://www.ibm.com/docs/en/ws-automation?topic=installation-system-requirements)

- Prior to deploying WSA application using ArgoCD, make sure to install WSA operator pre-requisites, which include IBM Cloud Pak foundational services, IBM Cert Manager operator, IBM Licensing operator, and ingress network policies. Follow steps from here (https://www.ibm.com/docs/en/ws-automation?topic=automation-installing-websphere-operator-prerequisites) to set up the pre-requisites.

## Installing OpenShift GitOps

Complete the following steps to install the OpenShift GitOps Operator.

1. Create the Operator namespace
    
    ```bash
    oc create ns openshift-gitops-operator
    ```

2. Create the Operator Group and OpenShift GitOps Subscription, wait for `OpenShift GitOps` to roll out under the `openshift-gitops` namespace.

    ```bash
    cat <<EOF | oc apply -f -
    apiVersion: operators.coreos.com/v1
    kind: OperatorGroup
    metadata:
      name: openshift-gitops-operator
      namespace: openshift-gitops-operator
    spec:
      upgradeStrategy: Default
    ---
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: openshift-gitops-operator
      namespace: openshift-gitops-operator
    spec:
      channel: latest
      installPlanApproval: Automatic
      name: openshift-gitops-operator
      source: redhat-operators
      sourceNamespace: openshift-marketplace
    EOF
    ```

3. Creating a `argocd-cluster-admin` ClusterRoleBinding to grant ArgoCD the necessary permissions to manage resources across the OpenShift cluster.

    ```bash
    oc adm policy add-cluster-role-to-user cluster-admin \
        system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller \
        -n openshift-gitops --rolebinding-name=argocd-cluster-admin
    ```

    Alternatively, you can apply the ClusterRoleBinding via YAML:

    ```bash
    cat <<EOF | oc apply -f -
    kind: ClusterRoleBinding
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: argocd-cluster-admin
    subjects:
      - kind: ServiceAccount
        name: openshift-gitops-argocd-application-controller
        namespace: openshift-gitops
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: cluster-admin
    EOF
    ```

4. Access the ArgoCD UI and verify Git Repository Connnectivity.
    
    The ArgoCD URL can be obtained via the `openshift-gitops` namespace route.
    ```
    oc get routes -n openshift-gitops
    ```

    Navigate to that route and login by selecting the OpenShift Login option and providing the clusters credentials.    

## Deploy ArgoCD Applications

### Custom Health Checks

Create the ArgoCD Application for Custom Health Checks:
```
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/instance: argocd
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  destination:
    namespace: default
    server: 'https://kubernetes.default.svc'
  source:
    repoURL: 'https://github.com/IBM/ibm-websphere-automation'
    path: gitops-deployment/argocd
    targetRevision: main
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

### WSA

Create the WSA Application:

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

## Sync Applications

The ArgoCD applications created in the preceding steps should now exist on the ArgoCD Application UI. The applications can be synced via the `SYNC` button; starting with the ArgoCD Application, then WSA.

WSA will enter a `Progressing` state and will remain in that state until WSA is fully installed on the cluster. The final expected state across the applications is one of of `Healthy` / `Synced`.

Following a completed sync, the sync policy within the application can be updated to `Automated` via the App Details view. In this mode, any updates to the installation manifests at the source repository will be automatically synced to the cluster. Values set as overrides via `valuesObject` will continue to take precedence over the values file. 

If WSA is to be later uninstalled, ensure to disable automatic sync before commencing the uninstall.