// ============================================================================
// Key Vault Shared Module — AVM Wrapper
// ----------------------------------------------------------------------------
// Wraps `br/public:avm/res/key-vault/vault` and applies organization defaults
// (RBAC-only auth, soft-delete, purge protection, diagnostic settings).
//
// AVM version pinned via `avm.version` at repo root. The avm-update-automation
// workflow keeps the version below in sync with the file.
// ============================================================================

metadata name = 'KeyVault Shared Module (AVM Wrapper)'
metadata description = 'Organization-standard wrapper around the AVM Key Vault module.'
metadata owner = 'ADUSA Cloud Engineering'

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Required parameters
// ---------------------------------------------------------------------------

@description('Required. Name of the Key Vault. 3-24 chars, alphanumeric and dashes.')
@minLength(3)
@maxLength(24)
param name string

@description('Required. Azure region for the Key Vault.')
param location string

// ---------------------------------------------------------------------------
// Organization-standard defaults (overridable but locked-down)
// ---------------------------------------------------------------------------

@description('Optional. SKU. Defaults to standard. Use premium only for HSM-backed keys.')
@allowed([ 'standard', 'premium' ])
param skuName string = 'standard'

@description('Optional. Enable RBAC authorization (org standard). Access policies are disallowed.')
param enableRbacAuthorization bool = true

@description('Optional. Soft-delete retention in days. Org minimum is 90.')
@minValue(90)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Optional. Purge protection. Required by org policy — must remain true.')
param enablePurgeProtection bool = true

@description('Optional. Allow Azure services (Deploy, Disk Encryption, ARM) to bypass network rules.')
param networkAclsBypass string = 'AzureServices'

@description('Optional. Default network action. Org standard is Deny.')
@allowed([ 'Allow', 'Deny' ])
param networkAclsDefaultAction string = 'Deny'

@description('Optional. Public network access. Org standard is Disabled.')
@allowed([ 'Enabled', 'Disabled' ])
param publicNetworkAccess string = 'Disabled'

// ---------------------------------------------------------------------------
// Optional pass-through parameters
// ---------------------------------------------------------------------------

@description('Optional. RBAC role assignments scoped to this vault.')
param roleAssignments array = []

@description('Optional. Private endpoints to create.')
param privateEndpoints array = []

@description('Optional. Diagnostic settings. Defaults to allLogs + AllMetrics if a Log Analytics workspace is provided.')
param diagnosticSettings array = []

@description('Optional. Resource tags.')
param tags object = {}

@description('Optional. Log Analytics workspace resource ID. When provided, a default diagnostic setting is created.')
param logAnalyticsWorkspaceResourceId string = ''

// ---------------------------------------------------------------------------
// Computed: default diagnostic setting when a workspace is supplied and the
// caller did not pass an explicit diagnosticSettings array.
// ---------------------------------------------------------------------------

var defaultDiagnostics = empty(logAnalyticsWorkspaceResourceId) ? [] : [
  {
    name: 'default'
    workspaceResourceId: logAnalyticsWorkspaceResourceId
    logCategoriesAndGroups: [ { categoryGroup: 'allLogs' } ]
    metricCategories: [ { category: 'AllMetrics' } ]
  }
]

var effectiveDiagnostics = empty(diagnosticSettings) ? defaultDiagnostics : diagnosticSettings

// ---------------------------------------------------------------------------
// AVM module call
// ---------------------------------------------------------------------------

module vault 'br/public:avm/res/key-vault/vault:0.11.0' = {
  name: 'kv-${uniqueString(resourceGroup().id, name)}'
  params: {
    name: name
    location: location
    sku: skuName
    enableRbacAuthorization: enableRbacAuthorization
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: networkAclsBypass
      defaultAction: networkAclsDefaultAction
    }
    roleAssignments: roleAssignments
    privateEndpoints: privateEndpoints
    diagnosticSettings: effectiveDiagnostics
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Key Vault.')
output resourceId string = vault.outputs.resourceId

@description('Name of the Key Vault.')
output name string = vault.outputs.name

@description('URI of the Key Vault.')
output uri string = vault.outputs.uri

@description('Resource group name.')
output resourceGroupName string = vault.outputs.resourceGroupName
