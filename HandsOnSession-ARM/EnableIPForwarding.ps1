$nicfw = Get-AzureRmNetworkInterface -ResourceGroupName jvh3rg-ng -Name jvh3win729
$nicfw.EnableIPForwarding = 0
Set-AzureRmNetworkInterface -NetworkInterface $nicfw