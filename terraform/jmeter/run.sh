#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

# instalando dependencias
apt-get update
apt-get upgrade -y
apt-get install -y gcc default-jre curl unzip

# descargando pruebas
aws s3 cp s3://container-benchmark-jmeter/testbase.jmx /opt/testbase.jmx

# configurando pruebas
sed -i 's|{{apiEndpoint}}|'${apiEndpoint}'|g' /opt/testbase.jmx
sed -i 's|{{numThreads}}|'${numThreads}'|g' /opt/testbase.jmx
sed -i 's|{{startUsers}}|'${startUsers}'|g' /opt/testbase.jmx
sed -i 's|{{flightTime}}|'${flightTime}'|g' /opt/testbase.jmx

# instalando jmeter
cd /opt
curl https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.zip -o apache-jmeter-5.6.3.zip
unzip apache-jmeter-5.6.3.zip
aws s3 sync s3://container-benchmark-jmeter/ /opt/apache-jmeter-5.6.3/lib/

# iniciando pruebas
cd apache-jmeter-5.6.3/bin/
./jmeter -n -t /opt/testbase.jmx -l /opt/results.csv

# imprimiendo resultado
cat /opt/results.csv
