#!/bin/bash

#
# IBM Confidential
# OCO Source Materials
# 5900-AH1
#
# (C) Copyright IBM Corp. 2024, 2025
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
#-------------------------------------------------------------------------------------------------------
# upgrade-prereq.sh - 
# Upgrades IBM Cloud Pak foundational services 4.x to a newer version
#-------------------------------------------------------------------------------------------------------
#
#   This script upgrades upgrades IBM Cert Manager and IBM Licensing operators,
#   and IBM Cloud Pak foundational services 4.x to a newer version.
#
#   This script contains the following parameters:
#   Required parameters:
#       --instance-namespace $WSA_INSTANCE_NAMESPACE - the namespace where the instance of WebSphere Automation custom resources (CR) (i.e "WebSphereAutomation") are.
#   Optional parameters:
#       --websphere-automation-version $WSA_VERSION_NUMBER - the semantic version of WebSphere Automation operator (i.e. "1.10.0") that is targeted for upgrade.
#       --cert-manager-namespace $CERT_MANAGER_NAMESPACE - the namespace where IBM Cert Manager operator is installed. Defaults to ibm-cert-manager.
#       --licensing-service-namespace $LICENSING_SERVICE_NAMESPACE - the namespace where IBM Licensing operator is installed. Defaults to ibm-licensing.
#       --cert-manager-catalog-source $CERT_MANAGER_CATALOG_SOURCE - the catalog source name for IBM Cert Manager operator. Defaults to ibm-cert-manager-catalog.
#       --licensing-service-catalog-source $LICENSING_SERVICE_CATALOG_SOURCE - the catalog source name for IBM Licensing operator. Defaults to ibm-licensing-catalog.
#       --common-services-catalog-source $COMMON_SERVICES_CATALOG_SOURCE - the catalog source name for IBM Cloud Pak foundational services (Common Services). Defaults to ibm-operator-catalog.
#       --common-services-case-version $COMMON_SERVICES_CASE_VERSION - Case version of IBM Cloud Pak foundational services (Common Services) is installed. Defaults to 4.10.0.
#       --all-namespaces - only declare when you will be installing IBM WebSphere Automation Operator in AllNamespaces install mode.
#       --patch-catalog-sources - only declare if you want to patch catalog sources to the newest version automatically through the script.
# 
#   Usage:
#       ./update-prereq.sh --instance-namespace <WSA_INSTANCE_NAMESPACE>
#                         [--websphere-automation-version <WSA_VERSION_NUMBER>]
#                         [--cert-manager-namespace <CERT_MANAGER_NAMESPACE>]
#                         [--licensing-service-namespace <LICENSING_SERVICE_NAMESPACE>]
#                         [--cert-manager-catalog-source <CERT_MANAGER_CATALOG_SOURCE>]
#                         [--licensing-service-catalog-source <LICENSING_SERVICE_CATALOG_SOURCE>]
#                         [--common-services-catalog-source <COMMON_SERVICES_CATALOG_SOURCE>]
#                         [--common-services-case-version <COMMON_SERVICES_CASE_VERSION>]
#                         [--all-namespaces]
#                         [--patch-catalog-sources]
#  
#-------------------------------------------------------------------------------------------------------


readonly usage="Usage: $0  --instance-namespace <WSA_INSTANCE_NAMESPACE>
                          [--websphere-automation-version <WSA_VERSION_NUMBER>]
                          [--cert-manager-namespace <CERT_MANAGER_NAMESPACE>]
                          [--licensing-service-namespace <LICENSING_SERVICE_NAMESPACE>]
                          [--cert-manager-catalog-source <CERT_MANAGER_CATALOG_SOURCE>]
                          [--licensing-service-catalog-source <LICENSING_SERVICE_CATALOG_SOURCE>]
                          [--common-services-catalog-source <COMMON_SERVICES_CATALOG_SOURCE>]
                          [--common-services-case-version <COMMON_SERVICES_CASE_VERSION>]
                          [--all-namespaces]
                          [--patch-catalog-sources]"

set -o pipefail

wait_for_condition() {
    local condition=$1
    local expected_result=$2
    local wait_message=$3
    local error_message=$4

    local total_retries=30
    local retries=1
    while true
    do
        echo "==> ${wait_message} (retry ${retries}/${total_retries})"
        result=$(eval "${condition}")

        [[ "$result" -eq "$expected_result" ]] && break

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
    local expected_result="1"
    local wait_message="Waiting for CatalogSource '${cs_name}' to be present..."
    local error_message="The CatalogSource '${cs_name}' does not exist."

    wait_for_condition "${condition}" "${expected_result}" "${wait_message}" "${error_message}"
}

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
            --patch-catalog-sources)
                readonly PATCH_CATALOG_SOURCES="true"
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

check_args() {   
    if [[ -z "${WSA_INSTANCE_NAMESPACE}" ]]; then
        echo "==> Error: Must set the WebSphere Automation instance's namespace. Exiting."
        echo ""
        echo "${usage}"
        exit 1
    fi

    if [[ -z "${WSA_VERSION_NUMBER}" ]]; then
        echo "==> WebSphere Automation version not set. Setting as 1.10.0."
        WSA_VERSION_NUMBER="1.10.0"
    else
        IFS='.' read -r -a semVersionArray <<< "${WSA_VERSION_NUMBER}"
        if [[ "${#semVersionArray[@]}" != "3" ]]; then
            echo "==> Error: You must provide the WebSphere Automation version in semantic version format, such as '1.10.0'."
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
        WSA_OPERATOR_NAMESPACE="openshift-operators"
    fi

    if [[ -z "${PATCH_CATALOG_SOURCES}" ]]; then
        PATCH_CATALOG_SOURCES="false"
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
        else
            # Otherwise, use the latest version
            COMMON_SERVICES_CASE_VERSION=4.14.0
        fi
        echo "==> Common Services case version is not set. Setting as ${COMMON_SERVICES_CASE_VERSION}."
    fi

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
    if [[ ! $(which yq 2>/dev/null) ]]; then
        echo "You must install 'yq' before proceeding with the upgrade script. Exiting."
        exit 1
    fi
    check_yq_version

    parse_args "$@"
    check_args

    wget https://github.com/IBM/cloud-pak/raw/master/repo/case/ibm-cp-common-services/${COMMON_SERVICES_CASE_VERSION}/ibm-cp-common-services-${COMMON_SERVICES_CASE_VERSION}.tgz
    tar -xvzf ibm-cp-common-services-$COMMON_SERVICES_CASE_VERSION.tgz
    cd ibm-cp-common-services/inventory/ibmCommonServiceOperatorSetup/installer_scripts/

    # Patch Catalog Sources only if the flag was declared
    if [[ "${PATCH_CATALOG_SOURCES}" == "true" ]]; then
        echo "Patching Catalog Sources to the newest versions..."
        if [[ "${COMMON_SERVICES_CATALOG_SOURCE}" == "ibm-operator-catalog" ]]; then
            echo "Upgrading IBM Operator CatalogSource..."
            oc patch catalogsource ibm-operator-catalog -n openshift-marketplace -p '{"spec":{"image":"icr.io/cpopen/ibm-operator-catalog:latest"}}' --type merge 
        else
            echo "Upgrading IBM Cert Manager CatalogSource..."
            oc patch catalogsource ${CERT_MANAGER_CATALOG_SOURCE} -n openshift-marketplace -p '{"spec":{"image":"icr.io/cpopen/ibm-cert-manager-operator-catalog"}}' --type merge
            oc patch catalogsource ${CERT_MANAGER_CATALOG_SOURCE} -n openshift-marketplace -p '{"spec":{"displayName":"ibm-cert-manager"}}' --type merge

            echo "Upgrading IBM Licensing CatalogSource..."
            oc patch catalogsource ${LICENSING_SERVICE_CATALOG_SOURCE} -n openshift-marketplace -p '{"spec":{"image":"icr.io/cpopen/ibm-licensing-catalog"}}' --type merge
            oc patch catalogsource ${LICENSING_SERVICE_CATALOG_SOURCE} -n openshift-marketplace -p '{"spec":{"displayName":"ibm-licensing"}}' --type merge
            
            echo "Upgrading IBM Foundational Services CatalogSource..."
            oc patch catalogsource ${COMMON_SERVICES_CATALOG_SOURCE} -n openshift-marketplace -p '{"spec":{"image":"icr.io/cpopen/ibm-common-service-catalog:latest"}}' --type merge
            oc patch catalogsource ${COMMON_SERVICES_CATALOG_SOURCE} -n openshift-marketplace -p '{"spec":{"displayName":"IBMCS Operators"}}' --type merge
        fi
    fi

    echo "Applying changes for required ingress network policies..."
    cd ./cp3-networkpolicy/
    ./install_networkpolicy.sh -n ${WSA_INSTANCE_NAMESPACE} -o ${WSA_OPERATOR_NAMESPACE} -c ${CERT_MANAGER_NAMESPACE} -l ${LICENSING_SERVICE_NAMESPACE}
    if [ "$?" != "1" ]; then
        echo "Successfully configured the required Network Policies!"
        echo ""
    else
        echo ""
        echo "Error configuring the required Network Policies."
        echo "Please check error logs."
        exit 1
    fi

    cd ../

    echo "Upgrading IBM Cert Manager and IBM Licensing operators..."
    ./cp3pt0-deployment/setup_singleton.sh --license-accept --enable-licensing --operator-namespace ${WSA_OPERATOR_NAMESPACE} --cert-manager-namespace ${CERT_MANAGER_NAMESPACE} --licensing-namespace ${LICENSING_SERVICE_NAMESPACE} --cert-manager-source ${CERT_MANAGER_CATALOG_SOURCE} --licensing-source ${LICENSING_SERVICE_CATALOG_SOURCE} -v 1
    if [ "$?" != "1" ]; then
        echo "Successfully upgraded IBM Cert Manager and IBM Licensing operators!"
        echo ""
    else
        echo ""
        echo "Error upgrading IBM Cert Manager and IBM Licensing operators."
        echo "Please check error logs."
        exit 1
    fi

    echo "Upgrading IBM Foundational Services..."

    COMMON_SERVICES_CASE_CHANNEL=v$(echo $COMMON_SERVICES_CASE_VERSION | sed 's/\.[^.]*$//')
    ./cp3pt0-deployment/setup_tenant.sh --license-accept --enable-licensing --operator-namespace ${WSA_OPERATOR_NAMESPACE} --source ${COMMON_SERVICES_CATALOG_SOURCE} --channel ${COMMON_SERVICES_CASE_CHANNEL} -v 1
    if [ "$?" != "1" ]; then
        echo "Successfully upgraded IBM Foundational Services!"
        echo ""
    else
        echo ""
        echo "Error upgrading IBM Foundational Services."
        echo "Please check error logs."
        exit 1
    fi

    cd ../../../../

    rm ibm-cp-common-services-$COMMON_SERVICES_CASE_VERSION.tgz
    rm -r ibm-cp-common-services

    echo "==> Pre-Requisites upgrade complete!"
    echo "      Install mode: ${INSTALL_MODE}"
    echo "      WebSphere Automation operator namespace: ${WSA_OPERATOR_NAMESPACE}"
    echo "      WebSphere Automation instance namespace: ${WSA_INSTANCE_NAMESPACE}"
}

main "$@"
