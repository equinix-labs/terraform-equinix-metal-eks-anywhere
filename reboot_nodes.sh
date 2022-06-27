#!/bin/bash

NODES=$1

truncate -s 0 eksa-create-cluster.log

echo "Waiting for the creation of the workload cluster begins to reboot nodes..."
( tail -f -n0 eksa-create-cluster.log & ) | grep -q "Creating new workload cluster"

IFS=","
for node in $NODES
do
    echo "Rebooting node $node ..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.equinix.com/metal/v1/devices/$node/actions" -d "{\"type\":\"reboot\",\"force_delete\":\"false\"}" -H "Content-Type: application/json" -H "X-Auth-Token: $API_TOKEN")
    
    if [ ! $HTTP_STATUS -eq 202  ]; then
        echo "Error rebooting $node [HTTP status: $HTTP_STATUS]"
        exit 1
    else
        echo "Node $node rebooted"
    fi
done
