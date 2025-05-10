
# https://github.com/opnsense/update
rg='opnsense'
location='centralindia'
vm_name='opnsense'
vm_image=$(az vm image list -l $location -p thefreebsdfoundation --sku 14_2-release-zfs --all --query "[?offer=='freebsd-14_2'].urn" -o tsv | tr -d '\r') && echo $vm_image
az vm image terms accept --urn $vm_image -o none
vnet_name='opnsense-vnet'
vnet_address='10.10.0.0/16'
lan_subnet_name='lan-subnet'
lan_subnet_address='10.10.1.0/24'
wan_subnet_name='wan-subnet'
wan_subnet_address='10.10.0.0/24'
vm_size=Standard_B2als_v2
admin_username=$(whoami)

cloud_init_file=cloud_init.sh
cat <<EOF > $cloud_init_file
#!/usr/local/bin/bash
echo $admin_password | sudo -S pkg update
sudo pkg upgrade -y
sed 's/#PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config > /tmp/sshd_config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config_tmp
sudo mv /tmp/sshd_config /etc/ssh/sshd_config
sudo /etc/rc.d/sshd restart
fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in
sed 's/reboot/#reboot/' opnsense-bootstrap.sh.in >opnsense-bootstrap.sh.in.tmp
mv opnsense-bootstrap.sh.in.tmp opnsense-bootstrap.sh.in
sed 's/set -e/#set -e/' opnsense-bootstrap.sh.in >opnsense-bootstrap.sh.in.tmp
mv opnsense-bootstrap.sh.in.tmp opnsense-bootstrap.sh.in
sudo chmod +x opnsense-bootstrap.sh.in
sudo sh ~/opnsense-bootstrap.sh.in -y -r 25.1
sudo cp ~/config.xml /usr/local/etc/config.xml
sudo pkg upgrade
sudo pkg install -y bash git py311-setuptools-63.1.0_3
sudo ln -s /usr/local/bin/python3.11 /usr/local/bin/python
git -c http.sslVerify=false clone https://github.com/Azure/WALinuxAgent.git
cd ~/WALinuxAgent/
git checkout v2.13.1.1
sudo python setup.py install --register-service --force
sudo reboot
EOF

# resource group
echo -e "\e[1;36mCreating Resource Group $rg...\e[0m"
az group create -n $rg -l $location -o none

# vnet
echo -e "\e[1;36mCreating VNet $vnet_name...\e[0m"
az network vnet create -g $rg -n $vnet_name --address-prefixes $vnet_address --subnet-name $lan_subnet_name --subnet-prefixes $lan_subnet_address -o none
az network vnet subnet create -g $rg -n $wan_subnet_name --vnet-name $vnet_name --address-prefixes $wan_subnet_address -o none

# vm
echo -e "\e[1;36mCreating $vm_name VM...\e[0m"
az network public-ip create -g $rg -n $vm_name --allocation-method Static --sku Basic -o none
az network nic create -g $rg -n $vm_name-wan --subnet $wan_subnet_name --vnet-name $vnet_name --ip-forwarding true --private-ip-address 10.10.0.250 --public-ip-address $vm_name -o none
az network nic create -g $rg -n $vm_name-lan --subnet $lan_subnet_name --vnet-name $vnet_name --ip-forwarding true --private-ip-address 10.10.1.250 -o none
az vm create -g $rg -n $vm_name --image $vm_image --nics $vm_name-wan $vm_name-lan --os-disk-name $vm_name --size $vm_size --admin-username $admin_username --generate-ssh-keys
# vm details
opnsense_public_ip=$(az network public-ip show -g $rg -n $vm_name --query 'ipAddress' -o tsv | tr -d '\r') && echo $vm_name public ip address: $opnsense_public_ip

# enable vm boot diagnostic
echo -e "\e[1;36mEnabling VM boot diagnostics...\e[0m"
az vm boot-diagnostics enable -n $vm_name -g $rg -o none

# installation and configuration of opnsense 
config_file=~/config.xml
curl -o $config_file https://raw.githubusercontent.com/wshamroukh/opnsense-azure-vm/refs/heads/main/config.xml
echo -e "\e[1;36mCopying configuration files to $vm_name and installing opnsense firewall...\e[0m"
scp -o StrictHostKeyChecking=no $cloud_init_file $config_file $admin_username@$opnsense_public_ip:/home/$admin_username
ssh -o StrictHostKeyChecking=no $admin_username@$opnsense_public_ip "chmod +x /home/$admin_username/cloud_init.sh && sh /home/$admin_username/cloud_init.sh"
rm $cloud_init_file $config_file
echo -e "\e[1;31mVM is now rebooting. You can access it by going to https://$opnsense_public_ip/ \n usename: root \n passwd: opnsense\nIt's highly recommended to change the password\e[0m"

#https://publicIP/
#usename: root
#passwd: opnsense

# Cleanup
# az group delete -g $rg --yes --no-wait -o none