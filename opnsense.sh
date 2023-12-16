
# https://github.com/opnsense/update
#variables
rg='opnsense'
location='uaenorth'
vm_name='opnsense'
vm_image=$(az vm image list -l $location -p thefreebsdfoundation --all --query "[?offer=='freebsd-13_1'].urn" -o tsv | sort -u | tail -n 1)
az vm image terms accept --urn $vm_image -o none
vnet_name='opnsense-vnet'
vnet_address='10.10.0.0/16'
lan_subnet_name='lan-subnet'
lan_subnet_address='10.10.1.0/24'
wan_subnet_name='wan-subnet'
wan_subnet_address='10.10.0.0/24'
admin_username=$(whoami)
admin_password='P@ssw0rd#$3cr3t'

cloud_init_file=~/cloud_init.sh
cat <<EOF > $cloud_init_file
#!/usr/local/bin/bash
echo $admin_password | sudo -S pkg update
sudo pkg upgrade -y
sudo pkg install -y nano ca_root_nss
sudo /usr/libexec/locate.updatedb
sed 's/#PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config > /tmp/sshd_config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config_tmp
sudo mv /tmp/sshd_config /etc/ssh/sshd_config
sudo /etc/rc.d/sshd restart
echo -e "$admin_password\n$admin_password" | sudo passwd root
fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in
sed 's/reboot/#reboot/' opnsense-bootstrap.sh.in >opnsense-bootstrap.sh.in.tmp
mv opnsense-bootstrap.sh.in.tmp opnsense-bootstrap.sh.in
chmod +x opnsense-bootstrap.sh.in
sudo sh ~/opnsense-bootstrap.sh.in -y -r 23.7
sudo cp ~/config.xml /usr/local/etc/config.xml
sudo reboot
EOF


function wait_until_finished {
     wait_interval=15
     resource_id=$1
     resource_name=$(echo $resource_id | cut -d/ -f 9)
     echo -e "\e[1;36mWaiting for resource $resource_name to finish provisioning...\e[0m"
     start_time=`date +%s`
     state=$(az resource show --id $resource_id --query properties.provisioningState -o tsv)
     until [[ "$state" == "Succeeded" ]] || [[ "$state" == "Failed" ]] || [[ -z "$state" ]]
     do
        sleep $wait_interval
        state=$(az resource show --id $resource_id --query properties.provisioningState -o tsv)
     done
     if [[ -z "$state" ]]
     then
        echo -e "\e[1;31mSomething really bad happened...\e[0m"
     else
        run_time=$(expr `date +%s` - $start_time)
        ((minutes=${run_time}/60))
        ((seconds=${run_time}%60))
        echo -e "\e[1;32mResource $resource_name provisioning state is $state, wait time $minutes minutes and $seconds seconds\e[0m"
     fi
}

# resource group
echo -e "\e[1;36mCreating Resource Group $rg...\e[0m"
az group create -n $rg -l $location -o none

# vnet
echo -e "\e[1;36mCreating VNet $vnet_name...\e[0m"
az network vnet create -g $rg -n $vnet_name --address-prefixes $vnet_address --subnet-name $lan_subnet_name --subnet-prefixes $lan_subnet_address -o none
az network vnet subnet create -g $rg -n $wan_subnet_name --vnet-name $vnet_name --address-prefixes $wan_subnet_address -o none

# vm
echo -e "\e[1;36mCreating $vm_name VM...\e[0m"
az network public-ip create -g $rg -n "$vm_name-public-ip" --allocation-method Static --sku Basic -o none
az network nic create -g $rg -n "$vm_name-wan-nic" --subnet $wan_subnet_name --vnet-name $vnet_name --ip-forwarding true --private-ip-address 10.10.0.250 --public-ip-address "$vm_name-public-ip" -o none
az network nic create -g $rg -n "$vm_name-lan-nic" --subnet $lan_subnet_name --vnet-name $vnet_name --ip-forwarding true --private-ip-address 10.10.1.250 -o none
az vm create -g $rg -n $vm_name --image $vm_image --nics "$vm_name-wan-nic" "$vm_name-lan-nic" --os-disk-name $vm_name-osdisk --size Standard_B2s --admin-username $admin_username --generate-ssh-keys --no-wait

# vm details
opnsense_public_ip=$(az network public-ip show -g $rg -n "$vm_name-public-ip" --query 'ipAddress' --output tsv) && echo $vm_name public ip address: $opnsense_public_ip
opnsense_vm_id=$(az vm show -g $rg -n $vm_name --query 'id' -o tsv)

# waiting for vm to finish provisioning
wait_until_finished $opnsense_vm_id

# enable vm boot diagnostic
echo -e "\e[1;36mEnabling VM boot diagnostics...\e[0m"
az vm boot-diagnostics enable -n $vm_name -g $rg -o none

# installation and configuration of opnsense 
config_file=~/config.xml
curl https://raw.githubusercontent.com/wshamroukh/opnsense/main/config.xml -O
echo -e "\e[1;36mCopying configuration files to $vm_name and installing opnsense firewall...\e[0m"
scp -o StrictHostKeyChecking=no $cloud_init_file $config_file $admin_username@$opnsense_public_ip:/home/$admin_username
ssh -o StrictHostKeyChecking=no $admin_username@$opnsense_public_ip "chmod +x /home/$admin_username/cloud_init.sh && /home/$admin_username/cloud_init.sh"
rm $cloud_init_file $config_file
echo -e "\e[1;31mVM is now rebooting. You can access it by going to https://$opnsense_public_ip/ \n usename: root \n passwd: opnsense\nIt's highly recommended to change the password\e[0m"

#https://publicIP/
#usename: root
#passwd: opnsense
