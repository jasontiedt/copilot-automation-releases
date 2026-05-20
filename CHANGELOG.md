# Changelog

All notable changes to the Key Vault shared module are documented here.
Versions track the pinned AVM `key-vault/vault` module version.

## 0.11.0 — Initial wrapper

- Initial wrapper around `br/public:avm/res/key-vault/vault:0.11.0`.
- SCF-aligned defaults: RBAC-only auth, purge protection, soft-delete 90 days,
  `publicNetworkAccess: Disabled`, `networkAcls.defaultAction: Deny`.
- Outputs: `resourceId`, `name`, `uri`, `resourceGroupName`.
