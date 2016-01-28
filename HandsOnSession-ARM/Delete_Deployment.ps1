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

$prefix = Read-Host "Please provide an identifying prefix for all VM's being build. e.g WeProd would become WeProd-VM-NGF (Max 19 char, no spaces, [A-Za-z0-9]" 

# Resource Groups parameters
$ngRGName = "$prefix-RG-NGF"
$wafRGName = "$prefix-RG-WAF"
$webRGName = "$prefix-RG-WEB"
$vnetRGName = "$prefix-RG-VNET" 

Write-Host Deleting Resource Group - $ngRGName
$input = Read-Host 'Do you want to delete it [Y/N] ?'
if ($input.ToUpper().Equals("Y"))
{
    Remove-AzureRmResourceGroup -Name $ngRGName -Force -Verbose
    Write-Host Deleted Resource Group - $ngRGName
}

Write-Host Deleting Resource Group - $wafRGName
$input = Read-Host 'Do you want to delete it [Y/N] ?'
if ($input.ToUpper().Equals("Y"))
{
    Remove-AzureRmResourceGroup -Name $wafRGName -Force -Verbose
    Write-Host Deleted Resource Group - $wafRGName
}

Write-Host Deleting Resource Group - $webRGName
$input = Read-Host 'Do you want to delete it [Y/N] ?'
if ($input.ToUpper().Equals("Y"))
{
    Remove-AzureRmResourceGroup -Name $webRGName -Force -Verbose
    Write-Host Deleted Resource Group - $webRGName
}

Write-Host Deleting Resource Group - $vnetRGName
$input = Read-Host 'Do you want to delete it [Y/N] ?'
if ($input.ToUpper().Equals("Y"))
{
    Remove-AzureRmResourceGroup -Name $vnetRGName -Force -Verbose
    Write-Host Deleted Resource Group - $vnetRGName
}