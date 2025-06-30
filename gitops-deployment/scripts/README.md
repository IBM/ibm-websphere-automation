# Uprading IBM Cloudpak Foundational Services

### Note:
The following instructions and the script under `/gitops-deployment/scripts` are to be followed only if WSA was previously setup using ArgoCD, and needs to upgrade to a newer version of WSA.

CPFS upgrades are not handled by WSA's Helm charts but a `upgrade-cpfs.sh` script has been provided under `/gitops-deployment/scripts` directory that can help you upgrade CPFS to a later version.

If you plan to upgrade WSA, make sure to check out the table below to see the version(s) of CPFS, that WSA supports. 

| IBM WebSphere Automation Version | Supported CPFS Versions| 
| --------------------------- | --------------------------- |
| v1.8.2 | 4.9.0, 4.10.0 |
| v1.9.0 | 4.10.0, 4.11.0, 4.12.0 |

## Before you begin
You must have yq installed to run the script. If you do not have yq installed, run the following code snippet. If your architecture is different than the one indicated by the BINARY parameter, change the value of the BINARY parameter to the appropriate value from the list on this page: https://github.com/mikefarah/yq/releases/latest External link icon.

```bash
BINARY=yq_linux_amd64 
wget https://github.com/mikefarah/yq/releases/latest/download/${BINARY} -O /usr/bin/yq && chmod +x /usr/bin/yq
``` 

## Downloading the CPFS upgrade script
Download the `upgrade-cpfs.sh` installation script under `/gitops-deployment/scripts`. If you have previously downloaded this script, download it again to make sure that you have the most recent instance. The script is occasionally updated.

Run the following command:
```bash
chmod +x upgrade-cpfs.sh
```

## Running the CPFS Upgrade Script

```bash
./update-cpfs.sh --instance-namespace <WSA_INSTANCE_NAMESPACE> --common-services-case-version <COMMON_SERVICES_CASE_VERSION>
                        [--common-services-catalog-source <COMMON_SERVICES_CATALOG_SOURCE>]
                        [--all-namespaces]
```                     

The `--instance-namespace` & `--common-services-case-version` flags are required parameters. Other flags are optional. If they are not specified, the following default values are used.

```bash
COMMON_SERVICES_CATALOG_SOURCE = ibm-operator-catalog
INSTALL_MODE = OwnNamespace
```

## Examples

In the following examples, if optional flags are not defined, default values are used. Use the optional flags to specify values that are different than the default ones.

Change the namespace values in the following example to match the namespace you have defined in your cluster and update CPFS version following the table given above.

For OwnNamespace or SingleNamespace mode with default values, run:
```bash
./update-cpfs.sh --instance-namespace websphere-automation --common-services-case-version 4.12.0
```