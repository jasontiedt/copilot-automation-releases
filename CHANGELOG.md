# Changelog

All notable changes to the Key Vault shared module are documented here.
Versions track the pinned AVM `key-vault/vault` module version.

## 0.13.3

- Bumped wrapped AVM module from `0.10.0` to `0.13.3`.
- Removed deprecated wrapper parameters `vaultSku`, `enableSoftDelete`, and
  `accessPolicies` now that their planned one-bump compatibility window has
  passed.
- Outputs unchanged: `resourceId`, `name`, `uri`, `resourceGroupName`.

## 0.11.0 — Initial wrapper

- Initial wrapper around `br/public:avm/res/key-vault/vault:0.11.0`.
- SCF-aligned defaults: RBAC-only auth, purge protection, soft-delete 90 days,
  `publicNetworkAccess: Disabled`, `networkAcls.defaultAction: Deny`.
- Outputs: `resourceId`, `name`, `uri`, `resourceGroupName`.
