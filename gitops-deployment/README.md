# Deploy IBM WebSphere Automation using GitOps
The use of GitOps enables IBM WebSphere Automation (WSA) to be deployed on a Red Hat OpenShift Container Platform (OCP) Cluster from a Git repository containing the installation manifests. At this time WSA supports OLM based install, with OLM resource manifests represented as a set of Helm Chart templates within a source Git repository.

For more information about GitOps, see [GitOps](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/gitops/index) in the Red Hat OpenShift documentation.

For more information about ArgoCD, see the [ArgoCD documentation](https://argo-cd.readthedocs.io/en/stable/).

## Contents

- [Prerequisites](#prerequisites)
- [Installing OpenShift GitOps](#installing-openshift-gitops)
  - [GitOps RBAC Requirements](#gitops-application-controller-privilege-requirements)
  - [Deploy ArgoCD Applications](#deploy-argo-cd-applications)
    - [Argo CD Custom Health Checks](#argo-cd-custom-health-checks)
    - [IBM Licensing Service](#ibm-licensing-service)
    - [IBM Cert Manager](#ibm-cert-manager)
    - [IBM WebSphere Automation](#ibm-websphere-automation)
  - [Sync Applications](#sync-applications)
  - [Verify your Installation](#verify-your-installation)
- [Customised Installation](#customized-installation)
- [Known Limitations](#known-limitations)

## Prerequisites

- Ensure the cluster meets the supported platform, sizing, persistent storage, and network requirements indended for WebSphere Automation. For more information, see [System Requirements](https://www.ibm.com/docs/en/ws-automation?topic=installation-system-requirements)

- You must have Red Hat OpenShift GitOps (Argo CD) installed on your Red Hat OpenShift cluster. For more information, see [Installing OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/latest/html/installing_gitops/installing-openshift-gitops) in the Red Hat OpenShift documentation.

## Installing OpenShift GitOps

### GitOps Application Controller Privilege Requirements
The service account used by the GitOps Application Controller will require elevated privileges to manage specific resources during the IBM WebSphere Automation. The extent of these privilege escalations will depend on the scope of the OpenShift GitOps ArgoCD instance—whether it is deployed in a namespace-scoped or cluster-wide configuration. For more information, see Argo CD instance scopes in the Red Hat OpenShift documentation.

The Role and RoleBinding examples provided below may be used to grant these additional permissions. However, it is strongly recommended that a cluster administrator carefully review and validate these permissions before applying them.

**Note:**

For OwnNamespace installation, make sure to create the Role & RoleBinding in the following namespaces, in addition to the namespace where WSA instance is deployed.
- ibm-cert-manager
- ibm-licensing

For SingleNamespace installation, make sure to create the Role & RoleBinding in the namespace where WSA instance, cert manger & licensing operator is deployed.

```bash
export GITOPS_NAMESPACE=openshift-gitops
export GITOPS_SERVICEACCOUNT=openshift-gitops-argocd-application-controller
export NAMESPACE=websphere-automation
```

#### The GitOps ArgoCD instance is deployed in cluster-wide mode:

```bash
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: gitops-websphere-automation-role
  namespace: ${NAMESPACE}
rules:
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["automation.websphere.ibm.com"]
    resources: ["websphereautomations", "webspheresecures", "webspherehealths"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
```

#### The GitOps ArgoCD instance is deployed in namespace-scoped mode:

```bash
cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: gitops-websphere-automation-role
  namespace: ${NAMESPACE}
rules:
  - apiGroups: ["operators.coreos.com"]
    resources: ["operatorgroups", "subscriptions", "catalogsources"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["automation.websphere.ibm.com"]
    resources: ["websphereautomations", "webspheresecures", "webspherehealths"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
```

#### Apply the RoleBinding to link the Role to the GitOps Application Controller service account

```bash
cat <<EOF | oc create -f -
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: gitops-websphere-automation-rolebinding
  namespace: ${NAMESPACE}
subjects:
- kind: ServiceAccount
  name: ${GITOPS_SERVICEACCOUNT}
  namespace: ${GITOPS_NAMESPACE}
roleRef:
  kind: Role
  name: gitops-websphere-automation-role
EOF
```  

### Deploy Argo CD Applications

Argo CD Applications are registered with the Argo CD server to define the desired state of Kubernetes resources. Each application specifies the source repository containing the manifests and the target cluster where those resources should be deployed. To deploy IBM WebSphere Automation, the Argo CD server synchronizes the corresponding applications to the target cluster, ensuring that the defined resources are applied and maintained in the desired state.

This section describes the Argo CD Applications that will be synchronized in the following steps to complete the installation. The Helm Chart Templates for IBM WebSphere Automation are hosted in a GitHub repository at https://github.com/IBM/ibm-websphere-automation/tree/main/gitops-deployment, which includes dedicated branches and release artifacts for each version. If customization is needed, you may use a forked repository as the SOURCE_REPOSITORY. Refer to the [Customized Installation](#customized-installation) section for guidance on modifying the Helm Chart Templates.

- [Argo CD Custom Health Checks](#argo-cd-custom-health-checks)
- [IBM Licensing Service](#ibm-licensing-service)
- [IBM Cert Manager](#ibm-cert-manager)
- [IBM WebSphere Automation](#ibm-cloud-pak-for-aiops)

When configuring Argo CD applications:

- Set the SOURCE_REPOSITORY to the GitHub repository containing the Helm Chart Templates.
- Set the TARGET_REVISION to the branch name that corresponds to the desired IBM WebSphere Automation version (e.g., use **v1.9.0** for WebSphere Automation 1.9.0).
- Set the GITOPS_NAMESPACE to namespace in which the ArgoCD instance is deployed.

#### Argo CD Custom Health Checks

Argo CD Custom Health Checks are a powerful feature that lets you define how Argo CD determines the health status of your custom Kubernetes resources (like CRDs). By default, Argo CD knows how to assess the health of standard Kubernetes resources (e.g., Deployments, Services), but for custom resources, you need to teach it what “healthy” means.

Create the following Argo CD Application, which includes custom health check configurations for both the Catalog Source and the IBM WebSphere Automation custom resources. Ensure that the `GITOPS_INSTANCE` and `GITOPS_NAMESPACE` variables coorrespond to the ArgoCD instance that will be used for the subsequent installation of IBM WebSphere Automation.

```bash
export SOURCE_REPOSITORY=https://github.com/IBM/ibm-websphere-automation
export TARGET_REVISION=<release-version>
export GITOPS_INSTANCE=openshift-gitops
export GITOPS_NAMESPACE=openshift-gitops
```

```bash
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: ${GITOPS_NAMESPACE}
  labels:
    app.kubernetes.io/instance: argocd
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  destination:
    namespace: ${GITOPS_NAMESPACE}
    server: 'https://kubernetes.default.svc'
  source:
    repoURL: ${SOURCE_REPOSITORY}
    path: gitops-deployment/argocd
    targetRevision: ${TARGET_REVISION}
    helm:
      valuesObject:
        gitops:
          instance: ${GITOPS_INSTANCE}
          namespace: ${GITOPS_NAMESPACE}
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

#### IBM Licensing Service

Skip this step if the IBM Cloud Pak Foundational Services License Service is already installed on the Red Hat OpenShift cluster that you are installing IBM WebSphere Automation on.

Create the following Argo CD Application to deploy the IBM Licensing Service.

```bash
export SOURCE_REPOSITORY=https://github.com/IBM/ibm-websphere-automation
export TARGET_REVISION=<release-version>
export GITOPS_NAMESPACE=openshift-gitops
```

```bash
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ibm-licensing
  namespace: ${GITOPS_NAMESPACE}
  labels:
    app.kubernetes.io/instance: ibm-licensing
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  destination:
    namespace: ibm-licensing
    server: 'https://kubernetes.default.svc'
  source:
    repoURL: ${SOURCE_REPOSITORY}
    path: gitops-deployment/licensing
    targetRevision: ${TARGET_REVISION}
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

#### IBM Cert Manager

Skip this step if you already have IBM Cert Manager or Red Hat Cert Manager installed on the Red Hat OpenShift cluster that you are installing IBM WebSphere Automation on. If you do not have a certificate manager then you must install one. 

Create the following ArgoCD Application to deploy the IBM Certificate Manager.

```bash
export SOURCE_REPOSITORY=https://github.com/IBM/ibm-websphere-automation
export TARGET_REVISION=<release-version>
export GITOPS_NAMESPACE=openshift-gitops
```

```bash
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ibm-cert-manager
  namespace: ${GITOPS_NAMESPACE}
  labels:
    app.kubernetes.io/instance: ibm-cert-manager
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  destination:
    namespace: ibm-cert-manager
    server: 'https://kubernetes.default.svc'
  source:
    repoURL: ${SOURCE_REPOSITORY}
    path: gitops-deployment/cert-manager
    targetRevision: ${TARGET_REVISION}
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

#### IBM WebSphere Automation
 
Create the following Argo CD Application to deploy IBM WebSphere Automation

There are two values files available under the /wsa path, any of the these values files can be used to deploy WSA via ArgoCD.

- `values-own-namespace.yaml`: A values file with values already pre-configured and installs the WebSphere Automation operator in OwnNamespace installation mode. Here both the operator and the WebSphere Automation instances are installed within the same namespace.
- `values.yaml`: Defines configurable parameters for deploying WSA.

Default values can be overridden, and additional attributes for the WebSphere Automation custom resources (CRs) can be specified using the `valuesObject` block, as detailed in the sections below.

#### Example 1: Creating an instance of WebSphereSecure & WebSphereAutomation custom resources using values.yaml

Set the necessary environment variables:
```bash
export VALUES_FILE=values.yaml
export SOURCE_REPOSITORY=https://github.com/IBM/ibm-websphere-automation
export TARGET_REVISION=<release-version>
export WSA_OPERATOR_NAMESPACE=<WSA Operator Namespace>
export WSA_INSTANCE_NAMESPACE=<WSA Instance Namespace>
export LICENSE_NAMESPACE=<IBM Licensing Namespace>
export CERT_MANAGER_NAMESPACE=<Cert Manager Namespace>
export GITOPS_NAMESPACE=<Gitops Namespace>
export LICENSE_ACCEPT=true
```

Create the application
```bash
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ibm-websphere-automation
  namespace: ${GITOPS_NAMESPACE}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/instance: ibm-websphere-automation
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  destination:
    namespace: ${WSA_INSTANCE_NAMESPACE}
    server: 'https://kubernetes.default.svc'
  source:
    repoURL: ${SOURCE_REPOSITORY}
    path: gitops-deployment/wsa
    targetRevision: ${TARGET_REVISION}
    helm:
      valueFiles:
        - ${VALUES_FILE}
      valuesObject:
        operatorNamespace: ${WSA_OPERATOR_NAMESPACE}
        commonServicesNamespace: ${WSA_OPERATOR_NAMESPACE}  
        subscription:
          wsaOperatorNamespace: ${WSA_OPERATOR_NAMESPACE}
          wsaInstanceNamespace: ${WSA_INSTANCE_NAMESPACE}
        wsaSecure:
          spec:
            license:
              accept: ${LICENSE_ACCEPT}
        wsa:
          spec:
            commonServices:
              registryNamespace: ${WSA_OPERATOR_NAMESPACE}
            license:
              accept: ${LICENSE_ACCEPT}
        licensingNamespace: ${LICENSE_NAMESPACE}
        certManagerNamespace: ${CERT_MANAGER_NAMESPACE}
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

**Note:** You can add or override attribute values in the values file using the `valuesObject` block. For example, to include a pullSecret in the WebSphere Secure custom resource, define it within the wsaSecure block as shown below.

For a complete list of supported attributes in the different IBM WebSphere Automation custom resources, refer to the [IBM WebSphere Automation custom resource](https://www.ibm.com/docs/en/ws-automation?topic=automation-custom-resources) document.

```bash
valuesObject:
  wsaSecure:
    spec:
      license:
        accept: ${LICENSE_ACCEPT}
      pullSecret: <value>  
```      

#### Example 2: Creating an instance of all three WebSphere Automation custom resources in OwnNamespace installation mode, using default configuration from the values file
Set the necessary environment variables:
```bash
export GITOPS_NAMESPACE=<Gitops Namespace>
export SOURCE_REPOSITORY=https://github.com/IBM/ibm-websphere-automation
export TARGET_REVISION=<release-version>
export WSA_INSTANCE_NAMESPACE=<WSA Instance Namespace>
export VALUES_FILE=values-own-namespace.yaml
```
Create the application
```bash
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ibm-websphere-automation
  namespace: ${GITOPS_NAMESPACE}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/instance: ibm-websphere-automation
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  destination:
    namespace: ${WSA_INSTANCE_NAMESPACE}
    server: 'https://kubernetes.default.svc'
  source:
    repoURL: ${SOURCE_REPOSITORY}
    path: gitops-deployment/wsa
    targetRevision: ${TARGET_REVISION}
    helm:
      valueFiles:
        - ${VALUES_FILE}
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

### Sync Applications

The ArgoCD applications created in the preceding steps should now exist on the ArgoCD Application UI. The applications can be synced via the `SYNC` button; starting with the ArgoCD Application, then WSA.

WSA will enter a `Progressing` state and will remain in that state until WSA is fully installed on the cluster. The final expected state across the applications is one of of `Healthy` / `Synced`.

Following a completed sync, the sync policy within the application can be updated to `Automated` via the App Details view. In this mode, any updates to the installation manifests at the source repository will be automatically synced to the cluster. Values set as overrides via `valuesObject` will continue to take precedence over the values file. 

If WSA is to be later uninstalled, ensure to disable automatic sync before commencing the uninstall.

### Verify your Installation

You can verify your installation of IBM WebSphere Automation by following the post-installation steps outlined in this [documentation](https://www.ibm.com/docs/en/ws-automation?topic=installing-validating-installation). These steps help to validate the installation status of WebSphere Automation operator and the WebSphere Automation instance deployment.

## Customized Installation

This section provides guidance for users who want to host the GitOps repositories in their own Git systems and customize the deployment of IBM WebSphere Automation from their own repositories.

To tailor a IBM WebSphere Automation deployment using your own Git repository, follow the steps outlined below.

1. Fork the [IBM WebSphere Automation GitOps](https://github.com/IBM/ibm-websphere-automation/tree/main/gitops-deployment) repository to your own GitHub account.
2. Define additional template files as needed. Any supplementary template files you add will be automatically detected and deployed by the Argo CD application during synchronization.
3. Add environment-specific values files, such as for staging, production, or other deployment targets and include any custom attributes as needed.
Then, configure the Argo CD application to reference the appropriate values file during deployment.

Note: If you use a repository that is forked from the official [IBM WebSphere Automation GitOps repository](https://github.com/IBM/ibm-websphere-automation/tree/main/gitops-deployment), then you must update the values of the Repository URL and Revision parameters across the ArgoCD applications to match your repository and branch. For example, if you use `https://github.com/<myaccount>/ibm-websphere-automation` and `dev` branch, then these two parameters must be changed.

## Known Limitations

1. CPFS upgrades are not handled by WSA's helm charts and will need to be handled outside of Gitops deployment, by running the upgrade script provided [here](https://github.com/IBM/ibm-websphere-automation/blob/gitops-enhancement/scripts/upgrade-cpfs.sh).

2. AllNamespaces mode of deployment is currently not supported at the moment with the configuration available in the values file.