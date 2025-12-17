#!/bin/bash

#
# IBM Confidential
# OCO Source Materials
# 5900-AH1
#
# (C) Copyright IBM Corp. 2024, 2025
#
# The source code for this program is not published or otherwise
# divested of its trade secrets, irrespective of what has been
# deposited with the U.S. Copyright Office.
#

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
#-------------------------------------------------------------------------------------------------------
#   install-prereq.sh - 
#   Installs Pre-Requisites for IBM WebSphere Automation installation
#-------------------------------------------------------------------------------------------------------
#
#   This script installs Pre-Requisites for IBM WebSphere Automation installation.
#   It installs IBM Cert Manager and IBM Licensing operators,
#   and required ingress Network Policies for Foundational Services.
#   It prepares the cluster for installing versions >= 1.7.0 of WebSphere Automation operator.
#   After running this script, you must install WebSphere Automation inside:
#   openshift-operators namespace for AllNamespaces install mode or <WSA_INSTANCE_NAMESPACE> for OwnNamespace install mode.
#   Then you must install WebSphere Automation instances inside <WSA_INSTANCE_NAMESPACE>.
#
#   This script contains the following parameters:
#  
#   Required parameters:
#       --instance-namespace $WSA_INSTANCE_NAMESPACE - the namespace where the instance of WebSphere Automation custom resources (CR) (i.e "WebSphereAutomation") will be created.
#   Optional parameters:
#       --websphere-automation-version $WSA_VERSION_NUMBER - the semantic version of WebSphere Automation operator (i.e. "1.11.0") that is targeted for installation.
#       --cert-manager-namespace $CERT_MANAGER_NAMESPACE - the namespace where IBM Cert Manager operator will be installed. Defaults to ibm-cert-manager.
#       --licensing-service-namespace $LICENSING_SERVICE_NAMESPACE - the namespace where IBM Licensing operator will be installed. Defaults to ibm-licensing.
#       --cert-manager-catalog-source $CERT_MANAGER_CATALOG_SOURCE - the catalog source name for IBM Cert Manager operator. Defaults to ibm-cert-manager-catalog.
#       --licensing-service-catalog-source $LICENSING_SERVICE_CATALOG_SOURCE - the catalog source name for IBM Licensing operator. Defaults to ibm-licensing-catalog.
#       --common-services-catalog-source $COMMON_SERVICES_CATALOG_SOURCE - the catalog source name for IBM Cloud Pak foundational services (Common Services). Defaults to ibm-operator-catalog.
#       --common-services-case-version $COMMON_SERVICES_CASE_VERSION - Case version of IBM Cloud Pak foundational services (Common Services) to be installed. Defaults to 4.10.0.
#       --all-namespaces - only declare when you will be installing IBM WebSphere Automation Operator in AllNamespaces install mode.
# 
#   Usage:
#       ./install-prereq.sh --instance-namespace <WSA_INSTANCE_NAMESPACE>
#                           [--websphere-automation-version <WSA_VERSION_NUMBER>]
#                           [--cert-manager-namespace <CERT_MANAGER_NAMESPACE>]
#                           [--licensing-service-namespace <LICENSING_SERVICE_NAMESPACE>]
#                           [--cert-manager-catalog-source <CERT_MANAGER_CATALOG_SOURCE>]
#                           [--licensing-service-catalog-source <LICENSING_SERVICE_CATALOG_SOURCE>]
#                           [--common-services-catalog-source <COMMON_SERVICES_CATALOG_SOURCE>]
#                           [--common-services-case-version <COMMON_SERVICES_CASE_VERSION>]
#                           [--all-namespaces]
#  
#-------------------------------------------------------------------------------------------------------


readonly usage="Usage: $0 --instance-namespace <WSA_INSTANCE_NAMESPACE>
                           [--websphere-automation-version <WSA_VERSION_NUMBER>]
                           [--cert-manager-namespace <CERT_MANAGER_NAMESPACE>]
                           [--licensing-service-namespace <LICENSING_SERVICE_NAMESPACE>]
                           [--cert-manager-catalog-source <CERT_MANAGER_CATALOG_SOURCE>]
                           [--licensing-service-catalog-source <LICENSING_SERVICE_CATALOG_SOURCE>]
                           [--common-services-catalog-source <COMMON_SERVICES_CATALOG_SOURCE>]
                           [--common-services-case-version <COMMON_SERVICES_CASE_VERSION>]
                           [--all-namespaces]"

set -o pipefail

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --instance-namespace)
                shift
                readonly WSA_INSTANCE_NAMESPACE="${1}"
                ;;
            --websphere-automation-version)
                shift
                readonly WSA_VERSION_NUMBER="${1}"
                ;;
            --cert-manager-namespace)
                shift
                readonly CERT_MANAGER_NAMESPACE="${1}"
                ;;
            --licensing-service-namespace)
                shift
                readonly LICENSING_SERVICE_NAMESPACE="${1}"
                ;;
            --cert-manager-catalog-source)
                shift
                readonly CERT_MANAGER_CATALOG_SOURCE="${1}"
                ;;
            --licensing-service-catalog-source)
                shift
                readonly LICENSING_SERVICE_CATALOG_SOURCE="${1}"
                ;;
            --common-services-catalog-source)
                shift
                readonly COMMON_SERVICES_CATALOG_SOURCE="${1}"
                ;;
            --common-services-case-version)
                shift
                readonly COMMON_SERVICES_CASE_VERSION="${1}"
                ;;
            --all-namespaces)
                readonly INSTALL_MODE="AllNamespaces"
                ;;
            *)
                echo "Error: Invalid argument - ${1}"
                echo "${usage}"
                exit 1
            ;;
        esac
        shift
    done
}

create_namespace() {
    ns=$1
    ns_status=$(oc get ns $ns  -o yaml | yq '.status.phase')
    if [[ "${ns_status}" != "Active" ]]; then
        echo "==> ${ns} namespace does not exist. Creating ${ns} namespace."
        oc create namespace ${ns}
    fi
}

check_args() {    
    if [[ -z "${WSA_INSTANCE_NAMESPACE}" ]]; then
        echo "==> Error: Must set the WebSphere Automation instance's namespace. Exiting."
        echo ""
        echo "${usage}"
        exit 1
    fi

    if [[ -z "${WSA_VERSION_NUMBER}" ]]; then
        echo "==> WebSphere Automation version not set. Setting as 1.11.0"
        WSA_VERSION_NUMBER="1.11.0"
    else
        IFS='.' read -r -a semVersionArray <<< "${WSA_VERSION_NUMBER}"
        if [[ "${#semVersionArray[@]}" != "3" ]]; then
            echo "==> Error: You must provide the WebSphere Automation version in semantic version format, such as '1.11.0'."
            echo ""
            echo "${usage}"
            exit 1
        fi
    fi

    if [[ -z "${INSTALL_MODE}" ]]; then
        echo "==> Install mode not set. Setting as OwnNamespace mode."
        INSTALL_MODE="OwnNamespace"
        WSA_OPERATOR_NAMESPACE=${WSA_INSTANCE_NAMESPACE}
    fi

    if [[ "${INSTALL_MODE}" == "AllNamespaces" ]]; then
        echo "==> AllNamespaces mode. Creating ibm-common-services namespace for Foundational Services."
        create_namespace ibm-common-services
        WSA_OPERATOR_NAMESPACE="openshift-operators"
    fi

    if [[ -z "${CERT_MANAGER_NAMESPACE}" ]]; then
        echo "==> Cert Manager namespace not set. Setting as ibm-cert-manager."
        CERT_MANAGER_NAMESPACE="ibm-cert-manager"
    fi

    if [[ -z "${LICENSING_SERVICE_NAMESPACE}" ]]; then
        echo "==> Licensing Service namespace not set. Setting as ibm-licensing."
        LICENSING_SERVICE_NAMESPACE="ibm-licensing"
    fi

    if [[ -z "${CERT_MANAGER_CATALOG_SOURCE}" ]]; then
        echo "==> Cert Manager CatalogSource not set. Setting as ibm-cert-manager-catalog."
        check_for_default_catalog_source "ibm-cert-manager-catalog" "ibm-operator-catalog"
        CERT_MANAGER_CATALOG_SOURCE=$default
    fi

    if [[ -z "${LICENSING_SERVICE_CATALOG_SOURCE}" ]]; then
        echo "==> Licensing Service CatalogSource not set. Setting as ibm-licensing-catalog."
        check_for_default_catalog_source "ibm-licensing-catalog" "ibm-operator-catalog"
        LICENSING_SERVICE_CATALOG_SOURCE=$default
    fi

    if [[ -z "${COMMON_SERVICES_CATALOG_SOURCE}" ]]; then
        echo "==> Common Services CatalogSource not set. Setting as ibm-operator-catalog."
        COMMON_SERVICES_CATALOG_SOURCE="ibm-operator-catalog"
        check_catalog_source "$COMMON_SERVICES_CATALOG_SOURCE"
    elif [[ "${COMMON_SERVICES_CATALOG_SOURCE}" != "ibm-operator-catalog" ]]; then
        # Validate whether or not all the required catalog sources exist
        check_catalog_source "$COMMON_SERVICES_CATALOG_SOURCE"
        check_catalog_source "$LICENSING_SERVICE_CATALOG_SOURCE"
        check_catalog_source "$CERT_MANAGER_CATALOG_SOURCE"
    fi

    if [[ -z "${COMMON_SERVICES_CASE_VERSION}" ]]; then
        # Check operator versions that might require using older Common Services case versions
        if [[ "${WSA_VERSION_NUMBER}" == "1.7.0" ]] || [[ "${WSA_VERSION_NUMBER}" == "1.7.1" ]] || [[ "${WSA_VERSION_NUMBER}" == "1.7.2" ]]; then
            COMMON_SERVICES_CASE_VERSION=4.4.0
        elif [[ "${WSA_VERSION_NUMBER}" == "1.7.3" ]]; then
            COMMON_SERVICES_CASE_VERSION=4.6.4
        elif [[ "${WSA_VERSION_NUMBER}" == "1.7.4" ]]; then
            COMMON_SERVICES_CASE_VERSION=4.8.0
        elif [[ "${WSA_VERSION_NUMBER}" == "1.7.5" ]] || [[ "${WSA_VERSION_NUMBER}" == "1.8.0" ]]; then
            COMMON_SERVICES_CASE_VERSION=4.9.0
        elif [[ "${WSA_VERSION_NUMBER}" == "1.8.1" ]] || [[ "${WSA_VERSION_NUMBER}" == "1.8.2" ]]; then
            COMMON_SERVICES_CASE_VERSION=4.10.0
        elif [[ "${WSA_VERSION_NUMBER}" == "1.9.0" ]]; then
            COMMON_SERVICES_CASE_VERSION=4.12.0
        elif [[ "${WSA_VERSION_NUMBER}" == "1.10.0" ]]; then
            COMMON_SERVICES_CASE_VERSION=4.14.0
        else
            # Otherwise, use the latest version
            COMMON_SERVICES_CASE_VERSION=4.15.0
        fi
        echo "==> Common Services case version is not set. Setting as ${COMMON_SERVICES_CASE_VERSION}."
    fi
    
    COMMON_SERVICES_CASE_CHANNEL=$(echo $COMMON_SERVICES_CASE_VERSION | sed 's/\.[^.]*$//')

    echo "***********************************************************************"
    echo "Configuration Details:"
    echo "      Install mode: ${INSTALL_MODE}"
    echo "      WebSphere Automation operator namespace: ${WSA_OPERATOR_NAMESPACE}"
    echo "      WebSphere Automation instance namespace: ${WSA_INSTANCE_NAMESPACE}"
    echo "      WebSphere Automation version: ${WSA_VERSION_NUMBER}"
    echo "      Cert Manager namespace: ${CERT_MANAGER_NAMESPACE}"
    echo "      Licensing Service namespace: ${LICENSING_SERVICE_NAMESPACE}"
    echo "      Cert Manager CatalogSource: ${CERT_MANAGER_CATALOG_SOURCE}"
    echo "      Licensing Service CatalogSource: ${LICENSING_SERVICE_CATALOG_SOURCE}"
    echo "      Common Services CatalogSource: ${COMMON_SERVICES_CATALOG_SOURCE}"
    echo "      Common Services case version: ${COMMON_SERVICES_CASE_VERSION}"
    echo "***********************************************************************"
}

wait_for_condition() {
    local condition=$1
    local target=$2
    local comp_operator=$3
    local wait_message=$4
    local error_message=$5

    local total_retries=30
    local retries=1
    while true
    do
        echo "==> ${wait_message} (retry ${retries}/${total_retries})"
        result=$(eval "${condition}")

        if [[ $comp_operator == "eq" ]]; then
            [[ $(($result)) -eq $(($target)) ]] && break
        elif [[ $comp_operator == "ge" ]]; then
            [[ $(($result)) -ge $(($target)) ]] && break
        else
            echo "==> Error: Condition check failed. Exiting."
            exit 1
        fi

        ((retries+=1))
        if (( retries >= total_retries )); then
            echo "==> Error: ${error_message}. Exiting."
            exit 1
        fi
        sleep 10
    done
}

check_catalog_source() {
    local cs_name="$1"

    local condition="oc get catalogsource -n openshift-marketplace -o name | grep ${cs_name} -c"
    local target="1"
    local comp_operator="eq"
    local wait_message="Waiting for CatalogSource '${cs_name}' to be present..."
    local error_message="The CatalogSource '${cs_name}' does not exist."

    wait_for_condition "${condition}" "${target}" "${comp_operator}" "${wait_message}" "${error_message}"
}

check_package_manifest() {
    local pm_name="$1"

    local condition="oc get packagemanifest -o name | grep "${pm_name}" -c"
    local target="1"
    local comp_operator="ge"
    local wait_message="Waiting for PackageManifest '${pm_name}' to be present..."
    local error_message="The PackageManifest '${pm_name}' does not exist."

    wait_for_condition "${condition}" "${target}" "${comp_operator}" "${wait_message}" "${error_message}"
}

check_for_sub() {
    local pm_name=$1
    local sub_name=$2
    local namespace=$3

    local condition="oc get subscription.operators.coreos.com -l operators.coreos.com/${pm_name}.${namespace}='' -n ${namespace} -o yaml -o jsonpath='{.items[*].status.installedCSV}' | grep ${sub_name}"
    csv_name=$(eval "${condition}")
    result=$(echo "${csv_name}" | grep ${sub_name} -c)

    if [[ "$result" == "1" ]]; then
        target_version_installed=$(echo "${csv_name}" | grep "$COMMON_SERVICES_CASE_VERSION" -c)
        
        if [[ "$target_version_installed" == "1" ]]; then
            echo "1"
            return
        else
            v4_installed=$(echo "${csv_name}" | grep "v4." -c)
            if [[ "$v4_installed" == "1" ]]; then
                echo "-1"
            else
                echo "-2"
            fi
            return
        fi
    fi
    echo "0"
}

wait_for_csv() {
    local pm_name=$1
    local sub_name=$2
    local namespace=$3

    local condition="oc get subscription.operators.coreos.com -l operators.coreos.com/${pm_name}.${namespace}='' -n ${namespace} -o yaml -o jsonpath='{.items[*].status.installedCSV}' | grep ${sub_name} -c"
    local target="1"
    local comp_operator="eq"
    local wait_message="Waiting for ClusterServiceVersion for '${pm_name}' to be present..."
    local error_message="The ClusterServiceVersion for '${pm_name}' does not exist."

    wait_for_condition "${condition}" "${target}" "${comp_operator}" "${wait_message}" "${error_message}"
}

wait_for_operator() {
    local operator_name=$1
    local namespace=$2

    local condition="oc -n ${namespace} get csv --no-headers --ignore-not-found | egrep 'Succeeded' | grep ^${operator_name} -c"
    local target="1"
    local comp_operator="eq"
    local wait_message="Waiting for operator ${operator_name} to be present..."
    local error_message="The operator ${operator_name} does not exist."

    wait_for_condition "${condition}" "${target}" "${comp_operator}" "${wait_message}" "${error_message}"
}

check_for_default_catalog_source() {
    local current_source=$1
    local backup_source=$2

    local wait_message="Waiting for CatalogSource '${current_source}' to be present..."
    local total_retries=10
    local retries=1

    while true
    do
        echo "==> ${wait_message} (retry ${retries}/${total_retries})"
        result=$(eval "oc get catalogsource -n openshift-marketplace -o name | grep ${current_source} -c")

        if [[ $(($result)) -eq 1 ]]; then
            default=$current_source
            break;
        fi

        ((retries+=1))
        if (( retries >= total_retries )); then
            echo "The CatalogSource '${current_source}' does not exist, using ${backup_source} instead."
            default=$backup_source
            break
        fi
        sleep 10
    done
}

main() {
    parse_args "$@"
    check_args

    create_namespace ${WSA_OPERATOR_NAMESPACE}
    create_namespace ${WSA_INSTANCE_NAMESPACE}
    create_namespace ${CERT_MANAGER_NAMESPACE}
    create_namespace ${LICENSING_SERVICE_NAMESPACE}

    wget https://github.com/IBM/cloud-pak/raw/master/repo/case/ibm-cp-common-services/${COMMON_SERVICES_CASE_VERSION}/ibm-cp-common-services-${COMMON_SERVICES_CASE_VERSION}.tgz
    tar -xvzf ibm-cp-common-services-$COMMON_SERVICES_CASE_VERSION.tgz
    cd ibm-cp-common-services/inventory/ibmCommonServiceOperatorSetup/installer_scripts/

    echo "Installing required ingress network policies..."
    cd ./cp3-networkpolicy/
    ./install_networkpolicy.sh -n ${WSA_INSTANCE_NAMESPACE} -o ${WSA_OPERATOR_NAMESPACE} -c ${CERT_MANAGER_NAMESPACE} -l ${LICENSING_SERVICE_NAMESPACE}
    if [ "$?" != "1" ]; then
        echo "Successfully created required Network Policies!"
        echo ""
    else
        echo ""
        echo "Error creating required Network Policies."
        echo "Please check error logs."
        exit 1
    fi

    cd ../

    echo "Installing IBM Cert Manager and IBM Licensing operators..."
    ./cp3pt0-deployment/setup_singleton.sh --license-accept --enable-licensing --operator-namespace ${WSA_OPERATOR_NAMESPACE} --cert-manager-namespace ${CERT_MANAGER_NAMESPACE} --licensing-namespace ${LICENSING_SERVICE_NAMESPACE} --cert-manager-source ${CERT_MANAGER_CATALOG_SOURCE} --licensing-source ${LICENSING_SERVICE_CATALOG_SOURCE} -v 1
    if [ "$?" != "1" ]; then
        echo "Successfully installed IBM Cert Manager and IBM Licensing operators!"
        echo ""
    else
        echo ""
        echo "Error installing IBM Cert Manager and IBM Licensing operators."
        echo "Please check error logs."
        exit 1
    fi

    res=$(check_for_sub "ibm-common-service-operator" "ibm-common-service-operator" "$WSA_OPERATOR_NAMESPACE")
    if [[ $res == 1 ]]; then
        echo "==> Info: IBM Cloud Pak foundational services v$COMMON_SERVICES_CASE_VERSION already exists."
    elif [[ $res == 0 ]]; then
        echo "Installing IBM Cloud Pak foundational services..."

        check_package_manifest "ibm-common-service-operator"

        if [[ $INSTALL_MODE == "OwnNamespace" ]]; then
            oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-websphere-automation-group
  namespace: $WSA_OPERATOR_NAMESPACE
spec:
  targetNamespaces:
  - $WSA_OPERATOR_NAMESPACE
EOF
        fi

        oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-common-service-operator
  namespace: $WSA_OPERATOR_NAMESPACE
spec:
  channel: v${COMMON_SERVICES_CASE_CHANNEL}
  installPlanApproval: Automatic
  name: ibm-common-service-operator
  source: ${COMMON_SERVICES_CATALOG_SOURCE}
  sourceNamespace: openshift-marketplace
EOF

        wait_for_csv "ibm-common-service-operator" "ibm-common-service-operator" "$WSA_OPERATOR_NAMESPACE"
        wait_for_operator "ibm-common-service-operator" "$WSA_OPERATOR_NAMESPACE"

        wait_for_csv "ibm-odlm" "operand-deployment-lifecycle-manager" "$WSA_OPERATOR_NAMESPACE"
        wait_for_operator "operand-deployment-lifecycle-manager" "$WSA_OPERATOR_NAMESPACE"
    else
        echo "==> Error installing IBM Cloud Pak foundational services v$COMMON_SERVICES_CASE_VERSION."
        if [[ $res == -1 ]]; then
            echo "    IBM Cloud Pak foundational services v4 is already installed in the cluster."
            echo "    Upgrade Foundational Services to v$COMMON_SERVICES_CASE_VERSION using upgrade-prereq.sh"
        else
            echo "    Older version of IBM Cloud Pak foundational services is installed in the cluster."
            echo "    Migrate to Foundational Services to v4."
        fi
        exit 1
    fi

    cd ../../../../

    rm ibm-cp-common-services-$COMMON_SERVICES_CASE_VERSION.tgz
    rm -r ibm-cp-common-services

    echo "==> Pre-Requisites installation complete!"
    echo "    Your OpenShift cluster is ready to install IBM WebSphere Automation Operator version >=1.7.0."
    echo "    Please install the latest driver of IBM WebSphere Automation Operator in the OpenShift UI using OperatorHub with the following configs: "
    echo "      Install mode: ${INSTALL_MODE}"
    echo "      WebSphere Automation operator namespace: ${WSA_OPERATOR_NAMESPACE}"
    echo "      WebSphere Automation instance namespace: ${WSA_INSTANCE_NAMESPACE}"
}

main "$@"
