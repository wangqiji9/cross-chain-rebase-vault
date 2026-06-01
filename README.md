# Cross-Chain Rebase Vault

**Stack:** Solidity 0.8.24 · Foundry · Chainlink CCIP · OpenZeppelin

A cross-chain rebase token built with Chainlink CCIP. Users deposit ETH on Sepolia to receive yield-bearing RBT tokens, and can bridge them to Arbitrum Sepolia while preserving their personal interest rate.

Token balances grow automatically over time. Interest accrues per second at a rate locked in at deposit — since the global rate can only decrease, earlier depositors always earn more. Tokens are minted lazily: `balanceOf()` reflects accrued interest in real time, but the actual mint only happens on interaction.

When bridging cross-chain, the user's interest rate is encoded into the CCIP message payload and restored on the destination chain.

The Vault accepts ETH deposits and mints RBT 1:1. On redemption, RBT is burned and ETH is returned — funded by deposits and external yield injected via `receive()`. The Vault does not generate yield itself; accrued interest creates a liability that must be covered externally.

## Deployed Contracts

### Sepolia

| Contract | Address |
|----------|---------|
| RebaseToken | `0xCAF1AF19c231A0Ccfa9C1e7f5dB426623696A2A3` |
| RebaseTokenPool | `0x8eEACc4c833bB9812EBfd440869B8d47f5D0f716` |
| Vault | `0x8eB039856fE13b266d7C8fb3780f510e85340E19` |

### Arbitrum Sepolia

| Contract | Address |
|----------|---------|
| RebaseToken | `0x1c3018d36BCF96E3156dDF8d57b4B37Fb9a06171` |
| RebaseTokenPool | `0xB98A473f3497B4DAd4F88C1C80a3ee88A2975baD` |

## Build & Test

```shell
forge build
forge test
```
