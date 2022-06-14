# EKS-A Baremetal on Equinix Metal

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
   Further references to `${eksa-admin}` should be subsituted with the Public IP address of this node that is used in the VLAN.
   
2. <details><summary>Follow Docker Install instructions from https://docs.docker.com/engine/install/ubuntu/</summary>
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
3. Create a VLAN:

     ```sh
     metal vlan create --metro da --description tinkerbell --vxlan 1000
     ```

4. Create a Public IP Reservation (16 addresses): (TODO: <https://github.com/equinix/metal-cli/issues/206>)

     ```sh
     metal ip request --facility da11 --type public_ipv4 --quantity 16 --tags eksa
     #Capture the ID, Network, Gateway, and Netmask using jq
     i=1 # We will increment "i" for the eks-a node and eksa-node-* nodes
     POOL_ID=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .id')
     POOL_NW=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .network')
     POOL_GW=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .gateway')
     POOL_NM=$(metal ip list -o json | jq -r '.[] | select(.tags | contains(["eksa"]))? | .netmask')
     EKSA_A=$(python3 -c 'import ipaddress; print(str(ipaddress.IPv4Address("'${POOL_GW}'")+'$i'))')
     ```
     (IP reservations should be created within the Metro, facility is used as a workaround for now)
     These POOL variables will be referred to in later steps with pseudo-code to refer to specific addresses within the pool. 
5. Create a Metal Gateway: (TODO: <https://github.com/equinix/metal-cli/issues/205>)
     (Using the UI: use selected Metro, VLAN, and Public IP Reservation)
6. Create Tinkerbell worker nodes `eksa-node-001` - `eksa-node-002` with Custom IPXE <http://{eks-a-public-address>}. These nodes will be provisioned as EKS-A Control Plane *OR* Worker nodes.

     ```sh
     for a in {1..2}; do
       metal device create --plan c3.small.x86 --metro da --hostname eksa-node-00$a \
         --ipxe-script-url http://${eksa-admin} --os custom_ipxe
     done
     ```

7. Convert the nodes to Layer2-Bonded: (TODO: <https://github.com/equinix/metal-cli/issues/206>)
     (Using the UI: Convert nodes to [`Layer2-Unbonded`](https://metal.equinix.com/developers/docs/layer2-networking/layer2-mode/#converting-to-layer-2-unbonded-mode) (Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names))
8. Capture the MAC Addresses and create `hardware.csv` file on `eks-admin` in `/root/`.
   1. Create the CSV Header:
      ```sh
      echo hostname,vendor,bmc_ip,bmc_username,bmc_password,bmc_vendor,mac,ip_address,gateway,netmask,nameservers,id > hardware.csv
      ```

   2. Use `metal` and `jq` to grab HW MAC addresses and add them to the hardware.csv:
      
      ```sh
      node_ids=$(metal devices list -o json | jq -r '.[] | select(.hostname | startswith("eksa-node")) | .id')

      for id in $node_ids; do
        let i++
        MAC=$(metal device get -i $id -o json | jq -r ‘.network_ports | .[] | select(.name == “eth0”) | .data.mac’)
        IP=$(python3 -c 'import ipaddress; print(str(ipaddress.IPv4Address("'${POOL_GW}'")+'$i'))')
        echo "eks-node-00${i},Equinix,0.0.0.${i},ADMIN,PASSWORD,Equinix,${MAC},${IP},${POOL_GW},${POOL_NM},8.8.8.8," >> hardware.csv
      done
      ```
      
   3. Create a line for each node (format depends on version of eksanywhere, some versions will require a `labels` and `disk` field):
      ```csv
      hostname,vendor,bmc_ip,bmc_username,bmc_password,bmc_vendor,mac,ip_address,gateway,netmask,nameservers,id
      eks-node0${i},Equinix,0.0.0.${1},ADMIN,PASSWORD,Equinix,${mac},${pool .($i+1)},${pool .1},255.255.255.240,8.8.8.8,
      ```
9. Configure VLAN address in `/etc/network/interfaces` on eksa-admin (following <https://metal.equinix.com/developers/docs/layer2-networking/hybrid-bonded-mode/>)

      ```
      auto bond0.1000
      iface bond0.1000 inet static
        pre-up sleep 5
        address ${ip of the eks-admin, gw + 1}
        netmask 255.255.255.240
        vlan-raw-device bond0
      ```

      `systemctl restart networking`
10. Install Tinkerbell on eksa-admin
   i. `scp tinkerbell-stack.tar.gz ${eksa-admin}:/root` (tarball from the Beta program)
   ii. ```sh
        ssh ${eksa-admin}
        tar zxvf tinkerbell-stack.tar.gz
        cd tinerbell-stack
        export TINKERBELL_HOST_IP=${eks-admin}
        docker compose up -d
        ```
   (If opting to use the latest `main` branch of https://github.com/aws/eks-anywhere, this step can be skipped. Tinkerbell is installed in kind by the `create cluster` command)
11. Install `kubectl` on eksa-admin:

      ```sh
      curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
      echo “deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main” | sudo tee /etc/apt/sources.list.d/kubernetes.list
      apt update
      apt install kubectl
      ```

      Alternatively:

      ```
      snap install kubectl -channel=1.23 --classic # 1.23 matches the version used in the eks-anywhere repo
      ```

12. Install `eksctl` using a custom build from Github. The copy in the Beta package is not recent enough. The version specified below includes fixes to skip power commands.

      ```
      cd ~
      apt install build-essential
      snap install go --classic
      git clone -b ab06b6eebc0735f7bb290184e4b6b6c11befcdee https://github.com/aws/eks-anywhere
      cd eks-anywhere
      make build
      cp bin/eksctl-anywhere /usr/local/bin
      ```
      (If opting to use the latest `main` branch for the build, the Hardware CSV format and eksctl arguments may be different)
13. Create Tinkerbell Hardware

      ```sh
      eksctl-anywhere generate hardware --filename hardware.csv --tinkerbell-ip ${eksa-admin}
      ```

      (note: `--filename` may be `--hardware` in newer versions)
      View `hardware-manifests/hardware.yaml` and compare to the beta guide. Check for valid yaml contents, including generated `spec.id` values.
14. Create EKS-A Cluster config:

      ```sh
      export CLUSTER_NAME=“${USER}-${RANDOM}”
      export TINKERBELL_PROVIDER=true
      eksctl-anywhere generate clusterconfig $CLUSTER_NAME --provider tinkerbell > $CLUSTER_NAME.yaml
      ```

15. Manually set control-plane IP for `Cluster` resource in the config
      Modify `spec.controlPlaneConfiguration.endpoint.host` to a unique VIP address from the public IP pool. For simplicity in node configuration, we've chosen the last IP in the block.
16. Manually set the `TinkerbellDatacenterConfig` resource `spec` in config:

      ```yaml
      spec:
        tinkerbellCertURL: "http://${eksa-admin}:42114/cert"
        tinkerbellGRPCAuth: "${eksa-admin}:42113"
        tinkerbellIP: "${eksa-admin}"
        tinkerbellHegelURL: "http://${eksa-admin}:50061"
        tinkerbellPBnJGRPCAuth: "${eksa-admin}:50051"
      ```

17. Manually set the public ssh key in `TinkerbellMachineConfig` `users[name=ec2-user].sshAuthorizedKeys`
      Key can be a locally generated on eksa-admin (`ssh-keygen -t rsa`) or an existing user key.
18. Create an EKS-A Cluster

      ```sh
      eksctl-anywhere create cluster --filename $CLUSTER_NAME.yaml --hardwarefile hardware-manifests/hardware.yaml --skip-power-actions --force-cleanup
      ```

      (This command can be rerun if errors are encountered)

19.
