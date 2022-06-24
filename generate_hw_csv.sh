#!/bin/bash

WORKERS=$1

echo "hostname,vendor,mac,ip_address,gateway,netmask,nameservers,disk,labels" > /root/hardware.csv

IFS="^"
for worker in $WORKERS
do
    echo "$worker" >> /root/hardware.csv
done
