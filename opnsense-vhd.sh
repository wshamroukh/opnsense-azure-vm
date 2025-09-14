rg='opnsense'
location='centralindia'
vm_name='opnsense'
vhdUri=https://wadvhds.blob.core.windows.net/vhds/opnsense.vhd
storageType=Premium_LRS
vnet_name='opnsense-vnet'
vnet_address='10.10.0.0/16'
lan_subnet_name='lan-subnet'
lan_subnet_address='10.10.1.0/24'
wan_subnet_name='wan-subnet'
wan_subnet_address='10.10.0.0/24'
vm_size=Standard_B2als_v2

# resource group
echo -e "\e[1;36mCreating Resource Group $rg...\e[0m"
az group create -n $rg -l $location -o none

# vnet
echo -e "\e[1;36mCreating VNet $vnet_name...\e[0m"
az network vnet create -g $rg -n $vnet_name --address-prefixes $vnet_address --subnet-name $lan_subnet_name --subnet-prefixes $lan_subnet_address -o none
az network vnet subnet create -g $rg -n $wan_subnet_name --vnet-name $vnet_name --address-prefixes $wan_subnet_address -o none

# create a managed disk from a vhd
echo -e "\e[1;36mCreating $vm_name managed disk from a vhd...\e[0m"
az disk create -g $rg -n $vm_name --sku $storageType --location $location --size-gb 30 --source $vhdUri --os-type Linux -o none
#Get the resource Id of the managed disk
diskId=$(az disk show -n $vm_name -g $rg --query [id] -o tsv | tr -d '\r')

# Create opnsense VM by attaching existing managed disks as OS
echo -e "\e[1;36mCreating $vm_name VM...\e[0m"
az network public-ip create -g $rg -n $vm_name -l $location --allocation-method Static --sku Basic -o none
az network nic create -g $rg -n $vm_name-wan --subnet $wan_subnet_name --vnet-name $vnet_name --ip-forwarding true --private-ip-address 10.10.0.250 --public-ip-address $vm_name -o none
az network nic create -g $rg -n $vm_name-lan --subnet $lan_subnet_name --vnet-name $vnet_name --ip-forwarding true --private-ip-address 10.10.1.250 -o none
az vm create -n $vm_name -g $rg --nics $vm_name-wan $vm_name-lan --size Standard_B2als_v2 --attach-os-disk $diskId --os-type linux -o none
hub1_fw_public_ip=$(az network public-ip show -g $rg -n $vm_name --query 'ipAddress' -o tsv | tr -d '\r') && echo $vm_name public ip: $hub1_fw_public_ip
hub1_fw_wan_private_ip=$(az network nic show -g $rg -n $vm_name-wan --query ipConfigurations[].privateIPAddress -o tsv | tr -d '\r') && echo $vm_name wan private IP: $hub1_fw_wan_private_ip
hub1_fw_lan_private_ip=$(az network nic show -g $rg -n $vm_name-lan --query ipConfigurations[].privateIPAddress -o tsv | tr -d '\r') && echo $vm_name lan private IP: $hub1_fw_lan_private_ip

# opnsense vm boot diagnostics
echo -e "\e[1;36mEnabling VM boot diagnostics for $vm_name...\e[0m"
az vm boot-diagnostics enable -g $rg -n $vm_name -o none

echo -e "\e[1;32mOpnsense was Deployed Successfully.Try accessing it at https://$hub1_fw_public_ip/ with username: root and password: opnsense\e[0m"

#https://publicIP/
#usename: root
#passwd: opnsense

# Cleanup
# az group delete -g $rg --yes --no-wait -o none
