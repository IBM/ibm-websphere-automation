#!/bin/bash

#
# IBM Confidential
# OCO Source Materials
# 5900-AH1
#
# (C) Copyright IBM Corp. 2024
#

#
# The source code for this program is not published or otherwise
# divested of its trade secrets, irrespective of what has been
# deposited with the U.S. Copyright Office.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
WSA_MIGRATABLE_VERSION=1.6.4
ICS_COMPAT_VERSION="3.23.12"

validate_user_input() {
    WSA_OP_NS=$1
    WSA_IN_NS=$2
    # Validate oc login
    oc status > /dev/null 2>&1 && true
    if [[ $? -ne 0 ]]; then
        echo "==> Error: Run 'oc login' to log into a cluster before running $0. Exiting."
        exit 1
    fi

    # Validate project  
    wsa_operator_project=$(oc get project $WSA_OP_NS -o name | grep "project.project.openshift.io" -c)
    wsa_instance_project=$(oc get project $WSA_IN_NS -o name | grep "project.project.openshift.io" -c)
    if [[ "$wsa_operator_project" != "1" ]]; then
        echo "==> Error: WebSphere Automation operator namespace does not exist. Not continuing with the upgrade. Exiting."
        exit
    fi
    if [[ "$wsa_instance_project" != "1" ]]; then
        echo "==> Error: WebSphere Automation instance namespace does not exist. Not continuing with the upgrade. Exiting."
        exit
    fi

    # Validate controller-manager
    wsa_operator=$(oc get deployment websphere-automation-operator-controller-manager -n $WSA_OP_NS -o name | grep "deployment.apps" -c)
    if [[ "$wsa_operator" != "1" ]]; then
        echo "==> Error: WebSphere Automation operator is not installed. Not continuing with the upgrade. Exiting."
        exit
    fi

    # Validate WSA instance
    wsa_instance=$(oc get websphereautomation -n $WSA_IN_NS -o name | grep "websphereautomation.automation.websphere.ibm.com" -c)
    if [[ "$wsa_operator" != "1" ]]; then
        if [[ "$wsa_operator" == "0" ]]; then
            echo "==> Error: There is no WebSphere Automation CR instance in this namespace. Not continuing with the upgrade. Exiting." 
        else
            echo "==> Error: There must only be one WebSphere Automation CR instance in this namespace. Not continuing with the upgrade. Exiting." 
        fi
        exit
    fi
    oc project $WSA_IN_NS
}

is_wsa_migratable_version() {
    WSA_OP_NS=$1
    semVersion=$(oc get clusterserviceversion -n $WSA_OP_NS -o name | grep "ibm-websphere-automation\." | cut -d '/' -f2 | cut -d 'v' -f2)
    if [[ "$semVersion" != "$WSA_MIGRATABLE_VERSION" ]]; then
        echo "==> Error: You must be on version $WSA_MIGRATABLE_VERSION to upgrade the WebSphere Automation operator with this script. Exiting."
        exit 
    fi
}

is_less_than_ics_upgraded_version() {
    WSA_OP_NS=$1
    semVersion=$(oc get clusterserviceversion -n $WSA_OP_NS -o name | grep "ibm-common-service-operator\." | cut -d '/' -f2 | cut -d '-' -f4 | cut -d 'v' -f2)
    IFS='.' read -r -a semVersionArray <<< "$semVersion"
    lessThanUpgradedVersion="false"
    if [[ "${#semVersionArray[@]}" == "3" ]]; then
        if [[ "${semVersionArray[0]}" -lt "4" ]]; then
            lessThanUpgradedVersion="true"
        fi
    else
      echo "==> Failed to read the ClusterServiceVersion 'ibm-common-service-operator' version $semVersion. Exiting."
      exit
    fi
    if [[ "$lessThanUpgradedVersion" == "false" ]]; then
        echo "==> Error: Detected a version of IBM Cloud Pak foundational services 4 or higher. You must be on version $WSA_MIGRATABLE_VERSION to upgrade the WebSphere Automation operator with this script. Specifically, version $WSA_MIGRATABLE_VERSION of WebSphere Automation operator uses IBM Cloud Pak foundational services 3 as a dependency. Exiting."
        exit 
    fi
}

is_greater_than_or_equal_to_ics_compat_version() {
    semVersion=$(oc get clusterserviceversion -n $WSA_OP_NS -o name | grep "ibm-common-service-operator\." | cut -d '/' -f2 | cut -d '-' -f4 | cut -d 'v' -f2)
    IFS='.' read -r -a semVersionArray <<< "$semVersion"
    greaterEqualThanICSCompatVersion="false"
    if [[ "${#semVersionArray[@]}" == "3" ]]; then
        IFS='.' read -r -a icsCompatVersion <<< "$ICS_COMPAT_VERSION"
        if [[ "${semVersionArray[0]}" -gt "${icsCompatVersion[0]}" ]]; then
            greaterEqualThanICSCompatVersion="true"
        elif [[ "${semVersionArray[0]}" -eq "${icsCompatVersion[0]}" ]]; then
            if [[ "${semVersionArray[1]}" -gt "${icsCompatVersion[1]}" ]]; then
                greaterEqualThanICSCompatVersion="true"
            elif [[ "${semVersionArray[1]}" -eq "${icsCompatVersion[1]}" ]]; then
                if [[ "${semVersionArray[2]}" -ge "${icsCompatVersion[2]}" ]]; then
                    greaterEqualThanICSCompatVersion="true"
                fi
            fi
        fi
    fi
    if [[ "$greaterEqualThanICSCompatVersion" == "false" ]]; then
        echo "You must be on a version of IBM Cloud Pak foundational services greater than or equal to $ICS_COMPAT_VERSION to upgrade. Exiting."
        exit 
    fi
}

detect_cs_install() {
    WSA_IN_NS=$1
    operand_request_instance=$(oc get operandrequest -n $WSA_IN_NS -o name | grep "operandrequest.operator.ibm.com/websphereauto" -c)
    if [[ "$operand_request_instance" != 1 ]]; then
        echo "==> Error: IBM WebSphere Automation has not loaded correctly, please reinstall the operator and try again. Could not find the OperandRequest 'websphereauto' in namespace '$WSA_IN_NS'."
        exit 
    fi

    # Check .spec.requests.operands[].registryNamespace
    registry_ns_count=$(oc get operandrequest -n $WSA_IN_NS websphereauto -o yaml | grep "registryNamespace: " -c)
    if [[ "$registry_ns_count" != 1 ]]; then
        echo "==> Error: IBM WebSphere Automation's OperandRequest CR instance 'websphereauto' is invalid. Could not find the .spec.requests.operands[].registryNamespace field, or matched more than one. You must reinstall IBM WebSphere Automation operator before continuing the upgrade."
        exit
    fi
}

scale_to_zero() {
    scaleToZero=$1
    WSA_IN_NS=$2
    if [[ "$scaleToZero" == "true" ]]; then
        oc get websphereautomation -n $WSA_IN_NS -o name | cut -d '/' -f2 | xargs oc patch websphereautomation -n $WSA_IN_NS -p "{\"spec\":{\"scaleToZero\": $scaleToZero}}" --type=merge || true
    else
        oc get websphereautomation -n $WSA_IN_NS -o name | cut -d '/' -f2 | xargs oc patch websphereautomation -n $WSA_IN_NS -p "[{ \"op\": \"remove\", \"path\": \"/spec/scaleToZero\" }]" --type=json || true
    fi
}

wait_for_wsa_ready() {
    retries=$1
    WSA_OP_NS=$2
    WSA_IN_NS=$3

    while true
    do
        echo "==> Waiting for WebSphere Automation operator to start... ($retries retries)"
        alive=$(oc get deployments websphere-automation-operator-controller-manager -n $WSA_OP_NS -o name | grep "deployment.apps" -c)
        if [[ "$alive" -eq "1" ]]; then
            available_replicas=$(oc get deployments websphere-automation-operator-controller-manager -n $WSA_OP_NS -o=jsonpath="{range .items[*]}{.status.availableReplicas}")
            [[ "$available_replicas" -eq "1" ]] && break
        fi
        ((retries-=1))
        if (( retries < 0 )); then
            echo "  > Waited too long for WSA to start. Exiting."
            exit 1
        fi
        sleep 10
    done

    # Wait 20 seconds for reconcile loop to kick in
    sleep 20

    retries=$1
    while true
    do
        echo "==> Waiting for WebSphere Automation operator to be ready... ($retries retries)"
        # There should only be one WSA instance in a single namespace, so xargs takes one element only
        wsa_ready=$(oc get websphereautomation -o name -n $WSA_IN_NS | cut -d '/' -f2 | xargs oc get websphereautomation -n $WSA_IN_NS -o jsonpath='{.status.conditions}' | grep "All prerequisites and installed components are ready" -c)
        [[ "$wsa_ready" -eq "1" ]] && break
        ((retries-=1))
        if (( retries < 0 )); then
            echo "  > Waited too long for WSA to be ready. Exiting."
            exit 1
        fi
        sleep 10
    done
}

wait_for_zen_service() {
    NS=$1
    SCRIPT_NAME=$2
    retries=350
    while true
    do
        echo "==> Waiting for ZenService 'iaf-zen-cpdservice' in namespace '$NS' to become ready... ($retries retries left)"
        current_version_status=$(oc -n $NS get ZenService iaf-zen-cpdservice -o json | yq -r '.status.currentVersion')
        current_progress=$(oc -n $NS get ZenService iaf-zen-cpdservice -o json | yq -r '.status.Progress')
        [[ $current_version_status == 5.* ]] && [[ "$current_progress" == "100%" ]] && break
        ((retries-=1))
        if (( retries < 0 )); then
            echo "  > Waited too long for ZenService 'iaf-zen-cpdservice' to load. To try again from this timeout, run the script $SCRIPT_NAME with your previously specified flags and with the '--skip-checks' flag enabled."
            exit 1
        fi
        sleep 10
    done
    echo "==> ZenService 'iaf-zen-cpdservice' has been upgraded!"
}

wait_for_iam_config_job() {
    NS=$1
    retries=40
    while true
    do
        echo "==> Waiting for Job 'iam-config-job' in namespace '$NS' to become ready... ($retries retries left)"
        job_succeeded=$(oc -n $NS get Job iam-config-job -o json | yq -r '.status.succeeded')
        [[ $job_succeeded == 1 ]] && break
        ((retries-=1))
        if (( retries < 0 )); then
            echo "  > Waited too long for Job 'iam-config-job' to load."
            exit 1
        fi
        sleep 10
    done
    echo "==> Job 'iam-config-job' has completed!"
}

delete_operator() {
    operator_name=$1
    operator_ns=$2
    echo "==> Deleting operator $operator_name"
    delete_csv $operator_name $operator_ns || true
    if [[ "$operator_name" == "operand-deployment-lifecycle-manager" ]]; then
        delete_subscription "operand-deployment-lifecycle-manager-app" $operator_ns || true
    else
        delete_subscription $operator_name $operator_ns || true
    fi 
}

get_csv_name() {
    csv_ns=$2
    oc get clusterserviceversion -n $csv_ns -o name | grep "$1\." | cut -d '/' -f2
}

delete_csv() {
    csv_ns=$2
    csv_count=$(oc get clusterserviceversion -n $csv_ns -o name | grep "$1\." -c)
    csv=$(get_csv_name "$1" $csv_ns)
    if [[ "$csv_count" == "1" ]]; then
        echo "    > Deleting ClusterServiceVersion..."
        oc delete clusterserviceversion -n $csv_ns $csv || true
    elif [[ "$csv_count" == "0" ]]; then
        echo "    > ClusterServiceVersion not found."
    else
        echo "Error: Found multiple entries for CSV '$1'. Exiting."
        exit 1
    fi
}

get_subscription_name() {
    subscription_ns=$2
    oc get subscription -n $subscription_ns -o name | grep "$1" | cut -d '/' -f2
}

delete_subscription() {
    subscription_ns=$2
    csv_count=$(oc get subscription -n $subscription_ns -o name | grep "$1" -c)
    sub=$(get_subscription_name "$1" $subscription_ns)
    if [[ "$csv_count" == "1" ]]; then
        echo "    > Deleting Subscription..."
        oc delete subscription -n $subscription_ns $sub || true
    elif [[ "$csv_count" == "0" ]]; then
        echo "    > Subscription not found."
    else
        echo "Error: Found multiple entries for Subscription '$1'. Exiting."
        exit 1
    fi
}

delete_resource() {
    resource_name=$1
    instance_name=$2
    instance_ns=$3
    if [[ "$instance_ns" != "" ]]; then
        echo "==> Deleting $resource_name '$instance_name' in namespace '$instance_ns'"
        resource_count=$(oc get $resource_name -n $instance_ns -o name | grep "$instance_name" -c || echo "0")
        if [[ "$resource_count" == "1" ]]; then
            echo "    > Deleting $resource_name..."
            oc delete $resource_name -n $instance_ns $instance_name || true
        elif [[ "$resource_count" == "0" ]]; then
            echo "    > $resource_name not found."
        fi
    else
        echo "==> Deleting cluster-wide $resource_name '$instance_name'"
        resource_count=$(oc get $resource_name -o name | grep "$instance_name" -c || echo "0")
        if [[ "$resource_count" == "1" ]]; then
            echo "    > Deleting cluster-wide $resource_name..."
            oc delete $resource_name $instance_name || true
        elif [[ "$resource_count" == "0" ]]; then
            echo "    > Cluster-wide $resource_name not found."
        fi
    fi
}


create_network_policies() {
    WSA_OP_NS=$1
    OWN_NS=$2
    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-ingress-network-policy-zen-minio
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: zen-minio
  policyTypes:
  - Ingress
  ingress:
    - {} 
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: wsa-ingress-network-policy-common-service
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      name: ibm-common-service-operator
  ingress:
    - {}
  policyTypes:
    - Ingress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-zen-postgres
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: cloud-native-postgresql
  ingress:
    - {}
  policyTypes:
    - Ingress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: wsa-ingress-network-policy-zen-metastore
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: zen-metastore-edb
  ingress:
    - {}
  policyTypes:
    - Ingress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-platform-auth-service
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: platform-auth-service
  ingress:
    - {}
  egress:
    - {}
  policyTypes:
    - Ingress
    - Egress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-ingress-platform-identity-provider
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: platform-identity-provider
  ingress:
    - {}
  policyTypes:
    - Ingress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-ingress-platform-identity-management
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: platform-identity-management
  ingress:
    - {}
  policyTypes:
    - Ingress
EOF


    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-ingress-icp-mongodb
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      app: icp-mongodb
  ingress:
    - {}
  policyTypes:
    - Ingress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-egress-oidc-client-registration-egress
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      job-name: oidc-client-registration
  egress:
    - {}
  policyTypes:
    - Egress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-zen-core-api
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: zen-core-api
  ingress:
    - {}
  egress:
    - {}
  policyTypes:
    - Ingress
    - Egress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-zen-core
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: zen-core
  ingress:
    - {}
  egress:
    - {}
  policyTypes:
    - Ingress
    - Egress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-ibm-nginx
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: ibm-nginx
  ingress:
    - {}
  egress:
    - {}
  policyTypes:
    - Ingress
    - Egress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-usermgmt
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: usermgmt
  ingress:
    - {}
  egress:
    - {}
  policyTypes:
    - Ingress
    - Egress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-zen-metastoredb
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: zen-metastoredb
  ingress:
    - {}
  egress:
    - {}
  policyTypes:
    - Ingress
    - Egress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-activity-record-manager
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: wsa-activity-record-manager
  ingress:
    - {}
  egress:
    - {}
  policyTypes:
    - Ingress
    - Egress
EOF

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-zen-audit
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      component: zen-audit
  ingress:
    - {}
  policyTypes:
    - Ingress
EOF


    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-iam-operator
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      name: ibm-iam-operator
  egress:
    - {}
  policyTypes:
    - Egress
EOF

if [[ "$OWN_NS" == "true" ]]; then
    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-events-operator
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      ibmevents.ibm.com/kind: cluster-operator
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: $WSA_OP_NS
        podSelector: {}
  egress:
    - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: $WSA_OP_NS
        podSelector: {}
  policyTypes:
    - Ingress
    - Egress
EOF
fi

    oc apply -f - <<EOF
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: cs4x-iaf-system
  namespace: $WSA_OP_NS
spec:
  podSelector:
    matchLabels:
      ibmevents.ibm.com/cluster: iaf-system
  ingress:
    - {}
  policyTypes:
    - Ingress
EOF
}

delete_network_policies() {
    WSA_OP_NS=$1
    oc delete networkpolicy -n $WSA_OP_NS cs4x-ingress-network-policy-zen-minio || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-zen-postgres || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-platform-auth-service || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-ingress-platform-identity-provider || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-ingress-platform-identity-management || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-ingress-icp-mongodb || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-egress-oidc-client-registration-egress || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-zen-core-api || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-zen-core || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-ibm-nginx || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-usermgmt || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-zen-metastoredb || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-activity-record-manager || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-zen-audit || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-iam-operator || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-iaf-system || true
    oc delete networkpolicy -n $WSA_OP_NS cs4x-events-operator || true
}

delete_ics() {
  CS_NS=$1
  oc patch authentication.operator.ibm.com -n $CS_NS example-authentication -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete authentication.operator.ibm.com -n $CS_NS example-authentication || true #finalizer
  oc delete pap.operator.ibm.com -n $CS_NS example-pap || true
  oc delete policydecision.operator.ibm.com -n $CS_NS example-policydecision || true
  oc patch commonwebuis.operators.ibm.com -n $CS_NS example-commonwebui -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete commonwebuis.operators.ibm.com -n $CS_NS example-commonwebui || true #finalizer
  oc patch nginxingress.operator.ibm.com -n $CS_NS default -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete nginxingress.operator.ibm.com -n $CS_NS default || true #finalizer

  oc patch policycontroller.operator.ibm.com -n $CS_NS policycontroller-deployment -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete policycontroller.operator.ibm.com -n $CS_NS policycontroller-deployment || true #finalizer

  oc delete managementingress.operator.ibm.com -n $CS_NS default || true
  oc delete deployment -n $CS_NS meta-api-deploy || true
  oc patch OIDCClientWatcher.operator.ibm.com -n $CS_NS example-oidcclientwatcher -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete OIDCClientWatcher.operator.ibm.com -n $CS_NS example-oidcclientwatcher || true #finalizer

  oc patch PlatformAPI.operator.ibm.com -n $CS_NS platform-api -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete PlatformAPI.operator.ibm.com -n $CS_NS platform-api || true #finalizer

  oc delete SecretWatcher.operator.ibm.com -n $CS_NS secretwatcher-deployment || true
  oc delete MongoDB.operator.ibm.com -n $CS_NS ibm-mongodb || true
  oc delete job -n $CS_NS iam-onboarding || true
  oc delete job -n $CS_NS pre-zen-operand-config-job || true
  oc delete job -n $CS_NS security-onboarding || true
  oc delete job -n $CS_NS setup-job || true

  oc patch namespacescope.operator.ibm.com -n $CS_NS common-service -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete namespacescope.operator.ibm.com -n $CS_NS common-service || true #finalizer

  # OperandBindInfo
  oc patch operandbindinfos.operator.ibm.com -n $CS_NS ibm-iam-bindinfo -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete operandbindinfos.operator.ibm.com -n $CS_NS ibm-iam-bindinfo || true #finalizer
  oc patch operandbindinfos.operator.ibm.com -n $CS_NS management-ingress -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete operandbindinfos.operator.ibm.com -n $CS_NS management-ingress || true #finalizer

  # OperandRequests
  oc patch operandrequests.operator.ibm.com -n $CS_NS ibm-commonui-request -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete operandrequests.operator.ibm.com -n $CS_NS ibm-commonui-request || true #finalizer

  oc patch operandrequests.operator.ibm.com -n $CS_NS ibm-iam-request -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete operandrequests.operator.ibm.com -n $CS_NS ibm-iam-request || true #finalizer
  oc patch operandrequests.operator.ibm.com -n $CS_NS ibm-mongodb-request -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete operandrequests.operator.ibm.com -n $CS_NS ibm-mongodb-request || true #finalizer

  oc patch operandrequests.operator.ibm.com -n $CS_NS management-ingress -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete operandrequests.operator.ibm.com -n $CS_NS management-ingress || true #finalizer

  oc patch operandrequests.operator.ibm.com -n $CS_NS platform-api-request -p '{"metadata":{"finalizers":null}}' --type=merge || true
  oc delete operandrequests.operator.ibm.com -n $CS_NS platform-api-request || true #finalizer

  oc delete project $CS_NS || true
}

check_catalog_source() {
    cs_name=$1
    cs_count=$(oc get catalogsource -n openshift-marketplace -o name | grep "${cs_name}" -c)
    if [[ "$cs_count" != "1" ]]; then
        echo "==> Error: The CatalogSource '${cs_name}' does not exist. Follow the instructions on https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.4?topic=online-installing-foundational-services-by-using-console#catalog-sources to install all CatalogSources. Exiting."
        exit
    fi
}

# Implementation taken from https://github.com/IBM/cloud-pak/blob/master/repo/case/ibm-cp-common-services/4.4.0/ibm-cp-common-services-4.4.0.tgz
check_yq_version() {
  yq_version=$(yq --version | awk '{print $NF}' | sed 's/^v//')
  yq_minimum_version=4.18.1

  if [ "$(printf '%s\n' "$yq_minimum_version" "$yq_version" | sort -V | head -n1)" != "$yq_minimum_version" ]; then 
    echo "==> Error: yq version $yq_version must be at least $yq_minimum_version or higher."
    echo "  > Instructions for installing/upgrading yq are available here: https://github.com/marketplace/actions/yq-portable-yaml-processor"
    exit
  fi
}