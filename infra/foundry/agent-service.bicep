@description('Location for the Foundry-related resources.')
param location string = resourceGroup().location

@description('Name of the Azure AI Services account.')
param aiServiceName string = 'agenticopsai'

@description('Project name used by the Foundry agent workspace.')
param projectName string = 'agenticops-foundry-project'

@description('Model deployment name used by the hosted agent.')
param modelDeploymentName string = 'gpt-4o-mini'

resource aiService 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiServiceName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: toLower(aiServiceName)
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource project 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    friendlyName: 'AgenticOps Foundry Project'
    storageAccount: resourceId('Microsoft.Storage/storageAccounts', 'st${uniqueString(resourceGroup().id)}')
    keyVault: resourceId('Microsoft.KeyVault/vaults', 'kv${uniqueString(resourceGroup().id)}')
    applicationInsights: resourceId('Microsoft.Insights/components', 'appi${uniqueString(resourceGroup().id)}')
  }
}

output aiServiceName string = aiService.name
output projectName string = project.name
output modelDeploymentName string = modelDeploymentName
