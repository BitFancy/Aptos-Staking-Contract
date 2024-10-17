# Defiralia Staking

The current repository contains the first basic version of Defiralia (Staking) contracts.
The main purpose of contracts is to allow the staking of LP coins and earn community/3rd party project reward coins.

## Docs

Official whitepaper documentation will be published soon on [Defiralia - Whitepaper](https://defiralia.com/whitepaper).

### Build

[Aptos CLI](https://github.com/aptos-labs/aptos-core/releases) required.

Core:

    aptos move compile --skip-fetch-latest-git-deps

### Test

Core:

    aptos move test --skip-fetch-latest-git-deps

**Defiralia Staking Tests**

Placed in [staking/](staking) module.

    cd staking
    aptos move test --skip-fetch-latest-git-deps