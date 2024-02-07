#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y

apt-get install -y gcc default-jre curl unzip

mkdir -p /opt/opt/apache-jmeter
cd /opt/opt/apache-jmeter

curl https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.zip -o apache-jmeter-5.6.3.zip


unzip apache-jmeter-5.6.3.zip

pwd
ls -la
