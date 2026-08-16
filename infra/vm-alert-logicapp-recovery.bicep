@description('Azure region for the alerting and recovery resources.')
param location string = resourceGroup().location

@description('The Azure resource ID of the monitored VM.')
param vmResourceId string

@description('Name of the Logic App workflow.')
param logicAppName string = 'logic-vm-nginx-recover-${uniqueString(resourceGroup().id)}'

@description('Name of the action group that sends the alert to the Logic App.')
param actionGroupName string = 'ag-vm-nginx-${uniqueString(resourceGroup().id)}'

@description('The callback URL used by Azure Monitor to invoke the Logic App workflow. Leave blank to populate after deployment.')
param logicAppTriggerUrl string = ''

@description('Optional URL for the Microsoft Foundry Hosted Agent fallback.')
param foundryAgentUrl string = ''

@description('Optional token or API key for the Microsoft Foundry Hosted Agent fallback.')
@secure()
param foundryApiKey string = ''

@description('Monitored URL used by the recovery flow for diagnostics context.')
param monitoredUrl string = 'http://localhost/health'

resource monitoredVm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: last(split(vmResourceId, '/'))
}

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: json(loadTextContent('logic-app-vm-recovery/workflow.json'))
    parameters: {
      vmResourceId: {
        value: vmResourceId
      }
      monitoredUrl: {
        value: monitoredUrl
      }
      foundryAgentUrl: {
        value: foundryAgentUrl
      }
      foundryApiKey: {
        value: foundryApiKey
      }
    }
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: 'nginx404'
    enabled: true
    webhookReceivers: empty(logicAppTriggerUrl) ? [
      {
        name: 'logic-app-recovery'
        serviceUri: listCallbackUrl(resourceId('Microsoft.Logic/workflows', logicApp.name), '2019-05-01').value
        useCommonAlertSchema: true
      }
    ] : [
      {
        name: 'logic-app-recovery'
        serviceUri: logicAppTriggerUrl
        useCommonAlertSchema: true
      }
    ]
  }
}

resource logicAppVmRunCommandRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicApp.id, 'vm-run-command')
  scope: monitoredVm
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output actionGroupResourceId string = actionGroup.id
output logicAppResourceId string = logicApp.id
output alertResourceId string = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Insights/actionGroups/${actionGroupName}'
output monitorUrl string = monitoredUrl
