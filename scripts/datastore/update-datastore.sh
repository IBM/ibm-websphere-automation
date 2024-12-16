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
# update-datastore.sh - 
# Updates featureCompatibilityVersion of current datastore to required version
#-------------------------------------------------------------------------------------------------------
#
#
#   This script contains the following parameters:
#   Required parameters:
#       --instance-namespace $WSA_INSTANCE_NAMESPACE - the namespace where the instance of WebSphere Automation custom resources (CR) (i.e "WebSphereAutomation") are.
# 
#   Usage:
#       ./update-datastore.sh --instance-namespace <WSA_INSTANCE_NAMESPACE>
#  
#-------------------------------------------------------------------------------------------------------

readonly usage="Usage: $0  --instance-namespace <WSA_INSTANCE_NAMESPACE>"

set -o pipefail

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --instance-namespace)
                shift
                readonly WSA_INSTANCE_NAMESPACE="${1}"
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
}



main () {
    parse_args "$@"
    check_args

    NEW_FCV_VERSION="5.0"
    tls_args=(--tls --tlsCAFile /data/configdb/tls.crt --tlsCertificateKeyFile /work-dir/mongo.pem)

    # Get the pod names containing "wsa-mongo"
    WSA_AUTOMATION_CR=$(oc get websphereautomation -o name -n $WSA_INSTANCE_NAMESPACE | cut -d/ -f2) 
    POD_NAMES=($(oc get pods -n $WSA_INSTANCE_NAMESPACE | grep $WSA_AUTOMATION_CR-mongo | awk '{print $1}'))

    # Check if any mongo pods were found in the namespace
    if [ ${#POD_NAMES[@]} -eq 0 ]; then
        echo "No mongo pods were found in namespace $WSA_INSTANCE_NAMESPACE. Exiting."
        exit 1
    fi

    #check if datastore is ready
    if [[ $(oc get websphereautomation $WSA_AUTOMATION_CR -o jsonpath='{.status.conditions[?(@.type=="DataStoreReady")].status}' -n $WSA_INSTANCE_NAMESPACE) == "False" ]]; then
        echo "Datastore is not ready. Exiting."
        exit 1
    fi

    #get admin creds from creds file
    FIRST_POD="${POD_NAMES[0]}" 
    credentials_file='/work-dir/credentials.txt'
    admin_user=$(oc exec -n "$WSA_INSTANCE_NAMESPACE" "$FIRST_POD" -- head -n 1 "$credentials_file")
    admin_password=$(oc exec -n "$WSA_INSTANCE_NAMESPACE" "$FIRST_POD" -- tail -n 1 "$credentials_file")

    if [[ -z "$admin_user" || -z "$admin_password" ]]; then
        echo "Invalid Username or password. Exiting."
        exit 1
    fi
    admin_args=(-u "$admin_user" -p "$admin_password")

    #Check if FCV is already at required version
    CURRENT_FCV_VERSION=$(oc exec -n "$WSA_INSTANCE_NAMESPACE" "$FIRST_POD" -- mongo --quiet --host localhost ${tls_args[@]} ${admin_args[@]} --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion.version")
    echo "Current FCV: $CURRENT_FCV_VERSION"
    if [[ $CURRENT_FCV_VERSION == $NEW_FCV_VERSION ]]; then
        echo "Already at required FCV. Ready to upgrade to 1.8.0"
        exit 0  
    fi

    oc rsh -n $WSA_INSTANCE_NAMESPACE $FIRST_POD <<EOF
    mongo --host localhost --quiet ${tls_args[@]} ${admin_args[@]} <<-EOJS
        var status = rs.status();
        var recovering = status.members.some(function(m) { return m.stateStr === "RECOVERING"; });
        var rollback = status.members.some(function(m) { return m.stateStr === "ROLLBACK"; });
        if (recovering || rollback) {
            quit(1);
        }
        quit(0);
EOJS
EOF
    if [[ $? -eq 1 ]]; then
        echo "Some replicas are in RECOVERING or ROLLBACK state. Cannot update FCV while in this state. Exiting."
        exit 1
    fi

    #looping thru pods to find primary
    for POD_NAME in "${POD_NAMES[@]}"; do
        if [[ $(oc exec -n $WSA_INSTANCE_NAMESPACE $POD_NAME -- mongo --host localhost --quiet ${tls_args[@]} ${admin_args[@]} --eval "db.runCommand('ismaster').ismaster") == "true" ]]; then
            PRIMARY_POD="$POD_NAME"
            break
        fi
    done

    if [[ -z "$PRIMARY_POD" ]]; then
        echo "Could not find primary. Exiting."
        exit 1
    fi
    echo "Found Primary: $PRIMARY_POD"

    #change fcv to new version
    if [[ $(oc exec -n $WSA_INSTANCE_NAMESPACE $PRIMARY_POD -- mongo --host localhost --quiet  ${tls_args[@]} ${admin_args[@]} --eval  "db.adminCommand({setFeatureCompatibilityVersion: '$NEW_FCV_VERSION'}).ok") == "1" ]];then
        echo "FCV successfully changed. Ready to upgrade to 1.8.0"
        exit 0
    else
        echo "Failed to change FCV. Exiting."
        exit 1
    fi
}

main "$@"