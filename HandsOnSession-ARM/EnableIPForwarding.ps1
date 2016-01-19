$nicfw = Get-AzureRmNetworkInterface -ResourceGroupName jvh14-RG-NGF -Name jvh14-vm-ngf575
$nicfw.EnableIPForwarding = 1
Set-AzureRmNetworkInterface -NetworkInterface $nicfw