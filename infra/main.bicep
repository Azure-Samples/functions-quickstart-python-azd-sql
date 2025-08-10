targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources & Flex Consumption Function App')
@allowed([
  'australiaeast'
  'australiasoutheast'
  'brazilsouth'
  'canadacentral'
  'centralindia'
  'centralus'
  'eastasia'
  'eastus'
  'eastus2'
  'eastus2euap'
  'francecentral'
  'germanywestcentral'
  'italynorth'
  'japaneast'
  'koreacentral'
  'northcentralus'
  'northeurope'
  'norwayeast'
  'southafricanorth'
  'southcentralus'
  'southeastasia'
  'southindia'
  'spaincentral'
  'swedencentral'
  'uaenorth'
  'uksouth'
  'ukwest'
  'westcentralus'
  'westeurope'
  'westus'
  'westus2'
  'westus3'
])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string
param apiServiceName string = ''
param apiUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param keyVaultName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''
param sqlServerName string = ''
param apimServiceName string = ''
param connectionStringKey string = 'AZURE-SQL-CONNECTION-STRING'

@description('Flag to enable SQL scripts for database user and role setup')
param enableSQLScripts bool = false

@description('Flag to use Azure API Management to mediate the calls between the Web frontend and the backend API')
param useAPIM bool = false

@description('API Management SKU to use if APIM is enabled')
param apimSku string = 'Consumption'

param vnetEnabled bool
param vNetName string = ''

@description('Id of the user or app to assign application roles')
param principalId string = ''

param sqlDatabaseName string = ''

var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}api-${resourceToken}'


// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// User assigned managed identity to be used by the function app to reach storage and other dependencies
// Assign specific roles to this identity in the RBAC module
module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}api-${resourceToken}'
  }
}

// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan 'br/public:avm/res/web/serverfarm:0.1.1' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
    reserved: true
    location: location
    tags: tags
  }
}

module api './app/api.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.name
    appServicePlanId: appServicePlan.outputs.resourceId
    runtimeName: 'python'
    runtimeVersion: '3.12'
    storageAccountName: storage.outputs.name
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: apiUserAssignedIdentity.outputs.resourceId
    identityClientId: apiUserAssignedIdentity.outputs.clientId
    sqlAdminIdentityId: enableSQLScripts ? db.outputs.sqlAdminIdentityId : ''
    appSettings: {
      AZURE_KEY_VAULT_ENDPOINT: enableSQLScripts ? db.outputs.keyVaultUri : ''
      AZURE_SQL_CONNECTION_STRING_KEY: 'Server=${db.outputs.name}${environment().suffixes.sqlServerHostname}; Database=${db.outputs.databaseName}; Authentication=Active Directory Default; User Id=${apiUserAssignedIdentity.outputs.clientId}; TrustServerCertificate=True'
    }
    virtualNetworkSubnetId: vnetEnabled ? serviceVirtualNetwork.outputs.appSubnetID : ''
  }
}

// The application database
// Import the database resources from db.bicep
module db './app/db.bicep' = {
  name: 'database'
  scope: rg
  params: {
    location: location
    tags: tags
    sqlServerName: sqlServerName
    abbrs: abbrs
    resourceToken: resourceToken
    sqlDatabaseName: sqlDatabaseName
    apiUserAssignedIdentityName: apiUserAssignedIdentity.outputs.name
    apiUserAssignedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    apiUserAssignedIdentityClientId: apiUserAssignedIdentity.outputs.clientId
    enableSQLScripts: enableSQLScripts
    keyVaultName: keyVaultName
    principalId: principalId
    connectionStringKey: connectionStringKey
  }
}

var desktopIpAddress = '67.171.31.164'  // change to valid

module storage 'br/public:avm/res/storage/storage-account:0.8.3' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location // Assuming 'location' is a defined parameter or variable
    tags: tags       // Assuming 'tags' is a defined parameter or variable
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // Disable local authentication methods as per policy
    dnsEndpointType: 'Standard'
    publicNetworkAccess: 'Enabled'  // Pinning this to enabled, and we use defaultAction Deny or Allow
    networkAcls: vnetEnabled ? {
      defaultAction: 'Deny'
      bypass: 'None'
      // Conditionally add the desktop IP to ipRules
      ipRules: !empty(desktopIpAddress) ? [
        {
          action: 'Allow'
          value: desktopIpAddress // Use the value from the new parameter
        }
      ] : [] // If desktopIpAddress is not provided, ipRules will be an empty array
    } : {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      // ipRules are not typically needed here if defaultAction is Allow and publicNetworkAccess is Enabled
    }
    blobServices: {
      containers: [{name: deploymentStorageContainerName}] // Assuming 'deploymentStorageContainerName' is defined
    }
    minimumTlsVersion: 'TLS1_2'  // Enforcing TLS 1.2 for better security
  }
}


// Define the configuration object locally to pass to the modules
var storageEndpointConfig = {
  enableBlob: true  // Required for AzureWebJobsStorage, .zip deployment, Event Hubs trigger and Timer trigger checkpointing
  enableQueue: false  // Required for Durable Functions and MCP trigger
  enableTable: false  // Required for Durable Functions and OpenAI triggers and bindings
  enableFiles: false   // Not required, used in legacy scenarios
  allowUserIdentityPrincipal: true   // Allow interactive user identity to access for testing and debugging
}

// Consolidated Role Assignments
module rbac 'app/rbac.bicep' = {
  name: 'rbacAssignments'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    appInsightsName: monitoring.outputs.name
    managedIdentityPrincipalId: apiUserAssignedIdentity.outputs.principalId
    userIdentityPrincipalId: principalId
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
    allowUserIdentityPrincipal: storageEndpointConfig.allowUserIdentityPrincipal
  }
}

// Virtual Network & private endpoint to blob storage
module serviceVirtualNetwork 'app/vnet.bicep' =  if (vnetEnabled) {
  name: 'serviceVirtualNetwork'
  scope: rg
  params: {
    location: location
    tags: tags
    vNetName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
  }
}

module storagePrivateEndpoint 'app/storage-PrivateEndpoint.bicep' = if (vnetEnabled) {
  name: 'servicePrivateEndpoint'
  scope: rg
  params: {
    location: location
    tags: tags
    virtualNetworkName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetName: vnetEnabled ? serviceVirtualNetwork.outputs.peSubnetName : '' // Keep conditional check for safety, though module won't run if !vnetEnabled
    resourceName: storage.outputs.name
    enableBlob: storageEndpointConfig.enableBlob
    enableQueue: storageEndpointConfig.enableQueue
    enableTable: storageEndpointConfig.enableTable
  }
}

// SQL Server private endpoint
module sqlPrivateEndpoint 'app/sql-PrivateEndpoint.bicep' = if (vnetEnabled) {
  name: 'sqlPrivateEndpoint'
  scope: rg
  params: {
    location: location
    tags: tags
    virtualNetworkName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetName: vnetEnabled ? serviceVirtualNetwork.outputs.sqlSubnetName : ''
    sqlServerName: db.outputs.name
  }
}

// Monitor application with Azure Monitor - Log Analytics and Application Insights
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dataRetention: 30
  }
}
 
module monitoring 'br/public:avm/res/insights/component:0.6.0' = {
  name: '${uniqueString(deployment().name, location)}-appinsights'
  scope: rg
  params: {
    name: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
  }
}

// Creates Azure API Management (APIM) service to mediate the requests between the frontend and the backend API
module apim 'br/public:avm/res/api-management/service:0.2.0' = if (useAPIM) {
  name: 'apim-deployment'
  scope: rg
  params: {
    name: !empty(apimServiceName) ? apimServiceName : '${abbrs.apiManagementService}${resourceToken}'
    publisherEmail: 'noreply@microsoft.com'
    publisherName: 'n/a'
    location: location
    tags: tags
    sku: apimSku
    skuCount: 0
    zones: []
    customProperties: {}
    loggers: [
      {
        name: 'app-insights-logger'
        credentials: {
          instrumentationKey: monitoring.outputs.instrumentationKey
        }
        loggerDescription: 'Logger to Azure Application Insights'
        isBuffered: false
        loggerType: 'applicationInsights'
        targetResourceId: monitoring.outputs.resourceId
      }
    ]
  }
}


// Data outputs
output AZURE_SQL_CONNECTION_STRING_KEY string = 'Server=${db.outputs.fullyQualifiedDomainName}; Database=${db.outputs.databaseName}; Authentication=Active Directory Default; User Id=${apiUserAssignedIdentity.outputs.clientId}; TrustServerCertificate=True'
output AZURE_SQL_SERVER_NAME string = db.outputs.fullyQualifiedDomainName
output AZURE_SQL_SERVER_RESOURCE_NAME string = db.outputs.name
output AZURE_SQL_DATABASE_NAME string = db.outputs.databaseName
output USER_ASSIGNED_IDENTITY_CLIENT_ID string = apiUserAssignedIdentity.outputs.clientId
output USER_ASSIGNED_IDENTITY_PRINCIPAL_ID string = apiUserAssignedIdentity.outputs.principalId
output USER_ASSIGNED_IDENTITY_NAME string = apiUserAssignedIdentity.outputs.name

// App outputs
output AZURE_KEY_VAULT_ENDPOINT string = enableSQLScripts ? db.outputs.keyVaultUri : ''
output AZURE_KEY_VAULT_NAME string = enableSQLScripts ? db.outputs.keyVaultName : ''
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output USE_APIM bool = useAPIM
output RESOURCE_GROUP_NAME string = rg.name
