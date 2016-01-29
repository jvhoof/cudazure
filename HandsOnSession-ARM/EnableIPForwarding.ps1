$nicfw = Get-AzureRmNetworkInterface -ResourceGroupName JVH12-RG-NGF -Name JVH12-NIC-NGF0
$nicfw.EnableIPForwarding = 1
Set-AzureRmNetworkInterface -NetworkInterface $nicfw