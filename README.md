# EKS-A Baremetal on Equinix Metal

> **Warning**
> This README.md will serve as manual instructions for installing EKS-A Bare Metal on Equinix Metal.  These instructions are a work-in-progress. Once all steps are executed additional steps may be needed.

> **Note**
> Ignore the `.tf` files in this project for now. These instructions will offer copy+paste ready commands where possible to simplify the process. Terraform execution will come once the manual install is ironed out.

Steps below align with EKS-A Beta instructions. The steps below are intended to be complete, making reference to binaries from the EKS-A on Bare Metal Beta install guide. Confer with Beta Install guide when needed.

1. Create an EKS-A Admin machine:
   Using the [metal-cli](https://github.com/equinix/metal-cli):

   Create an [API Key](https://console.equinix.com/users/-/api-keys) and register it with the Metal CLI:

   ```sh
   metal init
   ```

   ```sh
   metal device create --plan=c3.small.x86 --metro=da --hostname eksa-admin --operating-system ubuntu_20_04
   ```

   Further references to `${eksa-admin}` should be substituted with the Public IP address of this node that is used in the VLAN.

1. <details><summary>Follow Docker Install instructions from https://docs.docker.com/engine/install/ubuntu/</summary>
   ```sh
   sudo apt-get remove docker docker-engine docker.io containerd runc
   ```
   This will have no effect on Equinix Metal, none of these packages are installed.

   ```sh
    sudo apt-get update
    sudo apt-get install \
      ca-certificates \
      curl \
      gnupg \
      lsb-release
    ```

    On Equinix Metal, only ca-certificates will be installed.

    ```sh
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    ```

    ```sh
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    ```

    ```sh
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    ```

    </details>
1. Create a VLAN:

     ```sh
     metal vlan create --metro da --description tinkerbell --vxlan 1000
     ```

1. Create a Public IP Reservation (16 addresses): (TODO: <https://github.com/equinix/metal-cli/issues/206>)

     ```sh
     metal ip request --facility da11 --type public_ipv4 --quantity 16 --tags eksa
     #Capture the ID, Network, Gateway, and Netmask using jq
     POOL_ID=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .id')
     POOL_NW=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .network')
     POOL_GW=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .gateway')
     POOL_NM=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .netmask')
     # POOL_ADMIN will be assigned to eksa-admin within the VLAN
     POOL_ADMIN=$(python3 -c 'import ipaddress; print(str(ipaddress.IPv4Address("'${POOL_GW}'")+1))')
     # PUB_ADMIN is the provisioned IPv4 public address of eks-admin which we can use with ssh
     PUB_ADMIN=$(metal devices list  -o json  | jq -r '.[] | select(.hostname=="eksa-admin") | .ip_addresses [] | select(contains({"public":true,"address_family":4})) | .address')
     ```

     (IP reservations should be created within the Metro, facility is used as a workaround for now)
     These POOL variables will be referred to in later steps with pseudo-code to refer to specific addresses within the pool.
1. Create a Metal Gateway: (TODO: <https://github.com/equinix/metal-cli/issues/205>)
     (Using the UI: use selected Metro, VLAN, and Public IP Reservation)
1. Create Tinkerbell worker nodes `eksa-node-001` - `eksa-node-002` with Custom IPXE <http://{eks-a-public-address>}. These nodes will be provisioned as EKS-A Control Plane *OR* Worker nodes.

     ```sh
     for a in {1..2}; do
       metal device create --plan c3.small.x86 --metro da --hostname eksa-node-00$a \
         --ipxe-script-url http://${POOL_ADMIN} --operating-system custom_ipxe
     done
     ```

1. Convert `eksa-node-*` to Layer2-Bonded: (TODO: <https://github.com/equinix/metal-cli/issues/206>)
     (Using the UI: Convert nodes to [`Layer2-Unbonded`](https://metal.equinix.com/developers/docs/layer2-networking/layer2-mode/#converting-to-layer-2-unbonded-mode) (Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names))
1. Capture the MAC Addresses and create `hardware.csv` file on `eks-admin` in `/root/`.
   1. Create the CSV Header:

      ```sh
      echo hostname,vendor,bmc_ip,bmc_username,bmc_password,bmc_vendor,mac,ip_address,gateway,netmask,nameservers,disk,labels > hardware.csv
      ```

   1. Use `metal` and `jq` to grab HW MAC addresses and add them to the hardware.csv:

      ```sh
      node_ids=$(metal devices list -o json | jq -r '.[] | select(.hostname | startswith("eksa-node")) | .id')

      i=1 # We will increment "i" for the eksa-node-* nodes. "1" represents the eksa-admin node.

      for id in $(echo $node_ids); do
         # Configure only the first node as a control-panel node
         if [ i == 1 ]; TYPE=cp; else TYPE=dp; fi # change to 3 for HA
         let i++
         MAC=$(metal device get -i $id -o json | jq -r ‘.network_ports | .[] | select(.name == “eth0”) | .data.mac’)
         IP=$(python3 -c 'import ipaddress; print(str(ipaddress.IPv4Address("'${POOL_GW}'")+'$i'))')
         echo "eks-node-00${i},Equinix,0.0.0.${i},ADMIN,PASSWORD,Equinix,${MAC},${IP},${POOL_GW},${POOL_NM},8.8.8.8,/dev/sda,type=${TYPE}" >> hardware.csv
      done

      scp hardware.csv root@$PUB_ADMIN:/root
      ```

      Change the `type=cp` label for the second node to `type=dp`.

      The BMC fields are using fake values since Equinix Metal does not expose the BMC of nodes. The IP address must be unique however, so we change that per node. In later versions of eksanywhere, we can omit the BMC requirements and these CSV fields.

1. Convert the `eksa-admin` node to Hybrid-Bonded connected to the VLAN.
   <https://metal.equinix.com/developers/docs/layer2-networking/hybrid-bonded-mode/>

      ```sh
      ssh root@$PUB_ADMIN tee -a /etc/network/interfaces << EOS

      auto bond0.1000
      iface bond0.1000 inet static
        pre-up sleep 5
        address $POOL_ADMIN
        netmask $POOL_NM
        gateway $POOL_GW
        vlan-raw-device bond0
      EOS
      ```

   This snippet configures the VLAN address in `/etc/network/interfaces` on eksa-admin.

   The following will put that configuration into use:

   `ssh root@$PUB_ADMIN systemctl restart networking`
1. Install Tinkerbell on eksa-admin
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

1. Install `kubectl` on eksa-admin:

   ```sh
   ssh root@$PUB_ADMIN
   ```

   ```sh
   curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
   echo “deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main” | sudo tee /etc/apt/sources.list.d/kubernetes.list
   apt update
   apt install kubectl
   ```

   Alternatively:

   ```sh
   snap install kubectl -channel=1.23 --classic # 1.23 matches the version used in the eks-anywhere repo
   ```

1. Create EKS-A Cluster config:

   ```sh
   # SSH into eksa-admin. The special args and environment setting are just tricks to plumb $POOL_ADMIN into the eksa-admin environment.
   LC_POOL_ADMIN=$POOL_ADMIN ssh -o SendEnv=LC_POOL_ADMIN root@$PUB_ADMIN
   ```

   ```sh
   export TINKERBELL_HOST_IP=$LC_POOL_ADMIN
   export CLUSTER_NAME=“${USER}-${RANDOM}”
   export TINKERBELL_PROVIDER=true
   eksctl-anywhere generate clusterconfig $CLUSTER_NAME --provider tinkerbell > $CLUSTER_NAME.yaml
   ```

1. Manually set control-plane IP for `Cluster` resource in the config
      Modify `spec.controlPlaneConfiguration.endpoint.host` to a unique VIP address from the public IP pool. For simplicity in node configuration, we've chosen the last IP in the block.
1. Manually set the `TinkerbellDatacenterConfig` resource `spec` in config:

      ```yaml
      spec:
        tinkerbellIP: "${eksa-admin}"
      ```

1. Manually set the public ssh key in `TinkerbellMachineConfig` `users[name=ec2-user].sshAuthorizedKeys`
      Key can be a locally generated on eksa-admin (`ssh-keygen -t rsa`) or an existing user key.
1. Create an EKS-A Cluster

      ```sh
      eksctl-anywhere create cluster --filename $CLUSTER_NAME.yaml \
       --hardware-csv hardware.csv --tinkerbell-bootstrap-ip $POOL_ADMIN \
       --skip-power-actions --force-cleanup -v 9
      ```

      (This command can be rerun if errors are encountered)
