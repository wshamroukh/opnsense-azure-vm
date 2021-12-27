#!/usr/bin/bash
#variables
location='westeurope'
rg_name='opnsense'
vm_name='opnsense'
vm_image='thefreebsdfoundation:freebsd-12_2:12_2-release:12.2.0'
vnet_name='opnsense-vnet'
vnet_address='10.10.0.0/16'
lan_subnet_name='lan-subnet'
lan_subnet_address='10.10.1.0/24'
wan_subnet_name='wan-subnet'
wan_subnet_address='10.10.0.0/24'
admin_username='waddahs'
admin_password='P@ssw0rd#$3cr3t'
cloud_init_file=~/cloud_init.sh
tee -a $cloud_init_file > /dev/null <<'EOF'
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
sudo sh ~/opnsense-bootstrap.sh.in -r 21.7
sudo cp config.xml /usr/local/etc/config.xml
sudo reboot
EOF

sed -i "/\$admin_password/ s//$admin_password/" $cloud_init_file
sed -i "/\\\n\$admin_password/ s//\\\n$admin_password/" $cloud_init_file

function wait_until_finished {
     wait_interval=15
     resource_id=$1
     resource_name=$(echo $resource_id | cut -d/ -f 9)
     echo -e "\e[1;36m Waiting for resource $resource_name to finish provisioning...\e[0m"
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

az group create -n $rg_name -l $location
az network vnet create -n $vnet_name -g $rg_name --address-prefixes $vnet_address --subnet-name $lan_subnet_name --subnet-prefixes $lan_subnet_address
az network vnet subnet create -n $wan_subnet_name -g $rg_name --vnet-name $vnet_name --address-prefixes $wan_subnet_address
az network public-ip create -n "$vm_name-public-ip" -g $rg_name --allocation-method Static --sku Basic
az network nic create -n "$vm_name-wan-nic" -g $rg_name --subnet $wan_subnet_name --vnet-name $vnet_name --ip-forwarding true --private-ip-address 10.10.0.250 --public-ip-address "$vm_name-public-ip"
az network nic create -n "$vm_name-lan-nic" -g $rg_name --subnet $lan_subnet_name --vnet-name $vnet_name --ip-forwarding true --private-ip-address 10.10.1.250
az vm create -n $vm_name -g $rg_name --image $vm_image --nics "$vm_name-wan-nic" "$vm_name-lan-nic" --os-disk-name $vm_name-osdisk --size Standard_B2s --admin-username $admin_username --admin-password $admin_password --no-wait
opnsense_public_ip=$(az network public-ip show -n "$vm_name-public-ip" -g $rg_name --query 'ipAddress' --output tsv)
sleep 30
opnsense_vm_id=$(az vm show -n $vm_name -g $rg_name --query 'id' -o tsv)
wait_until_finished $opnsense_vm_id

config_file=~/config.xml
curl https://raw.githubusercontent.com/wshamroukh/opnsense/main/config.xml -O
scp $cloud_init_file $config_file $admin_username@$opnsense_public_ip:/home/$admin_username
ssh $admin_username@$opnsense_public_ip "chmod +x /home/$admin_username/cloud_init.sh && /home/$admin_username/cloud_init.sh"
rm $cloud_init_file $config_file
echo -e "\e[1;31mVM is now rebooting. You can access it by going to https://$opnsense_public_ip/ \n usename: root \n passwd: opnsense\nIt's highly recommended to change the password\e[0m"

#https://publicIP/
#usename: root
#passwd: opnsense
