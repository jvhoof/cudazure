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

Login-AzureRMAccount -Credential $azure_creds 

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

$passwordVM = Read-Host -AsSecureString "Please provide password for NGF and Web Server" 
$prefix = Read-Host "Please provide an identifying prefix for all VM's being build. e.g WeProd would become WeProd-VM-NGF (Max 19 char, no spaces, [A-Za-z0-9]" 

$storageAccountNGF = $prefix.ToLower() + "stngf" 
$storageAccountWAF = $prefix.ToLower() + "stwaf" 
$storageAccountWEB = $prefix.ToLower() + "stweb" 

# VNET Configuration parameters
$vNETName = "$prefix-VNET"
$vNETPrefix = "172.16.136.0/22"

# Subnet Configuration parameters
$subnetNameNGF = "$prefix-SUBNET-NGF"
$subnetPrefixNGF = "172.16.136.0/24"
$subnetNameWAF = "$prefix-SUBNET-WAF"
$subnetPrefixWAF = "172.16.137.0/24"
$subnetNameWEB = "$prefix-SUBNET-WEB"
$subnetPrefixWEB = "172.16.138.0/24"

# Resource Groups parameters
$ngRGName = "$prefix-RG-NGF"
$wafRGName = "$prefix-RG-WAF"
$webRGName = "$prefix-RG-WEB"
$vnetRGName = "$prefix-RG-VNET" 

# Private IP for NextGen Firewall F
$pipAddressNGF = "172.16.136.4"

# Public DNS parameters for WAF and NGF
# match ^[a-z][a-z0-9-]{1,61}[a-z0-9]$ - no caps
$dnsNameForNGF = "$prefix-ngf"
$dnsNameForWAF = "$prefix-waf"

# Deployment size for WAF and NGF
$vmSizeNGF = "Standard_A1"
$vmSizeWAF = "Standard_A1"
$vmSizeWEB = "Standard_A1"

# SKU BYOL or Hourly license type
$imageSKU = "byol"

# Address prefix for all traffic towards internet
$vnetRTPrefixInternet = "0.0.0.0/0"
$vnetRTTableNameWAF = "$prefix-RT-WAF"
$vnetRTNameWAF1 = "$prefix-Route-To-WEB"
$vnetRTTableNameWEB = "$prefix-RT-WEB"
$vnetRTNameWEB1 = "$prefix-Route-To-WAF"
$vnetRTNameWEB2 = "$prefix-Route-To-Internet"

<##############################################################################################################
# The below section will deploy the VNET, NG and NSG's uncomment it if you want to build them using the templates provided.
# Comment the whole section below between these comments to just use the UDR's
##############################################################################################################>

# VNET and subnets Deployment
Write-Host "Creating Resource Group $vnetRGName for the networking configuration"
New-AzureRMResourceGroup -Name $vnetRGName -Location "$location"

Write-Host "Deploying VNET configuration"
New-AzureRMResourceGroupDeployment -Name "Deploy_$vnetRGName" -ResourceGroupName $vnetRGName `
    -TemplateFile "VNET_DeploymentTemplate.json" -location "$location" `
    -vNETName "$vNETName" -vNETPrefix "$vNETPrefix" `
    -subnetNameNGF "$subnetNameNGF" -subnetPrefixNGF "$subnetPrefixNGF" `
    -subnetNameWAF "$subnetNameWAF" -subnetPrefixWAF "$subnetPrefixWAF" `
    -subnetNameWEB "$subnetNameWEB" -subnetPrefixWEB "$subnetPrefixWEB" 

# NextGen Firewall F-Series Deployment
Write-Host "Creating Resource Group $ngRGName for the Barracuda NextGen Firewall F"
New-AzureRMResourceGroup -Name $ngRGName -Location $location

Write-Host "Deploying Barracuda NextGen Firewall F Series"
New-AzureRMResourceGroupDeployment -Name "Deploy_Barracuda_NextGen" -ResourceGroupName $ngRGName `
    -TemplateFile "NG_DeploymentTemplate.json" -location "$location" `
    -adminPassword $passwordVM -storageAccount "$storageAccountNGF" -dnsNameForNGF "$dnsNameForNGF" `
    -vNetResourceGroup "$vnetRGName" -prefix "$prefix" -vNETName "$vNETName" `
    -subnetNameNGF "$subnetNameNGF" -subnetPrefixNGF "$subnetPrefixNGF" `
    -vmSize $vmSizeNGF -imageSKU $imageSKU

# Web Application Firewall - WAF Deployment
Write-Host "Creating Resource Group $wafRGName for the Barracuda Web Application Firewall"
New-AzureRMResourceGroup -Name $wafRGName -Location $location

Write-Host "Deploying Barracuda Web Application Firewall"
New-AzureRMResourceGroupDeployment -Name "Deploy_Barracuda_WAF" -ResourceGroupName $wafRGName `
    -TemplateFile "WAF_DeploymentTemplate.json" -location "$location" `
    -adminPassword $passwordVM -storageAccount "$storageAccountWAF" -dnsNameForWAF "$dnsNameForWAF" `
    -vNetResourceGroup "$vnetRGName" -prefix "$prefix" -vNETName "$vNETName" `
    -subnetNameWAF "$subnetNameWAF" -subnetPrefixWAF "$subnetPrefixWAF" `
    -vmSize $vmSizeWAF -imageSKU $imageSKU

#Web Server Resource
Write-Host "Creating Resource Group $webRGName for the Web Server"
New-AzureRMResourceGroup -Name $webRGName -Location $location

Write-Host "Deploying the Web Server"
New-AzureRMResourceGroupDeployment -Name "Deploy_Web_Servers" -ResourceGroupName $webRGName `
    -TemplateFile "WEB_DeploymentTemplate.json" -location "$location" `
    -adminPassword $passwordVM -storageAccount "$storageAccountWEB" `
    -vNetResourceGroup "$vnetRGName" -prefix "$prefix" -vNETName "$vNETName" `
    -subnetNameWEB "$subnetNameWAF" -vmSize $vmSizeWEB

<##############################################################################################################
End of the section that deploys the VNET, NGF, WAF and Web Server
##############################################################################################################>

<##############################################################################################################
#
# IP FORWARDING
#
# Enable IPForwarding for all the NG's, this doesn't work via the templates as it defaults 
# to false regardless of the setting in the json
#
##############################################################################################################>

$ng_vms = (Get-AzureRMVM -ResourceGroupName $ngRGName | Where-Object -FilterScript {$_.Plan.Product -eq "barracuda-ng-firewall"})

ForEach($ng in $ng_vms){ 
    $i++
    #Get's the name of the NIC from the Interface ID
    $nic_name = $ng.NetworkInterfaceIDs.Split("/")[($ng).NetworkInterfaceIDs.Split("/").Count-1]

    #Get the NIC Configuration, this presumes the NIC is in the same Resource Group as it's NG.
    $nic = Get-AzureRMNetworkInterface -ResourceGroupName $ngRGName -Name $nic_name
    $nic.EnableIPForwarding = "true"
    #Apply the changed configuration against the NIC
    Set-AzureRMNetworkInterface -NetworkInterface $nic 
    if($i -eq 1){
       $gw=$($nic.IpConfigurations.PrivateIPAddress)
    }
    Write-Host "NG: $($ng.Name)"
    Write-Host "NG IP: $($nic.IpConfigurations.PrivateIPAddress)"
    Write-Host "NG IP: $($nic.EnableIPForwarding)"
}

<##############################################################################################################
#
# USER DEFINED ROUTING (UDR)
#
# Enable routing on the Azure platform. Routing is applied to the packets outgoing of a subnet  
# Foward and reverse routing need to be provided.
# Beware that there are implicit routes for all internal subnets. The default route 0.0.0.0/0 added using 
# UDR is for all route except for the implicit routes. To activate routing between subnets via the NGF these 
# routes need to be overwritten with UDR VirtualAppliance routes instead of the VNETLocal routes.
#
##############################################################################################################>

Write-Host "Updating the Resource Group $vnetRGName for the routing configuration"
New-AzureRMResourceGroup -Name $vnetRGName -Location $location

Write-Host "Deploying the UDR Routing for WEB Subnet"
#Now create the route table from the route configuration 
Write-Host "Test: $vnetRTTableNameWEB - $vnetRGName - $location"
$routeTableWeb = New-AzureRMRouteTable -Name $vnetRTTableNameWEB -ResourceGroupName $vnetRGName -Location $location

# Route from WEB Subnet to WAF Subnet
$routeTableWeb | Add-AzureRmRouteConfig `
        -Name $vnetRTNameWEB1 `
        -AddressPrefix $subnetPrefixWAF `
        -NextHopType VirtualAppliance `
        -NextHopIpAddress $pipAddressNGF

$routeTableWeb | Add-AzureRmRouteConfig `
        -Name $vnetRTNameWEB2 `
        -AddressPrefix $vnetRTPrefixInternet `
        -NextHopType VirtualAppliance `
        -NextHopIpAddress $pipAddressNGF

#Now Set the route in Azure.
Set-AzurermRouteTable -RouteTable $routeTableWeb 

#This next section associates the VNET and Subnet with the route

#Get your VVNET 
$vnet = Get-AzureRMVirtualNetwork -ResourceGroupName $vnetRGName

#Use the below command to apply the route table to the subnet config in the vnet
$newsubnetconfig = Set-AzureRMVirtualNetworkSubnetConfig -RouteTable $routeTableWeb `
                        -VirtualNetwork $vnet `
                        -Name $subnetNameWEB `
                        -AddressPrefix $subnetPrefixWEB
 
#Now apply the change into Azure. 
Set-AzureRMVirtualNetwork -VirtualNetwork $vnet

Write-Host "Deploying the UDR Routing for WAF Subnet"
#Now create the route table from the route configuration 
$routeTableWAF = New-AzureRMRouteTable -Name $vnetRTTableNameWAF -ResourceGroupName $vnetRGName -Location $location

# Route from WEB Subnet to WAF Subnet
$routeTableWAF | Add-AzureRmRouteConfig `
        -Name $vnetRTNameWAF1 `
        -AddressPrefix $subnetPrefixWEB `
        -NextHopType VirtualAppliance `
        -NextHopIpAddress $pipAddressNGF

#Now Set the route in Azure.
Set-AzurermRouteTable -RouteTable $routeTableWAF

#This next section associates the VNET and Subnet with the route

#Get your VVNET 
$vnet = Get-AzureRMVirtualNetwork -ResourceGroupName $vnetRGName

#Use the below command to apply the route table to the subnet config in the vnet
$newsubnetconfig = Set-AzureRMVirtualNetworkSubnetConfig -RouteTable $routeTableWAF `
                        -VirtualNetwork $vnet `
                        -Name $subnetNameWAF `
                        -AddressPrefix $subnetPrefixWAF
 
#Now apply the change into Azure. 
Set-AzureRMVirtualNetwork -VirtualNetwork $vnet

Write-Host "Script Finished. Please now configure the devices."