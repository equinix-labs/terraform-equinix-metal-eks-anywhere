# EKS-A Baremetal on Equinix Metal

> **Warning**
> This README.md will serve as manual instructions for installing EKS-A Bare Metal on Equinix Metal.  These instructions are a work-in-progress. Once all steps are executed additional steps may be needed.

> **Note**
> Ignore the `.tf` files in this project for now. These instructions will offer copy+paste ready commands where possible to simplify the process. Terraform execution will come once the manual install is ironed out.

Steps below align with EKS-A Beta instructions. While the steps below are intended to be complete, follow along with the EKS-A Beta Install guide for best results.

 ## Known Issues (Investigations ongoing)

* [#11](https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere/issues/11) Sometimes the pxe boot server that the nodes boot from is setup using the wrong IP address. Preventing the kubernetes nodes from ever booting up. The only known workaround is to start over from scratch and hope it works this time. You can tell if you're having the issue if the nodes are trying to boot from 172.17.0.1.
* [#10](https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere/issues/10) The create command hangs on the "Creating new workload cluster" step. This appears to be due to the cluster-api-provider-tinkerbell process never completing. The cluster-api logs indicate they're waiting for a provider-id that they're not seeing for some reason.
* [#9](https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere/issues/9) `systemctl restart networking` may complain that certain VLANs already exist. This doesn't always happen.

## Pre-requisites

The following tools will be needed on your local development environment where you will be running most of the commands in this guide.

* jq
* [metal-cli](https://github.com/equinix/metal-cli) (v0.8.0+)

## Steps to run locally and in the Equinix Metal Console

1. Create an EKS-A Admin machine:
   Using the [metal-cli](https://github.com/equinix/metal-cli):

   Create an [API Key](https://console.equinix.com/users/-/api-keys) and register it with the Metal CLI:

   ```sh
   metal init
   ```

   ```sh
   metal device create --plan=c3.small.x86 --metro=da --hostname eksa-admin --operating-system ubuntu_20_04
   ```

1. Create a VLAN:

     ```sh
     metal vlan create --metro da --description eks-anywhere --vxlan 1000
     ```

1. Create a Public IP Reservation (16 addresses):

     ```sh
     metal ip request --metro da --type public_ipv4 --quantity 16 --tags eksa
     ```

     > **Note**
     > IP reservations would ideally be created within the Metro, facility is used as a workaround to the CLI's limitations for now.

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
     # POOL_VIP is the floating IPv4 public address assigned to the current lead kubernetes control plane
     POOL_VIP=$(python3 -c 'import ipaddress; print(str(ipaddress.ip_network("'${POOL_NW}'/'${POOL_NM}'").broadcast_address-1))')
     ```

1. Create a Metal Gateway

    ```sh
    metal gateway create --ip-reservation-id $POOL_ID --virtual-network $VLAN_ID
    ```

1. Create Tinkerbell worker nodes `eksa-node-001` - `eksa-node-002` with Custom IPXE <http://{eks-a-public-address>}. These nodes will be provisioned as EKS-A Control Plane *OR* Worker nodes.

     ```sh
     for a in {1..2}; do
       metal device create --plan c3.small.x86 --metro da --hostname eksa-node-00$a \
         --ipxe-script-url http://$POOL_ADMIN/ipxe/  --operating-system custom_ipxe
     done
     ```

   Note that the `ipxe-script-url` doesn't actually get used in this process, we're just setting it as it's a requirement for using the custom_ipxe operating system type.

1. Convert the `eksa-admin` node to Hybrid-Bonded connected to the VLAN.
   <https://metal.equinix.com/developers/docs/layer2-networking/hybrid-bonded-mode/>

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

   This snippet configures the VLAN address in `/etc/network/interfaces` on eksa-admin.

   The following will put that configuration into use:

   `ssh root@$PUB_ADMIN systemctl restart networking`

1. Convert `eksa-node-*` to Layer2-Unbonded (not `eksa-admin`)
   Using the UI: Convert nodes to [`Layer2-Unbonded`](https://metal.equinix.com/developers/docs/layer2-networking/layer2-mode/#converting-to-layer-2-unbonded-mode) (Layer2-Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names).
   (TODO: Bring this functionality to the CLI <https://github.com/equinix/metal-cli/issues/206>)

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

1. Install eksctl-anywhere on eksa-admin
    1. Define the NDA Password as an environment variable:

       ```sh
       echo -n "NDA Password: "
       read -s NDA_PW
       export NDA_PW
       echo
       ```

    1. Fetch, unzip, and install the EKS-Anywhere (Beta) binary

         ```sh
         ssh -t root@$PUB_ADMIN <<EOS
         wget -q https://eks-anywhere-beta.s3.amazonaws.com/baremetal/baremetal-bundle.zip
         apt-get install unzip
         unzip -P $NDA_PW baremetal-bundle.zip
         cp baremetal-bundle/eksctl-anywhere /usr/local/bin
         EOS
         ```
## Steps to run on eksa-admin

We've now provided the `eksa-admin` machine with all of the variables and configuration needed in preparation.

1. Login to eksa-admin with the `LC_POOL_ADMIN` variable defined

   ```sh
   # SSH into eksa-admin. The special args and environment setting are just tricks to plumb $POOL_ADMIN into the eksa-admin environment.
   LC_POOL_ADMIN=$POOL_ADMIN ssh -o SendEnv=LC_POOL_ADMIN root@$PUB_ADMIN
   ```
   > **Note**
   > The remaining steps assume you have logged into `eksa-admin` with the SSH command shown above.

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
    get-docker.sh
    ```
    
    Alternatively, follow the instructions from <https://docs.docker.com/engine/install/ubuntu/>.

1. Create EKS-A Cluster config:

   ```sh
   export TINKERBELL_HOST_IP=$LC_POOL_ADMIN
   export CLUSTER_NAME="${USER}-${RANDOM}"
   export TINKERBELL_PROVIDER=true
   eksctl-anywhere generate clusterconfig $CLUSTER_NAME --provider tinkerbell > $CLUSTER_NAME.yaml
   ```

   > **Note**
   > The remaining steps assume you have defined the variables set above.

1. Manually set control-plane IP for `Cluster` resource in the config

   ```yaml
   controlPlaneConfiguration:
    count: 1
    endpoint:
      host: "${POOL_VIP}"
   ```

1. Manually set the `TinkerbellDatacenterConfig` resource `spec` in config:

   ```yaml
   spec:
     tinkerbellIP: "${POOL_ADMIN}"
   ```

1. Manually set the public ssh key in `TinkerbellMachineConfig` `users[name=ec2-user].sshAuthorizedKeys`
   The SSH Key can be a locally generated on `eksa-admin` (`ssh-keygen -t rsa`) or an existing user key.

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

1. Create an EKS-A Cluster. Double check and be sure `$LC_POOL_ADMIN` and `$CLUSTER_NAME` are set correctly before running this (they were passed through SSH or otherwise defined in previous steps). Otherwise manually set them!

   ```sh
   eksctl-anywhere create cluster --filename $CLUSTER_NAME.yaml \
     --hardware-csv hardware.csv --tinkerbell-bootstrap-ip $LC_POOL_ADMIN \
     --force-cleanup -v 9
   ```

   (This command can be rerun if errors are encountered)

1. Reboot the two nodes. This is to force them attempt to iPXE boot from the tinkerbell stack that eksctl-anywhere command creates.
