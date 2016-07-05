Param
(
    [Parameter(Mandatory = $true)]
    [String] $region,

    [Parameter(Mandatory = $true)]
    [String] $routeTableName,

    [Parameter(Mandatory = $true)]
    [String] $resourceGroupName,
	
    # Saving a single route for Azure KMS Server
	[Parameter(Mandatory = $true)]
    [Int] $maxAllowedRoutes = 99
)

# Stop script (fail safe) should we encounter errors.
$script:ErrorActionPreference = 'Stop'

# Authenticate using the Azure Run As connection.
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    Write-Output "Logging in to Azure..."
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
        Write-Output "Attempting to download the download page..."
        $downloadPage = $webClient.DownloadString($downloadUri) 
        $xmlFileUri = ($downloadPage.Split('"') -like "https://*PublicIps*")[0]

        Write-Output "Attempting to download the XML file..."
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

# Update RouteTable with missing routes per most recent file.
$routeTable = Get-AzureRmRouteTable -Name $routeTableName -ResourceGroupName $resourceGroupName

# Default number of routes is 100 but can be increased to
# 400 by submitting support ticket.
$currentRouteCount = 0

ForEach ($subnet in $ipRange.Subnet)
{
    $routeName = "AzurePublic_" + $subnet.Replace("/", "-")
    $route = Get-AzureRmRouteConfig -RouteTable $routeTable -Name $routeName -ErrorAction SilentlyContinue
    If($route -eq $null)
    {
        Add-AzureRmRouteConfig -Name $routeName -AddressPrefix $subnet -NextHopType Internet -RouteTable $routeTable
    }
    Else
    {
        Write-Output "Route $routeName already exists. Skipping."
    }
	
	# Ensure we don't exceed max quantity of routes.	
	$currentRouteCount++
	If ($currentRouteCount -eq $maxAllowedRoutes)
	{
		break
	}	
}

# Finally, save the updated RouteTable.
Set-AzureRmRouteTable -RouteTable $routeTable