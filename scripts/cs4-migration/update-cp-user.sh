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
# update-cp-user.sh - Helper script to update the IBM IAM user from username 'admin' to 'cpadmin'
#-------------------------------------------------------------------------------------------------------
#
#  This script updates the IAM user 'admin' to 'cpadmin'.
#
#  Since IBM Cloud Pak foundational services 4.x changed the default IAM user's username to 'cpadmin',
#  this script is used to modify the username to adhere to 4.x naming conventions when coming from a
#  3.x installation (In the past, IBM Cloud Pak foundational services 3.x set the default IAM user's
#  username to 'admin').
#
#  Prerequisites: The ./preload-data.sh script must have successfully ran prior to running this script.
#  Failing to run the preload-data.sh script correctly may cause the IAM service not to be ready.
#
#  Usage: ./update-cp-user.sh <CS_NS>
#
#-------------------------------------------------------------------------------------------------------
set -o nounset
set -eo pipefail
CS_NS=$1

wait_for_iam_ready() {
    NS=$1
    retries=100
    while true; do
        echo "==> Waiting for authentication.operator.ibm.com 'example-authentication' in namespace '$NS' to become ready... ($retries retries left)"
        ready_status=$(oc -n $NS get authentication.operator.ibm.com example-authentication -o json | yq -r '.status.service.status' || echo "NotReady")
        [[ "$ready_status" == "Ready" ]] && break
        ((retries -= 1))
        if ((retries < 0)); then
            echo "  > Waited too long for 'example-authentication' to load. You must resolve the failing resources and re-run the script './update-cp-user.sh $NS' to finish the upgrade."
            exit 1
        fi
        sleep 10
    done
    echo "==> authentication.operator.ibm.com 'example-authentication' is ready!"
}

# The IAM needs to be ready before changing the admin username.
wait_for_iam_ready $CS_NS

IDMANAGER_INGRESS_PATH="/idmgmt/identity/api/v1/"
IDPROVIDER_INGRESS_PATH="/idprovider/"
CP_CONSOLE="$(oc -n ${CS_NS} get route cp-console -o=jsonpath='{.spec.host}')"

# Obtain access token
username="$(oc -n ${CS_NS} get secret platform-auth-idp-credentials -o jsonpath='{.data.admin_username}' | base64 --decode)"
password="$(oc -n ${CS_NS} get secret platform-auth-idp-credentials -o jsonpath='{.data.admin_password}' | base64 --decode)"
access_token=$(curl \
    --location \
    --request POST \
    --insecure \
    --silent \
    --header "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "scope=openid" \
    --data-urlencode "username=${username}" \
    --data-urlencode "password=${password}" \
    "https://${CP_CONSOLE}${IDPROVIDER_INGRESS_PATH}v1/auth/identitytoken" | yq -r '.access_token')

# Change name to cpadmin
new_name="cpadmin"
status=$(curl \
    --location \
    --request PUT \
    --insecure \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json' \
    --header "Authorization: Bearer ${access_token}" \
    -d "{\"username\": \"${new_name}\"}" \
    "https://${CP_CONSOLE}${IDMANAGER_INGRESS_PATH}users/defaultAdmin" | yq '.status')
if [[ "$status" != "success" ]]; then
    echo "==> Failed to update username from admin to cpadmin"
    echo "  > Re-run the script with the --skip-checks flag to retry the migration."
    exit 1
fi

# Restart platform pods to update user
# Follow https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.8?topic=configurations-changing-cluster-administrator-access-credentials
platform_identity_provider_pod=$(oc -n $CS_NS get pods -o name | grep platform-identity-provider | cut -d "/" -f2)
platform_auth_service_pod=$(oc -n $CS_NS get pods -o name | grep platform-auth-service | cut -d "/" -f2)

oc -n $CS_NS delete pod $platform_identity_provider_pod || true
oc -n $CS_NS delete pod $platform_auth_service_pod || true

echo "==> Changed user admin to cpadmin"

# Follow https://www.ibm.com/docs/en/cloud-paks/foundational-services/4.8?topic=login-cannot-log-in-console-after-reinstallation-foundational-services
oc -n $CS_NS delete job oidc-client-registration || true

common_web_pod=$(oc -n $CS_NS get pods -o name | grep common-web-ui | cut -d "/" -f2)
oc -n $CS_NS delete pod $common_web_pod || true

echo "==> Restarted CommonWebUI"
