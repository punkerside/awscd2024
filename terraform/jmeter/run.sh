#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y

apt-get install -y gcc default-jre curl unzip

curl https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.zip -o /opt/apache-jmeter-5.6.3.zip
cd /opt
unzip /opt/apache-jmeter-5.6.3.zip

ls -la