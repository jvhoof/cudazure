<#
.SYNOPSIS
NOTE ONLY FOR Azure Powershell 1.0 preview and beyond as it used the new AzureRM Module.
This script will perform deployments of Azure resource groups to create a default deployment of VNET, NG's, WAF's and a pair of servers.
.DESCRIPTION
The script 
.PARAMETERS
The script will promPts for the parameters it needs
.EXAMPLES


#>


#Functions
Function Create-Menu-Choice {
	<#
.SYNOPSIS
This function generates scriptblocks to be used to autogenerate input prompts.
It requires an array or hashtable. If you provide a hashtable you must provide

.DESCRIPTION

.PARAMETERS
Pass in the  

#>
param(
[string]$start_text, 
$array,
[string]$valuecolumnname,
[string]$textcolumnname
)


    $id = 0
    $text = $start_text + "`r`n"
    $scriptblock = ""

    if($valuecolumnname -and $textcolumnname){
           ForEach($entry in $array){
                $text += "$($id). $($entry.($textcolumnname)) `r`n" 
                $scriptblock += " `"$($id)`" { `$value1=`"$($entry.($valuecolumnname))`"; break; }"
                $id++;
            }
            $scriptblock += "} return `$value1"

    }else{
            ForEach($entry in $array){
                $text += "$($id). $($entry) `r`n" 
                $scriptblock += " `"$($id)`" { `$value1=`"$($entry)`"; break; }"
                $id++;
            }
            $scriptblock += "} return `$value1"
    }

    $b = "switch(Read-Host `"$($text)`"){"
    $b += $scriptblock

    return $b
}

#Checks if the right modules are present

Import-Module AzureRM -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

If((Get-Module AzureRM)){
$azurerm_version = (Get-Module -Name AzureRM).Version
    if($azurerm_version.Major -ge 1 ){
        Write-Host -ForegroundColor Green "AzureRM version $azurerm_version is present, please continue"
    }else{
        Write-Host -ForegroundColor Red "Warning AzureRM version $azurerm_version is present you need a minimum of 1.0.1"
    }
}else{
Write-Host -ForegroundColor Red "Warning, cannot find the AzureRM Module"
}


#Authenticate into Azure
#This section prompts for credentials and the selection to use

if(!$azure_creds){$azure_creds = Get-Credential}

Add-AzureRMAccount -Credential $azure_creds 

$subscriptionid = ([Scriptblock]::Create((Create-Menu-Choice -start_text "Please select a subscription" -array (Get-AzureRMSubscription) -valuecolumnname "SubscriptionId" -textcolumnname "SubscriptionName" )).Invoke())

Select-AzureRMSubscription -SubscriptionId "$($subscriptionid)"

if((Get-AzureRMSubscription).SubscriptionId -eq $subscriptionid){
Write-Host "Now working in: $((Get-AzureRMSubscription).SubscriptionName)";
}else{

Write-Host "Unable to select the desired subscription";
break;
}

<##############################################################################################################
# The below section will request location, prefix and NGF password parameters during the deployment.
# All other parameters need to be changed or are predefined using the prefix value to make them unique.
##############################################################################################################>

#get's a list of locations based upon the where virtual machines can be built.
$locations = ((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Compute).ResourceTypes | Where-Object -FilterScript {$_.ResourceTypeName -eq 'virtualMachines'}).Locations
$location = "$(([Scriptblock]::Create((Create-Menu-Choice -start_text "Please select a datacenter" -array ($locations))).Invoke()))"

$ng_password = Read-Host -AsSecureString "Please provide password for NG" 
$prefix = Read-Host "Please provide an identifying prefix for all VM's being build. e.g WE-PROD would become WE-PROD-VM-NG" 

$storageAccountNGF = "$prefix" + "storagengf" 
$storageAccountWAF = "$prefix" + "storagewaf" 

# VNET Configuration parameters
$vNETName = "$prefix-vnet"
$vNETPrefix = "172.16.70.0/24"

# Subnet Configuration parameters
$subnetNameNGF = "$prefix-subnet-ngf"
$subnetPrefixNGF = "172.16.70.0/28"
$subnetNameWAF = "$prefix-subnet-waf"
$subnetPrefixWAF = "172.16.70.16/28"
$subnetNameWEB = "$prefix-subnet-web"
$subnetPrefixWEB = "172.16.70.32/28"
$subnetNameAPP = "$prefix-subnet-app"
$subnetPrefixAPP = "172.16.70.48/28"
$subnetNameDB = "$prefix-subnet-db"
$subnetPrefixDB = "172.16.70.64/28"

# Resource Groups parameters
$ng_rg_name = "$prefix-RG-NGF"
$waf_rg_name = "$prefix-RG-WAF"
$web_rg_name = "$prefix-RG-WEB"
$vnet_rg_name = "$prefix-RG-VNET" 

# Public DNS parameters for WAF and NGF
# match ^[a-z][a-z0-9-]{1,61}[a-z0-9]$ - no caps
$dnsNameForNGF = "$prefix-ngf"
$dnsNameForWAF = "$prefix-waf"

# Deployment size for WAF and NGF
$vmSizeNGF = "Standard_A1"
$vmSizeWAF = "Standard_A1"

# SKU BYOL or Hourly license type
$imageSKU = "hourly"

<##############################################################################################################
# The below section will deploy the VNET, NG and NSG's uncomment it if you want to build them using the templates provided.
# Comment the whole section below between these comments to just use the UDR's
##############################################################################################################>

# VNET and subnets Deployment
<#
New-AzureRMResourceGroup -Name $vnet_rg_name -Location "$($location)"

New-AzureRMResourceGroupDeployment -Name "Deploy_$vnet_rg_name" -ResourceGroupName $vnet_rg_name `
    -TemplateFile "..\Templates\VNET_DeploymentTemplate.json" -location $location `
    -vNETName "$vNETName" -vNETPrefix "$vNETPrefix" `
    -subnetNameNGF "$subnetNameNGF" -subnetPrefixNGF "$subnetPrefixNGF" `
    -subnetNameWAF "$subnetNameWAF" -subnetPrefixWAF "$subnetPrefixWAF" `
    -subnetNameWEB "$subnetNameWEB" -subnetPrefixWEB "$subnetPrefixWEB" `
    -subnetNameAPP "$subnetNameAPP" -subnetPrefixAPP "$subnetPrefixAPP" `
    -subnetNameDB "$subnetNameDB" -subnetPrefixDB "$subnetPrefixDB" 
#>

# NextGen Firewall F-Series Deployment
<#
New-AzureRMResourceGroup -Name $ng_rg_name -Location $location

New-AzureRMResourceGroupDeployment -Name "Deploy_Barracuda_NextGen" -ResourceGroupName $ng_rg_name `
    -TemplateFile "..\Templates\NG_DeploymentTemplate.json" -location $location `
    -adminPassword $ng_password -storageAccount "$storageAccountNGF" -dnsNameForNGF "$dnsNameForNGF" `
    -vNetResourceGroup "$vnet_rg_name" -prefix "$prefix" -vNETName "$vNETName" `
    -subnetNameNGF "$subnetNameNGF" -subnetPrefixNGF "$subnetPrefixNGF" `
    -vmSize $vmSizeNGF -imageSKU $imageSKU
#>

# Web Application Firewall - WAF Deployment
New-AzureRMResourceGroup -Name $waf_rg_name -Location $location
New-AzureRMResourceGroupDeployment -Name "Deploy_Barracuda_WAF" -ResourceGroupName $waf_rg_name `
    -TemplateFile "..\Templates\WAF_DeploymentTemplate.json" -location $location `
    -adminPassword $ng_password -storageAccount "$storageAccountWAF" -dnsNameForWAF "$dnsNameForWAF" `
    -vNetResourceGroup "$vnet_rg_name" -prefix "$prefix" -vNETName "$vNETName" `
    -subnetNameWAF "$subnetNameWAF" -subnetPrefixWAF "$subnetPrefixWAF" `
    -vmSize $vmSizeWAF -imageSKU $imageSKU

#Web Server Resource
#New-AzureRMResourceGroup -Name $web_rg_name -Location $location
#New-AzureRMResourceGroupDeployment -Name "Deploy_Web_Servers" -ResourceGroupName $web_rg_name `
#    -TemplateFile "..\Templates\VM_DeploymentTemplate.json"  -TemplateParameterFile "..\Templates\properties.json" -location $location `
#    -newStorageAccountName "web$($storageaccount)" -adminPassword $ng_password  -vNetResourceGroup $vnet_rg_name `
#    -vNETName $vnet_name -PrefixName $prefix


<##############################################################################################################
End of the section that deploys the VNET and NG's
##############################################################################################################>


#Provide details of your Resource Groups and Config item names. This will need some modification to adapt to multiple routes.
#if(!$ng_rg_name){$ng_rg_name = Read-Host "Please provide the Resource Group that the NG's are deployed in"}
#if(!$vnet_rg_name){$vnet_rg_name = Read-Host "Please provide VNET Resource Group name"}




#Enable IPForwarding for all the NG's, this doesn't work via the templates as it defaults to false regardless of the setting in the json

#$ng_vms = (Get-AzureRMVM -ResourceGroupName $ng_rg_name | Where-Object -FilterScript {$_.Plan.Product -eq "barracuda-ng-firewall"})

#ForEach($ng in $ng_vms){ 
#$i++
#Get's the name of the NIC from the Interface ID
#    $nic_name = $ng.NetworkInterfaceIDs.Split("/")[($ng).NetworkInterfaceIDs.Split("/").Count-1]

    #Get the NIC Configuration, this presumes the NIC is in the same Resource Group as it's NG.
#    $nic = Get-AzureRMNetworkInterface -ResourceGroupName $ng_rg_name -Name $nic_name
#    $nic.EnableIPForwarding = "true"
    #Apply the changed configuration against the NIC
#    Set-AzureRMNetworkInterface -NetworkInterface $nic 
#    if($i -eq 1){
#       $gw=$($nic.IpConfigurations.PrivateIPAddress)
#    }
#    Write-Host "NG: $($ng.Name)"
#    Write-Host "NG IP: $($nic.IpConfigurations.PrivateIPAddress)"
#    Write-Host "NG IP: $($nic.EnableIPForwarding)"
#}


#Now create the route config. You could perhaps loop this section to ask the questions for each different route you wish to apply

#$rt_rg_name = Read-Host "Please provide routing Resource Group name"
#$rt_cfg_name = Read-Host "Please provide a name for the route"
#$subnet_name = Read-Host "Please provide the name of subnet that the route will apply against"
#$subnet_address_prefix = Read-Host "Please provide the CIDR of the subnet you will apply the route against"
#$rt_name = Read-Host "Please provide the route table name"
#$address_prefix = Read-Host "In CIDR format please provide the address to route for. `r`n If you wish the entire VNET to route via the NG use the address prefix for the vnet. `r`n If you use 0.0.0.0/0 only internet traffic will be impacted."
#$next_hop_ip = Read-Host "Please provide the next hop IP"

<#
Not supported yet but when the Powershell supports the preview API this should work.

#I created a new resource group for my routes, but you could use an existing one.
New-AzureRMResourceGroup -Name $rt_rg_name -Location $location

New-AzureRMResourceGroupDeployment -Name "Deploy_Routes_to_NG" -ResourceGroupName $rt_rg_name  `
-TemplateFile "..\Templates\UDR_DeploymentTemplate.json" -location $location `
 -vNetResourceGroup $vnet_rg_name -vNETName $vnet_name -routeTableName $rt_cfg_name -routeName $rt_name `
 -destinationNet "$($address_prefix)" -gatewayIP $next_hop_ip -subnetName $subnet_Name -Debug

#>


#I created a new resource group for my routes, but you could use an existing one.
#New-AzureRMResourceGroup -Name $rt_rg_name -Location $location

#Then create the Route configuration
#$route_cfg = New-AzureRMRouteConfig -Name $rt_cfg_name -AddressPrefix $address_prefix -NextHopType VirtualAppliance -NextHopIpAddress $next_hop_ip

#Now create the route table from the route configuration 
#$routetable = New-AzureRMRouteTable -Name $rt_name -ResourceGroupName $rt_rg_name -Location $location -Route $route_cfg 

#Now Set the route in Azure.
#Set-AzurermRouteTable -RouteTable $routetable 

#This next section associates the VNET and Subnet with the route

#Get your VVNET 
#$vnet = Get-AzureRMVirtualNetwork -ResourceGroupName $vnet_rg_name

#Use the below command to apply the route table to the subnet config in the vnet
#$newsubnetconfig = Set-AzureRMVirtualNetworkSubnetConfig -RouteTable $routetable -Vir