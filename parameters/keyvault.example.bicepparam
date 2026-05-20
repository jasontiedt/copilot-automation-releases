// ============================================================================
// Example parameter file for modules/keyvault.bicep
// Used by tests/deploy.validation.sh in the sandbox subscription.
// ============================================================================

using '../modules/keyvault.bicep'

param name = 'kv-shared-poc-001'
param location = 'eastus2'
param skuName = 'standard'

param tags = {
  environment: 'sandbox'
  owner: 'cloud-engineering'
  costCenter: 'adusa-platform'
  managedBy: 'avm-update-automation'
}

// Example: grant a workload identity Key Vault Secrets User access.
param roleAssignments = [
  // {
  //   roleDefinitionIdOrName: 'Key Vault Secrets User'
  //   principalId: '<object-id>'
  //   principalType: 'ServicePrincipal'
  // }
]

// Example: private endpoint into the platform spoke.
param privateEndpoints = [
  // {
  //   subnetResourceId: '<subnet-id>'
  //   privateDnsZoneGroup: {
  //     privateDnsZoneGroupConfigs: [
  //       { privateDnsZoneResourceId: '<private-dns-zone-id>' }
  //     ]
  //   }
  // }
]

// param logAnalyticsWorkspaceResourceId = '<law-id>'
