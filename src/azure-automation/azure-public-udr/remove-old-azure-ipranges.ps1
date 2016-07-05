Param
(
    [Parameter(Mandatory = $true)]
    [String] $region,

    [Parameter(Mandatory = $true)]
    [String] $routeTableName,

    [Parameter(Mandatory = $true)]
    [String] $resourceGroupName
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

# Remove routes not contained in most recent file from RouteTable.
$routeTable = Get-AzureRmRouteTable -Name $routeTableName -ResourceGroupName $resourceGroupName

[System.Collections.ArrayList]$routesToRemove = @()

# First get the list of routes to remove without actually removing
# so as to not disbturb the enumerable while we're enumerating.
ForEach ($route in $routeTable.Routes)
{
    $subnet = $route.Name.Replace("AzurePublic_", "").Replace("-", "/")

    If(($ipRange | where Subnet -eq $subnet) -eq $null)
    {
        $routesToRemove.Add($route.Name)
    }
    Else
    {
        Write-Output "Route $routeName still valid. Skipping."
    }	
}

# Now actually remove the routes.
ForEach ($routeToRemove in $routesToRemove)
{
    Remove-AzureRmRouteConfig -Name $routeToRemove -RouteTable $routeTable
}

# Finally, save the updated RouteTable.
Set-AzureRmRouteTable -RouteTable $routeTable