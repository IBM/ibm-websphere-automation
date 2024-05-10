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
#-------------------------------------------------------------------------------------------------------
# preserve-ics.sh - 
# Preserves IBM Cloud Pak foundational services 3.x for a IBM WebSphere Automation installation
# in the default CommonServices namespace (ibm-common-services), while installing a new
# IBM Cloud Pak foundational services 4.x into the WebSphere Automation operator's namespace.
#
# Preserving the IBM Cloud Pak foundational services 3.x allows other CloudPaks to continue to consume
# CommonServices from ibm-common-services, while WebSphere Automation is isolated in its own namespace 
# consuming new 4.x CommonServices.
#-------------------------------------------------------------------------------------------------------
#
#  This script preserves IBM Cloud Pak foundational services 3.x.
#  It prepares the cluster for installing version 1.7.0 of WebSphere Automation operator in OwnNamespace mode.
#  You must install the WebSphere Automation operator inside of WSA_OPERATOR_NAMESPACE after running this script.
#
#  This script contains the following optional parameters:
#  
#    Optional parameters:
#      $1 (WSA_OPERATOR_NAMESPACE) - the namespace containing the IBM WebSphere Automation Operator install
#      $2 (WSA_INSTANCE_NAMESPACE) - the namespace containing the "WebSphereAutomation" custom resource instance
# 
#  Usage:
#    1. arguments - ./preserve-ics.sh <WSA_OPERATOR_NAMESPACE> <WSA_INSTANCE_NAMESPACE>
#    2. stdin     - ./preserve-ics.sh
#  
#-------------------------------------------------------------------------------------------------------
readonly usage="Usage: $0 --operator-namespace <WSA_OPERATOR_NAMESPACE> --instance-namespace <WSA_INSTANCE_NAMESPACE>
                           [--cert-manager-namespace <CERT_MANAGER_NAMESPACE>]
                           [--licensing-service-namespace <LICENSING_SERVICE_NAMESPACE>]
                           [--cert-manager-catalog-source <CERT_MANAGER_CATALOG_SOURCE>]
                           [--licensing-service-catalog-source <LICENSING_SERVICE_CATALOG_SOURCE>]
                           [--common-services-catalog-source <COMMON_SERVICES_CATALOG_SOURCE>]
                           [--common-services-upgrade-channel <COMMON_SERVICES_UPGRADE_CHANNEL>]
                           [--common-services-case-version <COMMON_SERVICES_CASE_VERSION>]
                           [--skip-checks]"
readonly scriptName="$0"

set -o pipefail

. ./utils.sh

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --operator-namespace)
                shift
                readonly WSA_OPERATOR_NAMESPACE="${1}"
                ;;
            --instance-namespace)
                shift
                readonly WSA_INSTANCE_NAMESPACE="${1}"
                ;;
            --common-services-upgrade-channel)
                shift
                readonly COMMON_SERVICES_UPGRADE_CHANNEL="${1}"
                ;;
            --common-services-case-version)
                shift
                readonly COMMON_SERVICES_CASE_VERSION="${1}"
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
            --skip-checks)
                readonly SKIP_CHECKS="true"
                ;;
            *)
                echo "Error: Invalid argument - $1"
                echo "$usage"
                exit 1
            ;;
        esac
        shift
    done
}

check_args() {    
    if [[ -z "${WSA_OPERATOR_NAMESPACE}" ]]; then
        echo "==> Error: Must set the WebSphere Automation Operator's namespace. Exiting."
        echo "${usage}"
        exit 1
    fi

    if [[ -z "${WSA_INSTANCE_NAMESPACE}" ]]; then
        echo "==> Error: Must set the WebSphere Automation instance's namespace. Exiting."
        echo "${usage}"
        exit 1
    fi

    if [[ -z "${COMMON_SERVICES_UPGRADE_CHANNEL}" ]]; then
        echo "==> Common Services upgrade channel not set. Setting as v4.4."
        COMMON_SERVICES_UPGRADE_CHANNEL="v4.4"
    else
      IFS='.' read -r -a channelArray <<< "$COMMON_SERVICES_UPGRADE_CHANNEL"
      if [[ ! $COMMON_SERVICES_UPGRADE_CHANNEL = v* ]] || [[ "${#channelArray[@]}" != "2" ]]; then
        echo "==> Error: You must provide a channel in a format such as 'v4.4'."
        exit
      fi 
    fi

    if [[ -z "${COMMON_SERVICES_CASE_VERSION}" ]]; then
        echo "==> Common Services case version is not set. Setting as 4.4.0"
        COMMON_SERVICES_CASE_VERSION="4.4.0"
    else
        IFS='.' read -r -a semVersionArray <<< "$COMMON_SERVICES_CASE_VERSION"
        if [[ "${#semVersionArray[@]}" != "3" ]]; then
          echo "==> Error: You must provide the Common Services case version in semantic version format, such as '4.4.0'."
          exit
        else
          commonServicesURL="https://github.com/IBM/cloud-pak/raw/master/repo/case/ibm-cp-common-services/${COMMON_SERVICES_CASE_VERSION}/ibm-cp-common-services-${COMMON_SERVICES_CASE_VERSION}.tgz"
          if ! curl -f -I -s "$commonServicesURL" >/dev/null; then
            echo "==> Error: The Common Services case version provided does not correspond to a valid ibm-cp-common-services release. Check https://github.com/IBM/cloud-pak/raw/master/repo/case/ibm-cp-common-services for a list of available versions."
            exit
          fi         
        fi
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
        CERT_MANAGER_CATALOG_SOURCE="ibm-cert-manager-catalog"
    fi

    if [[ -z "${LICENSING_SERVICE_CATALOG_SOURCE}" ]]; then
        echo "==> Licensing Service CatalogSource not set. Setting as ibm-licensing-catalog."
        LICENSING_SERVICE_CATALOG_SOURCE="ibm-licensing-catalog" 
    fi

    if [[ -z "${COMMON_SERVICES_CATALOG_SOURCE}" ]]; then
        echo "==> Common Services CatalogSource not set. Setting as ibm-operator-catalog."
        COMMON_SERVICES_CATALOG_SOURCE="ibm-operator-catalog"
    elif [[ "${COMMON_SERVICES_CATALOG_SOURCE}" != "ibm-operator-catalog" ]]; then
        # Validate whether or not all the required catalog sources exist
        check_catalog_source "$COMMON_SERVICES_CATALOG_SOURCE"
        check_catalog_source "$LICENSING_SERVICE_CATALOG_SOURCE"
        check_catalog_source "$CERT_MANAGER_CATALOG_SOURCE"
        check_catalog_source "ibm-license-service-reporter-bundle-catalog"
        check_catalog_source "cloud-native-postgresql-catalog"
    fi

    if [[ -z "${SKIP_CHECKS}" ]]; then
        echo "==> Skip Checks flag not set. Setting as false."
        SKIP_CHECKS="false"
    fi

    echo "==> WebSphere Automation operator namespace is set to: $WSA_OPERATOR_NAMESPACE"
    echo "==> WebSphere Automation instance namespace is set to: $WSA_INSTANCE_NAMESPACE"
    echo "==> Cert Manager namespace is set to: $CERT_MANAGER_NAMESPACE"
    echo "==> Licensing Service namespace is set to: $LICENSING_SERVICE_NAMESPACE"
    echo "==> Cert Manager CatalogSource is set to: $CERT_MANAGER_CATALOG_SOURCE"
    echo "==> Licensing Service CatalogSource is set to: $LICENSING_SERVICE_CATALOG_SOURCE"
    echo "==> Common Services CatalogSource is set to: $COMMON_SERVICES_CATALOG_SOURCE"
    echo "==> Common Services upgrade channel is set to: $COMMON_SERVICES_UPGRADE_CHANNEL"
    echo "==> Common Services case version is set to: $COMMON_SERVICES_CASE_VERSION"
    echo "==> Skip checks is set to: $SKIP_CHECKS"
}

# Start here
if [[ ! $(which yq 2>/dev/null) ]]; then
  echo "You must install 'yq' before proceeding with the upgrade script. Exiting."
  exit 1 
fi
check_yq_version
parse_args "$@"
check_args
if [[ "$SKIP_CHECKS" == "false" ]]; then
    validate_user_input $WSA_OPERATOR_NAMESPACE $WSA_INSTANCE_NAMESPACE
    # Check that CommonServices exists before upgrading
    is_wsa_migratable_version $WSA_OPERATOR_NAMESPACE
    is_less_than_ics_upgraded_version $WSA_OPERATOR_NAMESPACE

    # Check if Common Services operator is greater than or equal to 3.23.12
    detect_cs_install $WSA_INSTANCE_NAMESPACE
    cs_ns=$(oc get operandrequest -n $WSA_INSTANCE_NAMESPACE websphereauto -o yaml | grep "registryNamespace: " | cut -d ":" -f2 | tr -d " ")
    is_greater_than_or_equal_to_ics_compat_version $cs_ns

    # Scale WSA down to reduce load on Nodes
    scale_to_zero "true" $WSA_INSTANCE_NAMESPACE
    sleep 120
    wait_for_wsa_ready 50 $WSA_OPERATOR_NAMESPACE $WSA_INSTANCE_NAMESPACE
    echo "  > Successfully scaled down WebSphere Automation, Health and Secure replicas!"
else
    echo "==> Skipping WebSphere Automtation and Common Services operator checks..."
fi
echo "==> Starting IBM Cloud Pak foundational services upgrade..."

# Find CS namespace
COMMON_SERVICES_NAMESPACE=$(oc get operandrequest -n $WSA_INSTANCE_NAMESPACE websphereauto -o yaml | grep "registryNamespace: " | cut -d ":" -f2 | tr -d " ")
if [[ "$COMMON_SERVICES_NAMESPACE" == "$WSA_OPERATOR_NAMESPACE" ]]; then
  echo "The IBM Cloud Pak foundational services has already been upgraded! Exiting."
  exit 1
fi

cs_operator_name=$(oc get subscription -n $WSA_OPERATOR_NAMESPACE -o name | grep "ibm-common-service-operator-v" | cut -d "/" -f2)
export new_sub_name="ibm-common-service-operator-$COMMON_SERVICES_UPGRADE_CHANNEL-$COMMON_SERVICES_CATALOG_SOURCE-openshift-marketplace"
if [[ "$cs_operator_name" != "$new_sub_name" ]]; then 
    # Delete WSA to get OLM dependency removed
    delete_operator "ibm-websphere-automation" $WSA_OPERATOR_NAMESPACE

    oc get webspheresecure -o name -n $WSA_INSTANCE_NAMESPACE | xargs oc patch --subresource=status -n $WSA_INSTANCE_NAMESPACE -p '{"status":{"references":{"translationChecksumUI":null}}}' --type=merge

    create_network_policies $WSA_INSTANCE_NAMESPACE "true"

    oc new-project $CERT_MANAGER_NAMESPACE
    oc new-project $LICENSING_SERVICE_NAMESPACE

    wget https://github.com/IBM/cloud-pak/raw/master/repo/case/ibm-cp-common-services/${COMMON_SERVICES_CASE_VERSION}/ibm-cp-common-services-${COMMON_SERVICES_CASE_VERSION}.tgz
    tar -xvzf ibm-cp-common-services-$COMMON_SERVICES_CASE_VERSION.tgz

    # Apply CP3 network policies
    cd ibm-cp-common-services/inventory/ibmCommonServiceOperatorSetup/installer_scripts/
    cd ./cp3-networkpolicy/
    ./install_networkpolicy.sh -n $WSA_INSTANCE_NAMESPACE -o $WSA_OPERATOR_NAMESPACE --licensing-namespace $LICENSING_SERVICE_NAMESPACE --cert-manager-namespace $CERT_MANAGER_NAMESPACE
    cd ../

    ./preload_data.sh --original-cs-ns $COMMON_SERVICES_NAMESPACE --services-ns $WSA_OPERATOR_NAMESPACE
    ./cp3pt0-deployment/setup_singleton.sh --operator-namespace $COMMON_SERVICES_NAMESPACE --enable-licensing --cert-manager-source $CERT_MANAGER_CATALOG_SOURCE --licensing-source $LICENSING_SERVICE_CATALOG_SOURCE --license-accept -v 1
    ./cp3pt0-deployment/setup_tenant.sh --operator-namespace $WSA_OPERATOR_NAMESPACE --services-namespace $WSA_OPERATOR_NAMESPACE --tethered-namespace $WSA_OPERATOR_NAMESPACE --source $COMMON_SERVICES_CATALOG_SOURCE --license-accept
    cd ../../../../
    oc patch operandrequest websphereauto -n $WSA_INSTANCE_NAMESPACE --type=json -p="[{\"op\": \"add\", \"path\": \"/spec/requests\", \"value\": [{\"operands\": [{\"name\": \"ibm-events-operator\"},{\"name\": \"ibm-platformui-operator\"}],\"registry\": \"common-service\",\"registryNamespace\": \"$WSA_OPERATOR_NAMESPACE\"}]}]"
else
    echo "==> IBM CloudPak foundational services operator is already upgraded to channel $COMMON_SERVICES_UPGRADE_CHANNEL."
fi

# # If this is an air-gapped install, delete the Zen operator in ibm-common-services
# if [[ ! -z "${COMMON_SERVICES_CATALOG_SOURCE}" ]]; then
#     delete_operator "ibm-zen-operator" $COMMON_SERVICES_NAMESPACE
# fi

# Wait for ZenService to load to 5.*
wait_for_zen_service $WSA_OPERATOR_NAMESPACE "$scriptName"

# Rename the cp-console user from "admin" to "cpadmin"
./update-cp-user.sh $WSA_OPERATOR_NAMESPACE

# Restore WSA, WSS, WSH replicas
scale_to_zero "false" $WSA_INSTANCE_NAMESPACE

delete_network_policies $WSA_INSTANCE_NAMESPACE

rm ibm-cp-common-services-$COMMON_SERVICES_CASE_VERSION.tgz
rm -r ibm-cp-common-services

echo "==> The IBM Cloud Pak foundational services upgrade has completed!"
echo "    Your OpenShift cluster is ready to install IBM WebSphere Automation Operator version >=1.7.0."
echo "    To continue this migration, please install the latest driver in the OpenShift UI using OperatorHub."
