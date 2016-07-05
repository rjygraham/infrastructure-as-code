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


# Authenticate using the Azure Run As connection.
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
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
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Download current list of Azure Public IP ranges
$downloadUri = "https://www.microsoft.com/en-in/download/confirmation.aspx?id=41653"

# Use WebClient instead of Invoke-WebRequest since IWR doesn't
# play nice in Azure Automation even with -UseBasicParsing flag.
$webClient = (New-Object System.Net.WebClient)

# Get and parse web page for updated list and then download the list
$downloadPage = $webClient.DownloadString($downloadUri) 
$xmlFileUri = ($downloadPage.Split('"') -like "https://*PublicIps*")[0]
$response = $webClient.DownloadString($xmlFileUri)

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