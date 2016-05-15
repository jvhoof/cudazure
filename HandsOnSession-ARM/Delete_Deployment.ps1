<#
.SYNOPSIS
NOTE ONLY FOR Azure Powershell 1.0 preview and beyond as it used the new AzureRM Module.
.DESCRIPTION
This script will delete the deployment of the NGF, WAF, WEB and networking. 
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

#Authenticate into Azure
Login-AzureRMAccount

$subscriptionid = ([Scriptblock]::Create((Create-Menu-Choice -start_text "Please select a subscription" -array (Get-AzureRMSubscription) -valuecolumnname "SubscriptionId" -textcolumnname "SubscriptionName" )).Invoke())

Select-AzureRMSubscription -SubscriptionId "$($subscriptionid)"

if((Get-AzureRMSubscription).SubscriptionId -eq $subscriptionid){
Write-Host "Now working in: $((Get-AzureRMSubscription).SubscriptionName)";
}else{

Write-Host "Unable to select the desired subscription";
break;
}

$prefix = ""
do {
    if( $prefix.length -gt 7 ) {
        Write-Host "ERROR: Prefix too long" -ForegroundColor Red
    }
    $prefix = Read-Host "`nPlease provide an identifying prefix for all VM's being build. e.g WeProd would become WeProd-VM-NGF (Max 6 char, no spaces, [A-Za-z0-9]"
} while ($prefix.length -gt 7)

# Resource Groups parameters
$ngRGName = "$prefix-RG-NGF"
$wafRGName = "$prefix-RG-WAF"
$webRGName = "$prefix-RG-WEB"
$vnetRGName = "$prefix-RG-VNET" 

Write-Host Deleting Resource Group - $ngRGName
$input = Read-Host 'Do you want to delete it [Y/N/A] ?'
if ($input.ToUpper().Equals("Y") -Or $input.ToUpper().Equals("A")) {
    Remove-AzureRmResourceGroup -Name $ngRGName -Force
    Write-Host Deleted Resource Group - $ngRGName
}

Write-Host Deleting Resource Group - $wafRGName
if (! ($input.ToUpper().Equals("A"))) {
    $input = Read-Host 'Do you want to delete it [Y/N] ?'
}
if ($input.ToUpper().Equals("Y") -Or $input.ToUpper().Equals("A")) {
    Remove-AzureRmResourceGroup -Name $wafRGName -Force
    Write-Host Deleted Resource Group - $wafRGName
}

Write-Host Deleting Resource Group - $webRGName
if (! ($input.ToUpper().Equals("A"))) {
    $input = Read-Host 'Do you want to delete it [Y/N] ?'
}
if ($input.ToUpper().Equals("Y") -Or $input.ToUpper().Equals("A")) {
    Remove-AzureRmResourceGroup -Name $webRGName -Force
    Write-Host Deleted Resource Group - $webRGName
}

Write-Host Deleting Resource Group - $vnetRGName
if (! ($input.ToUpper().Equals("A"))) {
    $input = Read-Host 'Do you want to delete it [Y/N] ?'
}
if ($input.ToUpper().Equals("Y") -Or $input.ToUpper().Equals("A")) {
    Remove-AzureRmResourceGroup -Name $vnetRGName -Force
    Write-Host Deleted Resource Group - $vnetRGName
}