# EKS-A Baremetal on Equinix Metal

Steps below align with EKS-A Beta instructions. The steps below are intended to be complete, making reference to binaries from the EKS-A on Bare Metal Beta install guide. Confer with Beta Install guide when needed.

1. Create an EKS-A Admin machine:

   ```sh
   metal device create --plan=c3.small.x86 --metro=da --hostname eksa-admin --operating-system ubuntu_20_04
   ```

2. <details><summary>Follow Docker Install instructions from https://docs.docker.com/engine/install/ubuntu/</summary>
   ```sh
   sudo apt-get remove docker docker-engine docker.io containerd runc
   ```

   ```sh
    sudo apt-get update
    sudo apt-get install \
      ca-certificates \
      curl \
      gnupg \
      lsb-release
    ```

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
     metal ip request --facility da11 --type public_ipv4 --quantity 16
     ```

5. Create a Metal Gateway: (TODO: <https://github.com/equinix/metal-cli/issues/205>)
     (Using the UI: use selected Metro, VLAN, and Public IP Reservation)
6. Create worker nodes eksa-node01 - ekasa-node-005 with Custom IPXE <http://{eks-a-public-address>}

     ```sh
     for a in {1..5}; do metal device create --plan c3.small.x86 --metro da --hostname eksa-node-00$a --ipxe-script-url http://${eksa-admin} --os custom_ipxe; done
     ```

7. Convert the nodes to Layer2-Bonded: (TODO: <https://github.com/equinix/metal-cli/issues/206>)
     (Using the UI: Convert nodes to Layer2-Unbonded (Bonded would require custom Tinkerbell workflow steps to define the LACP bond for the correct interface names))
8. Capture the MAC Addresses and create `hardware.csv` file on `eks-admin` in `/root/`.
     i. Use `metal` and `jq` to grab HW MAC addresses:
        
      ```sh
      for i in 4a246de4-b229-4d8b-96f7-d15859a93863 2a70cb3c-7ccb-4339-9ef4-bab41902ad7d 58af545f-2a9e-4b33-ad76-4ce3f789bf28 01dfc360-28b7-4dfb-9390-daebff48d3a9 329092a3-6f8a-4b9e-8e0b-0f836fe4fa4d
        do
        metal device get -i $i -o json | jq -r ‘.network_ports | .[] | select(.name == “eth0”) | .data.mac’
      done
      ```

      (TODO: use a singe `jq` expression against `metal devices list` to emit all CSV rows?)
     ii. Create a line for each node (format depends on version of eksanywhere, some versions will require a `labels` and `disk` field):
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
