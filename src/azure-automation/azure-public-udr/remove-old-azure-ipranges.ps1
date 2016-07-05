﻿Param
(
    [Parameter(Mandatory = $true)]
    [String] $region,

    [Parameter(Mandatory = $true)]
    [String] $routeTableName,

    [Parameter(Mandatory = $true)]
    [String] $resourceGroupName,

    [Parameter(Mandatory = $false)]
    [String] $kmsRouteName
)

# Stop script (fail safe) should we encounter errors. We wouldn't want to
# wipe out an entire route table, would we? ;-)
$script:ErrorActionPreference = 'Stop'

# Authenticate using the Azure Run As connection.
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    Write-Information "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error $_.Exception
        throw $_.Exception
    }
}

# Location of the page hosting Public IP address XML file.
$downloadUri = "https://www.microsoft.com/en-in/download/confirmation.aspx?id=41653"

# Use WebClient instead of Invoke-WebRequest since IWR doesn't
# play nice in Azure Automation even with -UseBasicParsing flag.
$webClient = (New-Object System.Net.WebClient)

# Attempt to download current list of Azure Public IP ranges
$downloadAttempt = 1

do 
{
    try
    {
        # Get and parse web page for updated list and then download the list
        Write-Information "Attempting to download the download page..."
        $downloadPage = $webClient.DownloadString($downloadUri) 
        $xmlFileUri = ($downloadPage.Split('"') -like "https://*PublicIps*")[0]

        Write-Information "Attempting to download the XML file..."
        $response = $webClient.DownloadString($xmlFileUri)
    }
    catch 
    {
        Write-Warning "Download attempt $downloadAttempt failed: $($_.Exception)"

        if ($downloadAttempt -eq 3)
        {
            Write-Error "Could not download Public Azure IP address file. Terminating."
            throw $_.Exception
        }

        $downloadAttempt++
    }

} while ($response -eq $null -and $downloadAttempt -le 3)

# Get list of regions & public IP ranges
[xml]$xmlResponse = $response
$regions = $xmlResponse.AzurePublicIpAddresses.Region
$ipRange = ($regions | where-object Name -In $region).IpRange

# Remove routes not contained in most recent file from RouteTable.
$routeTable = Get-AzureRmRouteTable -Name $routeTableName -ResourceGroupName $resourceGroupName

[System.Collections.ArrayList]$routesToRemove = @()

# First get the list of routes to remove without actually removing
# so as to not disbturb the enumerable while we're enumerating.
ForEach ($route in $routeTable.Routes)
{
    # Ensure we don't remove the KMS Server route that may have been added.
    If ($kmsRouteName -eq $null -or $route.Name -ne $kmsRouteName)
    {
        $subnet = $route.Name.Replace("AzurePublic_", "").Replace("-", "/")

        If(($ipRange | where Subnet -eq $subnet) -eq $null)
        {
            $routesToRemove.Add($route.Name)
        }
        Else
        {
            Write-Output "Route $($route.Name) still valid. Skipping."
        }	
    }
}

# Now actually remove the routes.
ForEach ($routeToRemove in $routesToRemove)
{
    Remove-AzureRmRouteConfig -Name $routeToRemove -RouteTable $routeTable
}

# Finally, save the updated RouteTable.
Set-AzureRmRouteTable -RouteTable $routeTable