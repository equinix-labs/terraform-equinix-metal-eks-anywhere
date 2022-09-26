#!/bin/bash
set -e

declare -A NODES="${1#*=}"

truncate -s 0 eksa-create-cluster.log

echo "Waiting for the creation of the workload to start before rebooting nodes..."
( tail -f -n0 eksa-create-cluster.log & ) | grep -q "Creating new workload cluster"

FAILED_IDS=""
FAILED_SOS=""
IFS=","
for node in "${!NODES[@]}"; do
    echo "Rebooting node $node ..."
    n=1
    max=24
    delay=5
    while true; do
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.equinix.com/metal/v1/devices/$node/actions" -d "{\"type\":\"reboot\",\"force_delete\":\"false\"}" -H "Content-Type: application/json" -H "X-Auth-Token: $API_TOKEN")
        if [ ! $HTTP_STATUS -eq 202  ]; then
            if [[ $n -lt $max ]]; then
                echo "Error rebooting $node [HTTP status: $HTTP_STATUS], will try again in $delay seconds"
                n=$((n+1))
                sleep $delay;
            else
                echo "Rebooting node $node has failed after $n attempts"
                FAILED_IDS="${FAILED_IDS}${FAILED_IDS:+, }$node"
                FAILED_SOS="${FAILED_SOS}${FAILED_SOS:+, }${NODES[$node]}"
                break
            fi
        else
            echo "Node $node rebooted" && break
        fi
    done
done
[ -z "$FAILED_IDS" ] || echo -e "\n\nACTION REQUIRED: Some nodes failed to reboot. To complete the installation, please reboot the nodes [ $FAILED_IDS ] manually or log in to their SOS (Serial Over SSH) console [ $FAILED_SOS ]. Check documentation for more details https://github.com/equinix-labs/terraform-equinix-metal-eks-anywhere#steps-to-run-locally-while-eksctl-anywhere-is-creating-the-cluster\n\n"
