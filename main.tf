# Configure the Equinix Provider.
provider "equinix" {
  auth_token = var.metal_api_token
}

# Create a new VLAN in datacenter "ewr1"
resource "equinix_metal_vlan" "provisioning_vlan" {
  description = "provisioning_vlan"
  facility    = var.facility
  project_id  = var.project_id
}

# Create tinkerbell worker devices
resource "equinix_metal_device" "tink_worker" {
  count = 1

  hostname         = "my-tink-worker"
  plan             = var.device_type
  facilities       = [var.facility]
  operating_system = "custom_ipxe"
  ipxe_script_url  = "https://boot.netboot.xyz"
  always_pxe       = "true"
  billing_cycle    = "hourly"
  project_id       = var.project_id
}

resource "equinix_metal_device_network_type" "tink_worker_network_type" {
  count = 1

  device_id = equinix_metal_device.tink_worker[count.index].id
  type      = "layer2-individual"
}

# Attach VLAN to worker
resource "equinix_metal_port_vlan_attachment" "worker" {
  count = 1
  
  depends_on = [equinix_metal_device_network_type.tink_worker_network_type]

  device_id = equinix_metal_device.tink_worker[count.index].id
  port_name = "eth0"
  vlan_vnid = equinix_metal_vlan.provisioning_vlan.vxlan
}

# Create a provisioner device
resource "equinix_metal_device" "tink_provisioner" {
  hostname         = "my-tink-provisioner"
  plan             = var.device_type
  facilities       = [var.facility]
  operating_system = "ubuntu_20_04"
  billing_cycle    = "hourly"
  project_id       = var.project_id
  user_data        = file("setup.sh")
}

resource "equinix_metal_device_network_type" "tink_provisioner_network_type" {
  device_id = equinix_metal_device.tink_provisioner.id
  type      = "hybrid"
}

# Attach VLAN to provisioner
resource "equinix_metal_port_vlan_attachment" "provisioner" {
  depends_on = [equinix_metal_device_network_type.tink_provisioner_network_type]
  device_id  = equinix_metal_device.tink_provisioner.id
  port_name  = "eth1"
  vlan_vnid  = equinix_metal_vlan.provisioning_vlan.vxlan
}

resource "null_resource" "setup_tinkerbell" {
  connection {
    type        = "ssh"
    user        = "root"
    host        = equinix_metal_device.tink_provisioner.network[0].address
    agent       = var.use_ssh_agent
    private_key = var.use_ssh_agent ? null : file(var.ssh_private_key)
  }

  //TODO add local.tink_host_ip to compose/.env

  provisioner "local-exec" {
    command = "tar zcvf ${path.module}/compose.tar.gz ${path.module}/compose"
  }

  provisioner "file" {
    source      = "${path.module}/compose.tar.gz"
    destination = "/tmp/compose.tar.gz"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /root/tink/compose && tar zxvf /tmp/compose.tar.gz -C /root/tink",
      "cd /root/tink/compose && timeout 150 bash -c 'while :; do hash docker-compose && break; sleep 2; done' && docker-compose up -d"
    ]
  }
}

resource "null_resource" "setup_eks" {
  connection {
    type        = "ssh"
    user        = "root"
    host        = equinix_metal_device.tink_provisioner.network[0].address
    agent       = var.use_ssh_agent
    private_key = var.use_ssh_agent ? null : file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "${path.module}/eksctl-anywhere-linux-amd64.tar.gz"
    destination = "/tmp/eksctl-anywhere-linux-amd64.tar.gz"
  }
  
  provisioner "file" {
    source      = "${path.module}/setup_eks.sh"
    destination = "/tmp/setup_eks.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup_eks.sh",
      "/tmp/setup_eks.sh",
    ]
  }
}

locals {
  ssh_key_name = "cluster-key"
  cluster_name = "my-eks-cluster"
  control_plane_ip = "192.168.50.14" //TODO FAKE IP - This will be a floating VIP that will be used for control plane HA
  tink_cidr    = "192.168.50.0/28"
  tink_host_ip = cidrhost(local.tink_cidr, 1)
  tink_workers = [for idx, worker in equinix_metal_device.tink_worker : {
    id = worker.id
    hostname = worker.hostname
    vendor = "Dell"
    bmc_ip = ""
    bmc_username = ""
    bmc_password = ""
    mac = worker.ports[1].mac
    ip_address = cidrhost(local.tink_cidr, idx + 2)
    gateway = cidrhost(local.tink_cidr, 15)
    netmask = cidrnetmask(local.tink_cidr)
    nameservers = "8.8.8.8" //TODO GET NAMESERVERS
  }]
  tink_workers_str = [for n in local.tink_workers : "${n.id},${n.hostname},${n.vendor},${n.bmc_ip},${n.bmc_username},${n.bmc_password},${n.mac},${n.ip_address},${n.gateway},${n.netmask},${n.nameservers}"]
}

resource "null_resource" "generate_hardware" {
  depends_on = [
    null_resource.setup_eks
  ]

  triggers = {
    ids = join(",",local.tink_workers.*.id)
  }
  
  connection {
    type        = "ssh"
    user        = "root"
    host        = equinix_metal_device.tink_provisioner.network[0].address
    agent       = var.use_ssh_agent
    private_key = var.use_ssh_agent ? null : file(var.ssh_private_key)
  }

  provisioner "file" {
    source = "${path.module}/generate_hw.sh"
    destination = "/tmp/generate_hw_csv.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/generate_hw_csv.sh",
      "/tmp/generate_hw_csv.sh ${join("^", local.tink_workers_str)}",
      "TINKERBELL_PROVIDER=true eksctl-anywhere generate hardware --filename /root/hardware.csv --tinkerbell-ip ${local.tink_host_ip}"
    ]
  }
}

resource "tls_private_key" "cluster_ssh_key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "null_resource" "create_cluster" {
  depends_on = [
    null_resource.generate_hardware
  ]

  triggers = {
    ids = join(",",local.tink_workers.*.id)
  }
  
  connection {
    type        = "ssh"
    user        = "root"
    host        = equinix_metal_device.tink_provisioner.network[0].address
    agent       = var.use_ssh_agent
    private_key = var.use_ssh_agent ? null : file(var.ssh_private_key)
  }

  provisioner "file" {
    content = chomp(tls_private_key.cluster_ssh_key_pair.private_key_pem)
    destination = "/root/.ssh/${local.ssh_key_name}"
  }

  provisioner "file" {
    content = chomp(tls_private_key.cluster_ssh_key_pair.public_key_openssh)
    destination = "/root/.ssh/${local.ssh_key_name}.pub"
  }

  provisioner "remote-exec" {
    inline = [
      "export CLUSTER_NAME=${local.cluster_name}",
      "TINKERBELL_PROVIDER=true eksctl-anywhere generate clusterconfig $CLUSTER_NAME --provider tinkerbell > $CLUSTER_NAME.yaml",
      "sed -i 's/\\$CONTROL_PLANE_IP/${local.control_plane_ip}/g' $CLUSTER_NAME.yaml",
      "sed -i 's/\\$TINKERBELL_IP/${local.tink_host_ip}/g' $CLUSTER_NAME.yaml",
      "sed -i 's/\\$SSH_PUB_KEY/$(cat /root/.ssh/${local.ssh_key_name}.pub)/g' $CLUSTER_NAME.yaml",
      "eksctl-anywhere create cluster --filename $CLUSTER_NAME.yaml --hardwarefile hardware.yaml --skip-power-actions"
    ]
  }
}
