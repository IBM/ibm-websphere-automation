#!/bin/bash

#
# IBM Confidential
# OCO Source Materials
# 5900-AH1
#
# (C) Copyright IBM Corp. 2025
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
# upgrade-cpfs.sh - 
# Upgrades IBM Cloud Pak foundational services 4.x to a newer version
#-------------------------------------------------------------------------------------------------------
#
#   This script upgrades IBM Cloud Pak foundational services 4.x to a newer version.
#
#   This script contains the following parameters:
#   
#   Required parameters:
#       --instance-namespace $WSA_INSTANCE_NAMESPACE - the namespace where the instance of WebSphere Automation custom resources (CR) (i.e "WebSphereAutomation") are.
#       --common-services-case-version $COMMON_SERVICES_CASE_VERSION - Case version of IBM Cloud Pak foundational services (Common Services) is installed.
#   
#   Optional parameters:
#       --common-services-catalog-source $COMMON_SERVICES_CATALOG_SOURCE - the catalog source name for IBM Cloud Pak foundational services (Common Services). Defaults to ibm-operator-catalog.
#       --all-namespaces - only declare when you will be installing IBM WebSphere Automation Operator in AllNamespaces install mode.
# 
#   Usage:
#       ./update-cpfs.sh --instance-namespace <WSA_INSTANCE_NAMESPACE> --common-services-case-version <COMMON_SERVICES_CASE_VERSION>
#                       [--common-services-catalog-source <COMMON_SERVICES_CATALOG_SOURCE>]
#                       [--all-namespaces]
#-------------------------------------------------------------------------------------------------------


readonly usage="Usage: $0  --instance-namespace <WSA_INSTANCE_NAMESPACE>
                           --common-services-case-version <COMMON_SERVICES_CASE_VERSION>
                           [--common-services-catalog-source <COMMON_SERVICES_CATALOG_SOURCE>]
                           [--all-namespaces]"

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
             --common-services-case-version)
                shift
                readonly COMMON_SERVICES_CASE_VERSION="${1}"
                ;;    
            --common-services-catalog-source)
                shift
                readonly COMMON_SERVICES_CATALOG_SOURCE="${1}"
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

check_args() {   
    if [[ -z "${WSA_INSTANCE_NAMESPACE}" ]]; then
        echo "==> Error: Must set the WebSphere Automation instance's namespace. Exiting."
        echo ""
        echo "${usage}"
        exit 1
    fi

    if [[ -z "${INSTALL_MODE}" ]]; then
        echo "==> Install mode not set. Setting as OwnNamespace mode."
        INSTALL_MODE="OwnNamespace"
        WSA_OPERATOR_NAMESPACE=${WSA_INSTANCE_NAMESPACE}
    fi

    if [[ "${INSTALL_MODE}" == "AllNamespaces" ]]; then
        WSA_OPERATOR_NAMESPACE="openshift-operators"
    fi

    if [[ -z "${COMMON_SERVICES_CATALOG_SOURCE}" ]]; then
        echo "==> Common Services CatalogSource not set. Setting as ibm-operator-catalog."
    COMMON_SERVICES_CATALOG_SOURCE="ibm-operator-catalog"
        check_catalog_source "$COMMON_SERVICES_CATALOG_SOURCE"
    elif [[ "${COMMON_SERVICES_CATALOG_SOURCE}" != "ibm-operator-catalog" ]]; then
        # Validate whether or not all the required catalog sources exist
        check_catalog_source "$COMMON_SERVICES_CATALOG_SOURCE"
    fi

    echo "***********************************************************************"
    echo "Configuration Details:"
    echo "      Install mode: ${INSTALL_MODE}"
    echo "      WebSphere Automation operator namespace: ${WSA_OPERATOR_NAMESPACE}"
    echo "      WebSphere Automation instance namespace: ${WSA_INSTANCE_NAMESPACE}"
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

    echo "==> CPFS upgrade complete!"
    echo "      Install mode: ${INSTALL_MODE}"
    echo "      WebSphere Automation operator namespace: ${WSA_OPERATOR_NAMESPACE}"
    echo "      WebSphere Automation instance namespace: ${WSA_INSTANCE_NAMESPACE}"
}

main "$@"