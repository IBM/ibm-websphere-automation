#!/bin/bash

#
# IBM Confidential
# OCO Source Materials
# 5900-AH1
#
# (C) Copyright IBM Corp. 2024
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
#       --cert-manager-namespace $CERT_MANAGER_NAMESPACE - the namespace where IBM Cert Manager operator will be installed. Defaults to ibm-cert-manager.
#       --licensing-service-namespace $LICENSING_SERVICE_NAMESPACE - the namespace where IBM Licensing operator will be installed. Defaults to ibm-licensing.
#       --cert-manager-catalog-source $CERT_MANAGER_CATALOG_SOURCE - the catalog source name for IBM Cert Manager operator. Defaults to ibm-cert-manager-catalog.
#       --licensing-service-catalog-source $LICENSING_SERVICE_CATALOG_SOURCE - the catalog source name for IBM Licensing operator. Defaults to ibm-licensing-catalog.
#       --common-services-case-version $COMMON_SERVICES_CASE_VERSION - Case version of IBM Cloud Pak foundational services (Common Services) to be installed. Defaults to 4.4.0.
#       --all-namespaces - only declare when you will be installing IBM WebSphere Automation Operator in AllNamespaces install mode.
# 
#   Usage:
#       ./install-prereq.sh --instance-namespace <WSA_INSTANCE_NAMESPACE>
#                           [--cert-manager-namespace <CERT_MANAGER_NAMESPACE>]
#                           [--licensing-service-namespace <LICENSING_SERVICE_NAMESPACE>]
#                           [--cert-manager-catalog-source <CERT_MANAGER_CATALOG_SOURCE>]
#                           [--licensing-service-catalog-source <LICENSING_SERVICE_CATALOG_SOURCE>]
#                           [--common-services-case-version <COMMON_SERVICES_CASE_VERSION>]
#                           [--all-namespaces]
#  
#-------------------------------------------------------------------------------------------------------


readonly usage="Usage: $0 --instance-namespace <WSA_INSTANCE_NAMESPACE>
                           [--cert-manager-namespace <CERT_MANAGER_NAMESPACE>]
                           [--licensing-service-namespace <LICENSING_SERVICE_NAMESPACE>]
                           [--cert-manager-catalog-source <CERT_MANAGER_CATALOG_SOURCE>]
                           [--licensing-service-catalog-source <LICENSING_SERVICE_CATALOG_SOURCE>]
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
        CERT_MANAGER_CATALOG_SOURCE="ibm-cert-manager-catalog"
    fi

    if [[ -z "${LICENSING_SERVICE_CATALOG_SOURCE}" ]]; then
        echo "==> Licensing Service CatalogSource not set. Setting as ibm-licensing-catalog."
        LICENSING_SERVICE_CATALOG_SOURCE="ibm-licensing-catalog"
    fi

    if [[ -z "${COMMON_SERVICES_CASE_VERSION}" ]]; then
        echo "==> Common Services case version is not set. Setting as 4.4.0."
        COMMON_SERVICES_CASE_VERSION=4.4.0
    fi

    echo "***********************************************************************"
    echo "Configuration Details:"
    echo "      Install mode: ${INSTALL_MODE}"
    echo "      WebSphere Automation operator namespace: ${WSA_OPERATOR_NAMESPACE}"
    echo "      WebSphere Automation instance namespace: ${WSA_INSTANCE_NAMESPACE}"
    echo "      Cert Manager namespace: ${CERT_MANAGER_NAMESPACE}"
    echo "      Licensing Service namespace: ${LICENSING_SERVICE_NAMESPACE}"
    echo "      Cert Manager CatalogSource: ${CERT_MANAGER_CATALOG_SOURCE}"
    echo "      Licensing Service CatalogSource: ${LICENSING_SERVICE_CATALOG_SOURCE}"
    echo "      Common Services case version: ${COMMON_SERVICES_CASE_VERSION}"
    echo "***********************************************************************"
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
    ./cp3pt0-deployment/setup_singleton.sh --operator-namespace ${WSA_OPERATOR_NAMESPACE} --cert-manager-namespace ${CERT_MANAGER_NAMESPACE} --licensing-namespace ${LICENSING_SERVICE_NAMESPACE} --enable-licensing --cert-manager-source ${CERT_MANAGER_CATALOG_SOURCE} --licensing-source ${LICENSING_SERVICE_CATALOG_SOURCE} --license-accept -v 1
    if [ "$?" != "1" ]; then
        echo "Successfully installed IBM Cert Manager and IBM Licensing operators!"
        echo ""
    else
        echo ""
        echo "Error installing IBM Cert Manager and IBM Licensing operators."
        echo "Please check error logs."
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
