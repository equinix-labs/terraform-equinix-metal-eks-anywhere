# EKS-A Baremetal on Equinix Metal

[![Experimental](https://img.shields.io/badge/Stability-Experimental-red.svg)](https://github.com/equinix-labs/standards#about-uniform-standards)
[![terraform](https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere/actions/workflows/integration.yaml/badge.svg)](https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere/actions/workflows/integration.yaml)

> **[Experimental](https://github.com/equinix-labs/equinix-labs/blob/main/experimental-statement.md)**
> This project is experimental and a work in progress. Use at your own risk and do not expect thorough support!

This project deploys EKS-A Anywhere on Baremetal on Equinix Metal using the minimum requirements.

See <https://aws.amazon.com/blogs/containers/getting-started-with-eks-anywhere-on-bare-metal/> for more information about EKS-A on Bare Metal.

## Compatible Plans

EKS-A requires UEFI booting, which is supported by the following Equinix Metal On Demand plans:

* m3.small.x86
* m3.large.x86
* n3.xlarge.x86
* a3.large.x86

## Using Terraform

With your [Equinix Metal account, project, and a **User** API token](https://metal.equinix.com/developers/docs/accounts/users/), you can use [Terraform v1+](https://learn.hashicorp.com/tutorials/terraform/install-cli) to install a proof-of-concept demonstration environment for EKS-A on Baremetal. 

Create a [`terraform.tfvars` file](https://www.terraform.io/language/values/variables#assigning-values-to-root-module-variables) in the root of this project with `metal_api_token` and `project_id` defined. These are the required variables needed to run `terraform apply`.  See `variables.tf` for additional settings that you may wish to customize.

```ini
# terraform.fvars
metal_api_token="...your Metal User API Token here..."
project_id="...your Metal Project API Token here..."
```

> **Note**
> Project API Tokens can not be used to access some Gateway features used by this project. A User API Token is required.

Terraform will create an Equinix Metal VLAN, Metal Gateway, IP Reservation, and Equinix Metal servers to act as the EKS-A Admin node and worker devices. Terraform will also create the initial `hardware.csv` with the details of each server and register this with the `eks-anywhere` CLI to create the cluster. The worker nodes will be provisioned through Tinkerbell to act as a control-plane node and a worker-node.

Once complete, you'll see the following output:

```sh
$ terraform apply
... (~12m later)
Apply complete! Resources: 19 added, 0 changed, 0 destroyed.

Outputs:

eksa_admin_ip = "203.0.113.3"
eksa_admin_ssh_key = "/Users/username/.ssh/my-eksa-cluster-xed"
eksa_admin_ssh_user = "root"
eksa_nodes_sos = tomap({
  "eksa-node-cp-001" = "b0e1426d-4d9e-4d01-bd5c-54065df61d67@sos.sv15.platformequinix.com"
  "eksa-node-dp-001" = "84ffa9c7-84ce-46eb-97ff-2ae310fbb360@sos.sv15.platformequinix.com"
})
```

SSH into the EKS-A Admin node and follow the EKS-A on Baremetal instructions to continue within the Kubernetes environment.

```sh
ssh -i $(terraform output -json | jq -r .eksa_admin_ssh_key.value) root@$(terraform output -json | jq -r .eksa_admin_ip.value)
```

```sh
root@eksa-admin:~# KUBECONFIG=/root/my-eksa-cluster/my-eksa-cluster-eks-a-cluster.kubeconfig kubectl  get nodes
NAME               STATUS   ROLES                  AGE     VERSION
eksa-node-cp-001   Ready    control-plane,master   7m56s   v1.22.10-eks-7dc61e8
eksa-node-dp-001   Ready    <none>                 5m30s   v1.22.10-eks-7dc61e8
```

## Manual Installation

> **Note**
> This section will serve as manual instructions for installing EKS-A Bare Metal on Equinix Metal. The Terraform install above performs all of these steps for you.
> These instructions offer a step-by-step install with copy+paste commands that simplify the process.  Refer to the [open issues](https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere/issues) and please open issues if you encounter something not represented there.

Steps below align with [EKS-A on Bare Metal instructions](https://anywhere.eks.amazonaws.com/docs/reference/baremetal/). While the steps below are intended to be complete, follow along with the EKS-A Install guide for best results.

### Known Issues

_None Currently_.

If you run into something unexpected, after [checking the open issues](https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere/issues), [open a new issue reporting your experience](https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere/issues/new).

### Pre-requisites

The following tools will be needed on your local development environment where you will be running most of the commands in this guide.

* A Unix-like environment (Linux, OSX, [Windows WSL](https://docs.microsoft.com/en-us/windows/wsl/install))
* [jq](https://stedolan.github.io/jq/download/)
* [metal-cli](https://github.com/equinix/metal-cli) (v0.9.0+)

### Steps to run locally and in the Equinix Metal Console

1. Create an EKS-A Admin machine:
   Using the [metal-cli](https://github.com/equinix/metal-cli):

   Create an [API Key](https://console.equinix.com/users/-/api-keys) and register it with the Metal CLI:

   ```sh
   metal init
   ```

   ```sh
   metal device create --plan=m3.small.x86 --metro=da --hostname eksa-admin --operating-system ubuntu_20_04
   ```

1. Create a VLAN:

     ```sh
     metal vlan create --metro da --description eks-anywhere --vxlan 1000
     ```

1. Create a Public IP Reservation (16 addresses):

     ```sh
     metal ip request --metro da --type public_ipv4 --quantity 16 --tags eksa
     ```

     These variables will be referred to in later steps in executable snippets to refer to specific addresses within the pool. The correct IP reservation is chosen by looking for and expecting a single IP reservation to have the "eksa" tag applied.

     ```sh
     #Capture the ID, Network, Gateway, and Netmask using jq
     VLAN_ID=$(metal vlan list -o json | jq -r '.virtual_networks | .[] | select(.vxlan == 1000) | .id')
     POOL_ID=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .id')
     POOL_NW=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .network')
     POOL_GW=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .gateway')
     POOL_NM=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .netmask')
     # POOL_ADMIN will be assigned to eksa-admin within the VLAN
     POOL_ADMIN=$(python3 -c 'import ipaddress; print(str(ipaddress.IPv4Address("'${POOL_GW}'")+1))')
     # PUB_ADMIN is the provisioned IPv4 public address of eks-admin which we can use with ssh
     PUB_ADMIN=$(metal devices list  -o json  | jq -r '.[] | select(.hostname=="eksa-admin") | .ip_addresses [] | select(contains({"public":true,"address_family":4})) | .address')
     # PORT_ADMIN is the bond0 port of the eks-admin machine
     PORT_ADMIN=$(metal devices list  -o json  | jq -r '.[] | select(.hostname=="eksa-admin") | .network_ports [] | select(.name == "bond0") | .id')
     # POOL_VIP is the floating IPv4 public address assigned to the current lead kubernetes control plane
     POOL_VIP=$(python3 -c 'import ipaddress; print(str(ipaddress.ip_network("'${POOL_NW}'/'${POOL_NM}'").broadcast_address-1))')
     TINK_VIP=$(python3 -c 'import ipaddress; print(str(ipaddress.ip_network("'${POOL_NW}'/'${POOL_NM}'").broadcast_address-2))')
     ```

1. Create a Metal Gateway

    ```sh
    metal gateway create --ip-reservation-id $POOL_ID --virtual-network $VLAN_ID
    ```

1. Create Tinkerbell worker nodes `eksa-node-001` - `eksa-node-002` with Custom IPXE <http://{eks-a-public-address>}. These nodes will be provisioned as EKS-A Control Plane *OR* Worker nodes.

     ```sh
     for a in {1..2}; do
       metal device create --plan m3.small.x86 --metro da --hostname eksa-node-00$a \
         --ipxe-script-url http://$POOL_ADMIN/ipxe/  --operating-system custom_ipxe
     done
     ```

   Note that the `ipxe-script-url` doesn't actually get used in this process, we're just setting it as it's a requirement for using the custom_ipxe operating system type.

1. Add the vlan to the eks-admin bond0 port:

      ```sh
      metal port vlan -i $PORT_ADMIN -a $VLAN_ID
      ```

      Configure the layer 2 vlan network on eks-admin with this snippet:

      ```sh
      ssh root@$PUB_ADMIN tee -a /etc/network/interfaces << EOS

      auto bond0.1000
      iface bond0.1000 inet static
        pre-up sleep 5
        address $POOL_ADMIN
        netmask $POOL_NM
        vlan-raw-device bond0
      EOS
      ```

      Activate the layer 2 vlan network with this command:

      ```sh
      ssh root@$PUB_ADMIN systemctl restart networking
      ```

1. Convert `eksa-node-*` 's network ports to Layer2-Unbonded and attach to the VLAN.

      ```sh
      node_ids=$(metal devices list -o json | jq -r '.[] | select(.hostname | startswith("eksa-node")) | .id')

      i=1 # We will increment "i" for the eksa-node-* nodes. "1" represents the eksa-admin node.

      for id in $(echo $node_ids); do
         let i++
         BOND0_PORT=$(metal devices get -i $id -o json  | jq -r '.network_ports [] | select(.name == "bond0") | .id')
         ETH0_PORT=$(metal devices get -i $id -o json  | jq -r '.network_ports [] | select(.name == "eth0") | .id')
         metal port convert -i $BOND0_PORT --layer2 --bonded=false --force
         metal port vlan -i $ETH0_PORT -a $VLAN_ID
      done
      ```

1. Capture the MAC Addresses and create `hardware.csv` file on `eks-admin` in `/root/` (run this on the host with metal cli on it):
   1. Create the CSV Header:

      ```sh
      echo hostname,vendor,mac,ip_address,gateway,netmask,nameservers,disk,labels > hardware.csv
      ```

   1. Use `metal` and `jq` to grab HW MAC addresses and add them to the hardware.csv:

      ```sh
      node_ids=$(metal devices list -o json | jq -r '.[] | select(.hostname | startswith("eksa-node")) | .id')

      i=1 # We will increment "i" for the eksa-node-* nodes. "1" represents the eksa-admin node.

      for id in $(echo $node_ids); do
         # Configure only the first node as a control-panel node
         if [ "$i" = 1 ]; then TYPE=cp; else TYPE=dp; fi; # change to 3 for HA
         NODENAME="eks-node-00$i"
         let i++
         MAC=$(metal device get -i $id -o json | jq -r '.network_ports | .[] | select(.name == "eth0") | .data.mac')
         IP=$(python3 -c 'import ipaddress; print(str(ipaddress.IPv4Address("'${POOL_GW}'")+'$i'))')
         echo "$NODENAME,Equinix,${MAC},${IP},${POOL_GW},${POOL_NM},8.8.8.8,/dev/sda,type=${TYPE}" >> hardware.csv
      done
      ```

      The BMC fields are omitted because Equinix Metal does not expose the BMC of nodes. EKS Anywhere will skip BMC steps with this configuration.

   1. Copy `hardware.csv` to `eksa-admin`:

      ```sh
      scp hardware.csv root@$PUB_ADMIN:/root
      ```

We've now provided the `eksa-admin` machine with all of the variables and configuration needed in preparation.

### Steps to run on eksa-admin

1. Login to eksa-admin with the `LC_POOL_ADMIN` and `LC_POOL_VIP` variable defined

   ```sh
   # SSH into eksa-admin. The special args and environment setting are just tricks to plumb $POOL_ADMIN and $POOL_VIP into the eksa-admin environment.
   LC_POOL_ADMIN=$POOL_ADMIN LC_POOL_VIP=$POOL_VIP LC_TINK_VIP=$TINK_VIP ssh -o SendEnv=LC_POOL_ADMIN,LC_POOL_VIP,LC_TINK_VIP root@$PUB_ADMIN
   ```

   > **Note**
   > The remaining steps assume you have logged into `eksa-admin` with the SSH command shown above.

1. [Install `eksctl` and the `eksctl-anywhere` plugin](https://anywhere.eks.amazonaws.com/docs/getting-started/install/#install-eks-anywhere-cli-tools) on eksa-admin.

   ```sh
   curl "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
      --silent --location \
      | tar xz -C /tmp
   sudo mv /tmp/eksctl /usr/local/bin/
   ```

   ```sh
   export EKSA_RELEASE="0.10.1" OS="$(uname -s | tr A-Z a-z)" RELEASE_NUMBER=15
   curl "https://anywhere-assets.eks.amazonaws.com/releases/eks-a/${RELEASE_NUMBER}/artifacts/eks-a/v${EKSA_RELEASE}/${OS}/amd64/eksctl-anywhere-v${EKSA_RELEASE}-${OS}-amd64.tar.gz" \
      --silent --location \
      | tar xz ./eksctl-anywhere
   sudo mv ./eksctl-anywhere /usr/local/bin/
   ```

1. Install `kubectl` on eksa-admin:

   ```sh
   snap install kubectl --channel=1.23 --classic
   ```

   Version 1.23 matches the version used in the eks-anywhere repository.

   <details><summary>Alternatively, install via APT.</summary>

   ```sh
   curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
   echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
   apt-get update
   apt-get install kubectl
   ```

   </details>
1. Install Docker

    Run the docker install script:

    ```sh
    curl -fsSL https://get.docker.com -o get-docker.sh 
    chmod +x get-docker.sh
    ./get-docker.sh
    ```

    Alternatively, follow the instructions from <https://docs.docker.com/engine/install/ubuntu/>.

1. Create EKS-A Cluster config:

   ```sh
   export TINKERBELL_HOST_IP=$LC_TINK_VIP
   export CLUSTER_NAME="${USER}-${RANDOM}"
   export TINKERBELL_PROVIDER=true
   eksctl anywhere generate clusterconfig $CLUSTER_NAME --provider tinkerbell > $CLUSTER_NAME.yaml
   ```

   > **Note**
   > The remaining steps assume you have defined the variables set above.

1. Manually set control-plane IP for `Cluster` resource in the config

   ``` sh
   echo $LC_POOL_VIP
   ```

   ```yaml
   controlPlaneConfiguration:
    count: 1
    endpoint:
      host: "<value of LC_POOL_VIP>"
   ```

1. Manually set the `TinkerbellDatacenterConfig` resource `spec` in config:

   ``` sh
   echo $LC_TINK_VIP
   ```

   ```yaml
   spec:
     tinkerbellIP: "<value of LC_TINK_VIP>"
   ```

1. Manually set the public ssh key in `TinkerbellMachineConfig` `users[name=ec2-user].sshAuthorizedKeys`
   The SSH Key can be a locally generated on `eksa-admin` (`ssh-keygen -t rsa`) or an existing user key.

   ```sh
   ssh-keygen -t rsa
   ```

   ```sh
   cat /root/.ssh/id_rsa.pub
   ```

1. Manually set the hardwareSelector for each TinkerbellMachineConfig.

   For the control plane machine.

   ```sh
   spec:
     hardwareSelector:
       type: cp
   ```

   For the worker machine.

   ```sh
   spec:
     hardwareSelector:
       type: dp
   ```

1. Change the osFamily to ubuntu for each TinkerbellMachineConfig section

   ```sh
   osFamily: ubuntu
   ```

1. Create an EKS-A Cluster. Double check and be sure `$LC_POOL_ADMIN` and `$CLUSTER_NAME` are set correctly before running this (they were passed through SSH or otherwise defined in previous steps). Otherwise manually set them!

   ```sh
   eksctl anywhere create cluster --filename $CLUSTER_NAME.yaml \
     --hardware-csv hardware.csv --tinkerbell-bootstrap-ip $LC_POOL_ADMIN
   ```

### Steps to run locally while `eksctl anywhere` is creating the cluster

1. When the command above indicates it's waiting for the control plane node, reboot the two nodes. This is to force them attempt to iPXE boot from the tinkerbell stack that `eksctl anywhere` command creates. You can use this command to automate it, but you'll need to be back on the original host.

   ```sh
   node_ids=$(metal devices list -o json | jq -r '.[] | select(.hostname | startswith("eksa-node")) | .id')
   for id in $(echo $node_ids); do
      metal device reboot -i $id
   done
   ```
