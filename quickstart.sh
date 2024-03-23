#!/bin/bash

echo ""
echo -ne "\e[32m  Creating base container images\e[0m\e[0m\n"
echo -ne "\e[32m  ==============================\e[0m\e[0m\n"
echo ""
sleep 3s

make base

echo ""
echo -ne "\e[32m  Creating vpc and container registry\e[0m\e[0m\n"
echo -ne "\e[32m  ===================================\e[0m\e[0m\n"
echo ""
sleep 3s

make vpc

echo ""
echo -ne "\e[32m  Creating rds and provisioning database\e[0m\e[0m\n"
echo -ne "\e[32m  ======================================\e[0m\e[0m\n"
echo ""
sleep 3s

make rds

echo ""
echo -ne "\e[32m  Releasing test application\e[0m\e[0m\n"
echo -ne "\e[32m  ==========================\e[0m\e[0m\n"
echo ""
sleep 3s

make release

echo ""
echo -ne "\e[32m  Creating ecs cluster\e[0m\e[0m\n"
echo -ne "\e[32m  ====================\e[0m\e[0m\n"
echo ""
sleep 3s

make ecs

echo ""
echo -ne "\e[32m  Creating and provisioning eks cluster\e[0m\e[0m\n"
echo -ne "\e[32m  =====================================\e[0m\e[0m\n"
echo ""
sleep 3s

make eks

echo ""
echo -ne "\e[32m  Creating jmeter container image and provisioning tool\e[0m\e[0m\n"
echo -ne "\e[32m  =====================================================\e[0m\e[0m\n"
echo ""
sleep 3s

make jmeter
