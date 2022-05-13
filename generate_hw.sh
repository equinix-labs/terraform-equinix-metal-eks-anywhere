#!/bin/bash

WORKERS=$1

echo "id,hostname,vendor,bmc_ip,bmc_username,bmc_password,mac,ip_address,gateway,netmask,nameservers" > /root/hardware.csv

IFS="^"
for worker in $WORKERS
do
    echo "$worker" >> /root/hardware.csv
done
