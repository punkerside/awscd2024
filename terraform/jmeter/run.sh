#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y

apt-get install -y gcc default-jre curl unzip

cd /opt
aws s3 cp s3://container-benchmark-jmeter/testbase.jmx testbase.jmx

curl https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.zip -o apache-jmeter-5.6.3.zip
unzip apache-jmeter-5.6.3.zip

cd apache-jmeter-5.6.3/bin/
./jmeter -n -t /opt/testbase.jmx -l /opt/results.csv

cat /opt/results.csv
