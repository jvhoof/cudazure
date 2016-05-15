Write-Host "
##############################################################################################################

  ____                                      _       
 | __ )  __ _ _ __ _ __ __ _  ___ _   _  __| | __ _ 
 |  _ \ / _` | '__| '__/ _` |/ __| | | |/ _` |/ _` |
 | |_) | (_| | |  | | | (_| | (__| |_| | (_| | (_| |
 |____/ \__,_|_|  |_|  \__,_|\___|\__,_|\__,_|\__,_|

                                                    
 Hands-on Session to deploy Barracuda NextGen Firewall F-Series and Barracuda Web Application Firewall into
 Microsoft Azure

 More information can be found at http://bit.do/cudazure

 Any questions during deployment: jvanhoof@barracuda.com

##############################################################################################################
"


<#
.SYNOPSIS
NOTE ONLY FOR Azure Powershell 1.0 preview and beyond as it used the new AzureRM Module.
This script will perform deployments of Azure resource groups to create a default deployment of VNET, NG's, WAF's and a pair of servers.
.DESCRIPTION
The script 
.PARAMETERS
The script will prompts for the parameters it needs
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

<##############################################################################################################
# Verify that the templates are available and in the current working directory.  
##############################################################################################################>
If (! ( (Test-Path "VNET_DeploymentTemplate.json") -Or (Test-Path "NG_DeploymentTemplate.json") -Or (Test-Path "WAF_DeploymentTemplate.json") -Or (Test-Path "WEB_DeploymentTemplate.json") ) ){
    Write-Host "Unable to find the templates. `nMake sure they are in the same directory as the powershell script. `nChange the current directory to the script directory." -foreground "magenta"
    Exit
}

<##############################################################################################################
# Log into Microsoft Azure and select the correct Subscription
# All other parameters need to be changed or are predefined using the prefix value to make them unique.
##############################################################################################################>

Login-AzureRMAccount

$subscriptionid = ([Scriptblock]::Create((Create-Menu-Choice -start_text "Please select a subscription" -array (Get-AzureRMSubscription) -valuecolumnname "SubscriptionId" -textcolumnname "SubscriptionName" )).Invoke())

Select-AzureRMSubscription -SubscriptionId "$($subscriptionid)"

if((Get-AzureRMSubscription).SubscriptionId -eq $subscriptionid){
    Write-Host "Now working in: $((Get-AzureRMSubscription).SubscriptionName)";
} else {
    Write-Host "Unable to select the desired subscription";
    break;
}

<##############################################################################################################
# The below section will request location, prefix and NGF password parameters during the deployment.
# All other parameters need to be changed or are predefined using the prefix value to make them unique.
##############################################################################################################>

# get's a list of locations based upon the where virtual machines can be built.
$locations = ((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Compute).ResourceTypes | Where-Object -FilterScript {$_.ResourceTypeName -eq 'virtualMachines'}).Locations
$location = "$(([Scriptblock]::Create((Create-Menu-Choice -start_text "Please select a datacenter" -array ($locations))).Invoke()))"

$passwordVM = Read-Host -AsSecureString 'Please provide password for NGF and Web Server
!! BEWARE: Password complexity rules [A-Za-z0-9] and special char !!' 
$prefix = ""
do {
    if( $prefix.length -gt 7 ) {
        Write-Host "ERROR: Prefix too long" -ForegroundColor Red
    }
    $prefix = Read-Host "`nPlease provide an identifying prefix for all VM's being build. e.g WeProd would become WeProd-VM-NGF (Max 6 char, no spaces, [A-Za-z0-9]"
} while ($prefix.length -gt 7)

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

# Microsoft Azure Default Gateway for the NGF Subnet
$subnetGatewayIP = "172.16.136.1"
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
try {
    # VNET and subnets Deployment
    Write-Host "`nCreating Resource Group $vnetRGName for the networking configuration"
    New-AzureRMResourceGroup -Name $vnetRGName -Location "$location"

    Write-Host "Deploying VNET configuration"
    New-AzureRMResourceGroupDeployment -Name "Deploy_$vnetRGName" -ResourceGroupName $vnetRGName `
        -TemplateFile "VNET_DeploymentTemplate.json" -location "$location" `
        -vNETName "$vNETName" -vNETPrefix "$vNETPrefix" `
        -subnetNameNGF "$subnetNameNGF" -subnetPrefixNGF "$subnetPrefixNGF" `
        -subnetNameWAF "$subnetNameWAF" -subnetPrefixWAF "$subnetPrefixWAF" `
        -subnetNameWEB "$subnetNameWEB" -subnetPrefixWEB "$subnetPrefixWEB"  
} catch { 
    write-host "Caught an exception while deploying the VNET:" -ForegroundColor Red
    write-host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    # NextGen Firewall F-Series Deployment
    Write-Host "Creating Resource Group $ngRGName for the Barracuda NextGen Firewall F"
    New-AzureRMResourceGroup -Name $ngRGName -Location $location

    Write-Host "Deploying Barracuda NextGen Firewall F Series"
    New-AzureRMResourceGroupDeployment -Name "Deploy_Barracuda_NextGen" -ResourceGroupName $ngRGName `
        -TemplateFile "NG_DeploymentTemplate.json" -location "$location" `
        -adminPassword $passwordVM -storageAccountNamePrefix "$storageAccountNGF" -dnsNameForNGF "$dnsNameForNGF" `
        -vNetResourceGroup "$vnetRGName" -prefix "$prefix" -vNETName "$vNETName" `
        -subnetNameNGF "$subnetNameNGF" -subnetPrefixNGF "$subnetPrefixNGF" -pipAddressNGF "$pipAddressNGF" `
        -subnetGatewayIP "$subnetGatewayIP" -vmSize "$vmSizeNGF" -imageSKU "$imageSKU"
} catch { 
    write-host "Caught an exception while deploying the Barracuda NextGen Firewall F-Series:" -ForegroundColor Red
    write-host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    throw "Please review error, delete resources and redeploy"
}

try {
    # Web Application Firewall - WAF Deployment
    Write-Host "Creating Resource Group $wafRGName for the Barracuda Web Application Firewall"
    New-AzureRMResourceGroup -Name $wafRGName -Location $location

    Write-Host "Deploying Barracuda Web Application Firewall"
    New-AzureRMResourceGroupDeployment -Name "Deploy_Barracuda_WAF" -ResourceGroupName $wafRGName `
        -TemplateFile "WAF_DeploymentTemplate.json" -location "$location" `
        -adminPassword $passwordVM -storageAccountNamePrefix "$storageAccountWAF" -dnsNameForWAF "$dnsNameForWAF" `
        -vNetResourceGroup "$vnetRGName" -prefix "$prefix" -vNETName "$vNETName" `
        -subnetNameWAF "$subnetNameWAF" -subnetPrefixWAF "$subnetPrefixWAF" `
        -vmSize $vmSizeWAF -imageSKU $imageSKU
} catch { 
    write-host "Caught an exception while deploying the Barracuda Web Application Firewall:" -ForegroundColor Red
    write-host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    throw "Please review error, delete resources and redeploy"
}

try {
    #Web Server Resource
    Write-Host "Creating Resource Group $webRGName for the Web Server"
    New-AzureRMResourceGroup -Name $webRGName -Location $location

    Write-Host "Deploying the Web Server"
    New-AzureRMResourceGroupDeployment -Name "Deploy_Web_Servers" -ResourceGroupName $webRGName `
        -TemplateFile "WEB_DeploymentTemplate.json" -location "$location" `
        -adminPassword $passwordVM -storageAccountNamePrefix "$storageAccountWEB" `
        -vNetResourceGroup "$vnetRGName" -prefix "$prefix" -vNETName "$vNETName" `
        -subnetNameWEB "$subnetNameWEB" -vmSize $vmSizeWEB
} catch { 
    write-host "Caught an exception while deploying the Web Server:" -ForegroundColor Red
    write-host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    throw "Please review error, delete resources and redeploy"
}

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

try {
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
        Write-Host "IP Forwarding for NGF"
        Write-Host "NGF: $($ng.Name)"
        Write-Host "NGF IP: $($nic.IpConfigurations.PrivateIPAddress)"
        Write-Host "NGF IP: $($nic.EnableIPForwarding)"
    }
} catch { 
    write-host "Caught an exception while enabling IP Forwarding:" -ForegroundColor Red
    write-host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    throw "Please review error, delete resources and redeploy"
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

try {
    # Write-Host "Updating the Resource Group $vnetRGName for the routing configuration"
    # New-AzureRMResourceGroup -Name $vnetRGName -Location $location

    Write-Host "Deploying the UDR Routing for WEB Subnet"
    #Now create the route table from the route configuration 
    Write-Host "Test: $vnetRTTableNameWEB - $vnetRGName - $location"
    $routeTableWeb = New-AzureRMRouteTable -Name $vnetRTTableNameWEB -ResourceGroupName $vnetRGName -Location $location

    # Route from WEB Subnet to WAF Subnet
    Add-AzureRmRouteConfig `
            -Name $vnetRTNameWEB1 `
            -RouteTable $routeTableWeb `
            -AddressPrefix $subnetPrefixWAF `
            -NextHopType VirtualAppliance `
            -NextHopIpAddress $pipAddressNGF

    Add-AzureRmRouteConfig `
            -Name $vnetRTNameWEB2 `
            -RouteTable $routeTableWeb `
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
    Add-AzureRmRouteConfig `
            -Name $vnetRTNameWAF1 `
            -RouteTable $routeTableWAF `
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
} catch { 
    write-host "Caught an exception while deploying User Defined Routing:" -ForegroundColor Red
    write-host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    throw "Please review error, delete resources and redeploy"
}

Write-Host "
##############################################################################################################
 
 Script Finished. You can now configure the devices.

 NGF:
 IP address: Azure Portal. Check the NGF system IP.
 Username: root
 Password: (configured during the deployment script) 
 
 WAF:
 IP address: Azure portal. Check the WAF LB.
 Username: admin
 Password: admin
 
 Web Server:
 IP address: Publish the Web server via the NGF 
 Username: azureuser
 Password: (configured during the deployment script)
                                                     

##############################################################################################################
"

Write-Host "Script Finished. Please now configure the devices."
