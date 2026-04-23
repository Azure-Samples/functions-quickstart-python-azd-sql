---
name: azure-sql-region-check
description: >-
  Checks which Azure regions allow provisioning new Azure SQL Database servers
  for the current subscription. Use when a user encounters ProvisioningDisabled
  or RegionDoesNotAllowProvisioning errors, or when they need help selecting an
  Azure region for SQL Database deployment.
---

# Azure SQL Region Availability Check

When users encounter `ProvisioningDisabled` or `RegionDoesNotAllowProvisioning` errors deploying Azure SQL, run the procedure below to find working regions on their subscription.

## Prerequisites

- User must be logged in to Azure CLI (`az login`)
- The correct subscription must be set (`az account set --subscription <id>`)
- If using `azd`, check the subscription with: `azd env get-values | grep AZURE_SUBSCRIPTION_ID`

## Procedure

### 1. Verify Azure CLI Authentication

```bash
az account show --query "{name:name, id:id}" --output table
```

If the token is expired, run `az login` first. If using a specific subscription for `azd`, set it:

```bash
az account set --subscription "<SUBSCRIPTION_ID>"
```

### 2. Batch Test Regions

Create a temporary resource group, attempt to create a SQL server in each candidate region, and report results. Clean up everything afterward.

**PowerShell:**

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

az group delete --name $rg --yes --no-wait
```

**Bash:**

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

az group delete --name $rg --yes --no-wait
```

### 3. Apply the Result

Once a working region is found, set it and deploy:

```bash
azd env set AZURE_LOCATION <working-region>
azd up
```

## Important Notes

- **Prefer US regions** (`westus2`, `westus3`) for lowest latency if the user is US-based.
- **Always clean up** test resources after validation.
- Region availability is dynamic — results may change over time.
- The `az sql db list-editions --available` command is NOT reliable for this check; it may show `Available: False` even when provisioning works.
- If ALL regions fail, the subscription itself may have SQL provisioning disabled — the user should contact Azure support or try a different subscription.
