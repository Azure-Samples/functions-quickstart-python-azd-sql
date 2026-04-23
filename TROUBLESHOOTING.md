# Troubleshooting

## Azure SQL Region Selection — `ProvisioningDisabled` or `RegionDoesNotAllowProvisioning`

When deploying with `azd up`, you may encounter errors like:

```
ProvisioningDisabled: Provisioning is restricted in this region.
```

or

```
RegionDoesNotAllowProvisioning: Location 'East US' is not accepting creation of new Windows Azure SQL Database servers at this time.
```

This means your Azure subscription cannot create new SQL servers in the selected region. This is **not a bug in the template** — it's an Azure capacity or policy restriction that varies by subscription and changes over time.

### How to Find a Working Region

Use the Azure CLI to test which regions actually allow SQL server provisioning on your subscription. This creates a temporary SQL server, checks if it succeeds, and cleans up immediately.

#### Quick Single-Region Test

```bash
# Create a temporary resource group
az group create --name rg-sqltest-temp --location eastus --output none

# Test a specific region
az sql server create \
  --name "sqltest-$(shuf -i 10000-99999 -n 1)" \
  --resource-group rg-sqltest-temp \
  --location <REGION_TO_TEST> \
  --enable-ad-only-auth \
  --external-admin-principal-type User \
  --external-admin-name "test@test.com" \
  --external-admin-sid "$(az ad signed-in-user show --query id --output tsv)"

# Clean up
az group delete --name rg-sqltest-temp --yes --no-wait
```

If the command succeeds, the region works. If you see `RegionDoesNotAllowProvisioning`, try another region.

#### Batch Test Multiple Regions (PowerShell)

```powershell
$rg = "rg-sqltest-$(Get-Random -Maximum 9999)"
az group create --name $rg --location eastus --output none

$regions = @(
    "eastus", "eastus2", "westus2", "westus3",
    "centralus", "southcentralus", "northcentralus",
    "canadacentral", "westeurope", "northeurope",
    "uksouth", "australiaeast", "southeastasia",
    "swedencentral", "japaneast"
)

$userId = az ad signed-in-user show --query id --output tsv

foreach ($r in $regions) {
    $name = "sqltest$(Get-Random -Maximum 99999)"
    $result = az sql server create --name $name --resource-group $rg `
        --location $r --enable-ad-only-auth `
        --external-admin-principal-type User `
        --external-admin-name "test@test.com" `
        --external-admin-sid $userId 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ $r"
        az sql server delete --name $name --resource-group $rg --yes 2>$null
    } else {
        Write-Host "❌ $r"
    }
}

# Clean up
az group delete --name $rg --yes --no-wait
```

#### Batch Test Multiple Regions (Bash)

```bash
rg="rg-sqltest-$RANDOM"
az group create --name $rg --location eastus --output none

userId=$(az ad signed-in-user show --query id --output tsv)

for r in eastus eastus2 westus2 westus3 centralus southcentralus \
         northcentralus canadacentral westeurope northeurope \
         uksouth australiaeast southeastasia swedencentral japaneast; do
    name="sqltest$RANDOM"
    if az sql server create --name "$name" --resource-group "$rg" \
        --location "$r" --enable-ad-only-auth \
        --external-admin-principal-type User \
        --external-admin-name "test@test.com" \
        --external-admin-sid "$userId" &>/dev/null; then
        echo "✅ $r"
        az sql server delete --name "$name" --resource-group "$rg" --yes &>/dev/null
    else
        echo "❌ $r"
    fi
done

# Clean up
az group delete --name $rg --yes --no-wait
```

### Once You Find a Working Region

Set it in your azd environment and deploy:

```bash
azd env set AZURE_LOCATION <working-region>
azd up
```

### Common Regions That Are Often Available

Based on testing, the following regions tend to have better availability for new Azure SQL server provisioning (though this can change at any time):

- `westus2`
- `westus3`
- `northeurope`
- `uksouth`
- `australiaeast`
- `southeastasia`
- `swedencentral`

> **Note:** Region availability is dynamic and varies by subscription type (Enterprise, Pay-As-You-Go, Visual Studio, etc.). Always validate with the script above before deploying.

### Other Solutions

- **Open a support request** to unlock provisioning in a specific region: [Request a quota increase](https://docs.microsoft.com/en-us/azure/sql-database/quota-increase-request)
- **Upgrade your subscription** — free, trial, and student subscriptions have more region restrictions than Pay-As-You-Go or Enterprise subscriptions.
