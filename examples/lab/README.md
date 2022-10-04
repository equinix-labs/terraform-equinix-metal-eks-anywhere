# EKS-A on Baremetal on Equinix Metal Lab

## Overview

This example project offers a lab environment that can quickly enroll dozens of collaborators to experiment with EKS-A on Bare Metal.

Each collaborator is invited to the hosting organization and within that organization they get their own isolated project.
Project isolation offers independent management network IP ranges and VLANs. Project collaborators can not access servers in another project without explicit invitation.

A CSV file is used to define the email addresses of the collaborators as well as the metro and plan to use for the Equinix Metal servers.

The lab facilitator should populate the CSV file and use Terraform to create the lab environment. The organization used for lab will need entitlements sufficient to host the lab. The number of projects and servers that can be created may vary based on your account history.

Once run, each collaborator will receive an email from Equinix Metal inviting them to create an account and join the organization project. If the collaborator is an existing Equinix Metal user they may login with their existing account. Be mindful that collaborators will have access to create new devices and other resources within the project. Be sure you trust your lab participants before extending collaborator invitations.

Collaborators will only have access to the Equinix Metal Portal and through that they will have credentials that can be used to login to the EKS-A Admin node. The `root` password is displayed in the portal when viewing any server created within the last 24 hours.

Collaborators will not have access to the Terraform secrets or state.

## Plans and Metros

Bare metal servers consume physical space unlike virtual machines. Be mindful of capacity limitations for any particular server plan.
Check the Equinix Metal Capacity Dashboard when choosing plans and locations. <https://metal.equinix.com/developers/capacity-dashboard/>

The requirements and featureset of EKS-A on Bare Metal, BottleRocket OS, and Equinix Metal servers, reduces the choice of plans that can be used for control plane and data plane nodes. While we work to overcome these limitations, the following plans are known to provision EKS-A nodes today:

* [m3.small.x86](https://monitoring.nixos.org/grafana/d/I1WQEbbWz/packet-capacity-by-plan-table?var-plan=m3.small.x86&var-facility=All&orgId=1)
* [c2.medium.x86](https://monitoring.nixos.org/grafana/d/I1WQEbbWz/packet-capacity-by-plan-table?var-plan=c2.medium.x86&var-facility=All&orgId=1) (some servers may have incompatible device configurations)

## Run

From a local copy of this `terraform-equinix-metal-eksa-on-baremetal` project:

```sh
cd examples/lab
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
cp users.csv.examples users.csv
vim users.csv
terraform init -upgrade
terraform apply
```

The `users.csv` file can be updated at any time to change the target metro or plan for an environment that you want to recreate. You may also replace, remove, or add email addresses.  Simply run `terraform apply` when ready.

## Successful Provisions

A successful environment will result in a terraform output of `🎉 Cluster created!` for the environment.

### Accessing the cluster

Prerequisites:
- SSH client installed

When the event starts, participants should make sure they accepted the collaboration invitation emailed to them and then log into the Equinix Metal console <https://console.equinix.com>.

They will find that they have access to the event Organization and their project.

Within their project, they will find a server with a hostname prefixed `eksa-admin`. They should click on this server to find the IP address and `root` password. They must then login to this server using their local SSH tools. `ssh root@IP-OF-EKSA-ADMIN`.

Once logged in, they will find additional guidance in the `/root/README.md` file.

## Failed Provisions

Be sure to begin provisioning nodes in advance of your lab. Each project can take 30m or longer to setup. Complications may arise requiring a project to be recreated, which can greatly extend the time required.

### Detecting failures

Watch the output logs for any errors. Progress can be deceptive because Terraform's DAG will queue up resources behind other resources. You may not see errors until the final script timeout (about 60m) or the execution is canceled.

When a failure occurs on some environments, while other succeed, you should be able to detect the failed nodes with a command like `terraform state list | cut -f 2 -d\" | sort | uniq -c  | sort -n`.  This command lists how many resources were provisioned for each lab environment. Environments that have too few resources were not able to complete and can be replaced.

### Reprovisioning a Failed Cluster

There are various failure scenarios. For each scenario there is am optimal retry approach and a last ditch approach.

* `At least one Admin is required.; Cannot remove the Organization Owner`
  Avoid adding any organization owner email addresses to the collaborator email list. Consider creating a new account using email aliases, for example, if your email address is "example@example.com", "example+eks001@example.com" may also be used in some server environments.
  To clear the state of an organization owner that was added as a collaborator, run `terraform state rm 'module.lab["me@example.com"].equinix_metal_organization_member.user[0]`, remove the email address from the email list, and run `terraform apply`.
* eksa-admin failed to provision
  <!-- TODO: fix notes -->
* nodes failed to provision
  If a node fails to provision, the `terraform apply` command will take up to 60m and eventually time out. When this happens you may see errors such as `Terminating this operation may leave the cluster in an irrecoverable state.

  To replace a cluster, and only that cluster, run the following:

  ```sh
  ./replace.sh email@address.here
  ```

  When building a large lab, you may need to replace several environments. Identify and taint all of the failed environments using this script and then run `terraform apply`. If you inadvertantly mark the wrong resources, rerun the command with "untaint" at the end of the command (`./replace email@address.here untaint`). Participants will need to check their email and accept a new invitation to the project as the old project will be deleted.

  To prevent sending invitations until all environments have been successfully created, set the variable `send_invites` to `false` until ready, then set the variable to `true` and run `terraform apply` to only send out the invitations.  This can also be used to reduce the window of time participants have access to the environment.

  Terraform taints can be performed more selectively based on the failed step. For example, it should be sufficient to taint failed nodes and the `create_cluster` execution in some cases. In the future, guidance may be offered by this README.md for specific scenarios. For now each ifailed project must be replaced in its entirety when it has failed.

  * cp_node failed to provision
    <!-- TODO: fix notes -->
  * dp_node failed to provision
    <!-- TODO: fix notes -->
  * extra node failed to provision
    * The participant can do these steps themselves.
      * Delete the failed node.
      * Create a new m3.small.x86 with Custom iPXE as the OS type in the same metro as your other servers.
      * When the node is provisioned, obtain the MAC address and choose an available IP from the IP block (usually this is the fifth address in the block, ie. gateway address + 5).
      * Add these values to the hardware.csv file on the eksa-admin machine.
      * Follow the normal steps for adding a node to the cluster.

## Terminating the Lab

Run `terraform destroy` to terminate all resources provisioned during the lab. Repeat executions may be needed if Terraform times out or encounters other failures.

Collaborators will be removed from the host organization.
Collaborators can be removed without affecting the EKS-A environments using targeted Terraform commands.

If a node had to be manually added to a project, the project may fail to delete at the end of the lab event.Use the console or metal CLI to manually delete the project.
