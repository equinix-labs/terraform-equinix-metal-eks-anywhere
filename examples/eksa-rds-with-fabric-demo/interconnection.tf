# Create a new VLAN
resource "equinix_metal_vlan" "fabric_vlan" {
  description = format("EKS-A Demo - VLAN in %s for Fabric connection", var.metro)
  metro       = var.metro
  project_id  = var.project_id
}

## Request a connection service token in Equinix Metal
resource "equinix_metal_connection" "conn" {
  name               = "eksa-rds-demo"
  project_id         = var.project_id
  metro              = var.metro
  redundancy         = "primary"
  type               = "shared"
  service_token_type = "a_side"
  description        = format("connection to AWS in %s", var.metro)
  speed              = format("%dMbps", var.fabric_speed)
  vlans              = [equinix_metal_vlan.fabric_vlan.vxlan]
}

## Configure the Equinix Fabric connection from Equinix Metal to AWS using the metal connection service token
module "equinix-fabric-connection-aws" {
  source = "equinix-labs/fabric-connection-aws/equinix"
  
  fabric_notification_users     = var.fabric_notification_users
  fabric_connection_name        = "eksa-rds-demo"
  fabric_destination_metro_code = var.metro
  fabric_speed                  = var.fabric_speed
  fabric_service_token_id       = equinix_metal_connection.conn.service_tokens.0.id
  
  aws_account_id = var.aws_account_id

  aws_dx_create_vgw = true
  aws_vpc_id        = module.vpc.vpc_id
  # aws_dx_vgw_id = aws_vpn_gateway.vpgw.id
  
  ## BGP and Direct Connect private virtual interface config
  aws_dx_create_vif           = true
  aws_dx_vif_amazon_address   = var.aws_dx_vif_amazon_address
  aws_dx_vif_customer_address = var.aws_dx_vif_customer_address
  aws_dx_vif_customer_asn     = var.aws_dx_vif_customer_asn
  aws_dx_bgp_auth_key         = random_password.bgp_auth_key.result

  ## tags
  aws_tags = {
    Terraform   = "true"
    Environment = "EKSADemo"
  }
}

## Optionally we use an auto-generated password to enable authentication (shared key) between the two BGP peers
resource "random_password" "bgp_auth_key" {
  length           = 12
  special          = true
  override_special = "$%&*()-_=+[]{}<>:?"
}

## BGP - BIRD configuration
resource "equinix_metal_bgp_session" "bgp" {
  device_id      = module.eksa.eksa_admin_id
  address_family = "ipv4"
}

data "template_file" "interface_fabric_bond0" {
  template = <<EOF
auto bond0.$${vlan_vnid}
iface bond0.$${vlan_vnid} inet static
  pre-up sleep 5
  address $${local_ip}
  netmask $${netmask}
  vlan-raw-device bond0
EOF

  vars = {
    local_ip  = cidrhost(var.aws_dx_vif_customer_address, 2)
    netmask   = var.aws_dx_vif_netmask
    vlan_vnid = equinix_metal_vlan.fabric_vlan.vxlan
  }
}

data "template_file" "bird_conf_template" {

  template = <<EOF
filter equinix_metal_bgp {
  accept;
}

router id $${local_ip};

protocol direct {
    interface "bond0.*";
}

protocol kernel {
    scan time 10;
    persist;
    import all;
    export all;
}

protocol device {
    scan time 10;
}

protocol bgp neighbor_v4_1 {
    export filter equinix_metal_bgp;
    local as $${local_asn};
    neighbor $${cloud_ip} as $${cloud_asn};
    password "$${bgp_password}";
}
EOF
  vars = {
    local_ip     = cidrhost(var.aws_dx_vif_customer_address, 2)
    local_asn    = var.aws_dx_vif_customer_asn
    cloud_ip     = cidrhost(var.aws_dx_vif_amazon_address, 1)
    cloud_asn    = 65412 // this value is fixed by Amazon
    bgp_password = random_password.bgp_auth_key.result
  }
}

resource "null_resource" "configure_bird" {
  connection {
    type        = "ssh"
    user        = "root"
    host        = module.eksa.eksa_admin_ip
    private_key = file(module.eksa.eksa_admin_ssh_key)
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get install bird",
      "mv /etc/bird/bird.conf /etc/bird/bird.conf.old",
    ]
  }

  triggers = {
    template = data.template_file.bird_conf_template.rendered
    template = data.template_file.interface_fabric_bond0.rendered
  }

  provisioner "file" {
    content     = data.template_file.bird_conf_template.rendered
    destination = "/etc/bird/bird.conf"
  }

  provisioner "file" {
    content     = data.template_file.interface_fabric_bond0.rendered
    destination = "/etc/network/interfaces.d/fabricbond0"
  }

  provisioner "remote-exec" {
    inline = [
      "sysctl net.ipv4.ip_forward=1",
      "grep /etc/network/interfaces.d /etc/network/interfaces || echo 'source /etc/network/interfaces.d/*' >> /etc/network/interfaces",
      "ifup bond0.${equinix_metal_vlan.fabric_vlan.vxlan}",
      "service bird restart",
    ]
  }
}
