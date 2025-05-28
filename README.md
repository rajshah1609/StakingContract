# Staking Contract System

This repository contains a staking contract system for CGO, FXD, and XDC tokens on the XDC Apothem testnet (chain ID 51). The system includes a factory contract for deploying staking pools and individual pool contracts for each token.

## Prerequisites

- Node.js (v14+ recommended)
- npm or yarn
- An XDC wallet with testnet XDC for deployment
- Access to Apothem testnet RPC

## Installation

1. Clone the repository and install dependencies:
```bash
git clone <repository-url>
cd StakingContract
npm install
```

2. Set up environment variables:
```bash
cp .env.example .env
```

Edit `.env` file with your configuration:
```env
PRIVATE_KEY=your_private_key
APOTHEM_URL=https://erpc.apothem.network
```

## Build and Compile

1. Clean previous builds:
```bash
# Remove all compiled artifacts and cache
rm -rf artifacts cache typechain-types

# Clean hardhat cache
npx hardhat clean
```

2. Compile contracts:
```bash
npx hardhat compile
```

## Deployment

The deployment process is split into multiple scripts to handle each token separately. Make sure to deploy them in the correct order.

### 1. Deploy Factory Contract

```bash
# Deploy only the factory contract
npx hardhat deploy --tags factory
```

### 2. Deploy CGO Pools

```bash
# Deploy CGO staking pools
npx hardhat deploy --tags cgo-pools --network apothem
```

This will deploy:
- CGO Staking Pool B (15% APY)
  - Min stake: 1,000 CGO
  - Max stake: 500,000 CGO
  - Cooloff: 2 days
  - Reward interval: 12 hours

### 3. Deploy FXD Pools

```bash
# Deploy FXD staking pools
npx hardhat deploy --tags fxd-pools --network apothem
```

This will deploy:
- FXD Growth Pool (12% APY)
  - Min stake: 5,000 FXD
  - Max stake: 500,000 FXD
  - Cooloff: 2 days
  - Reward interval: 12 hours

### 4. Deploy XDC Pools

```bash
# Deploy XDC staking pools
npx hardhat deploy --tags xdc-pools --network apothem
```

This will deploy:
- XDC Premium Pool (7% APY)
  - Min stake: 10,000 XDC
  - Max stake: 1,000,000 XDC
  - Cooloff: 3 days
  - Reward interval: 12 hours

## Testing

### Run All Tests

```bash
# Run all tests
npx hardhat test
```

### Run Integration Tests

```bash
# Run integration tests for pool deployment
npx hardhat test test/integration/deploy-all-pools.test.ts --network hardhat
```

## Contract Verification

After deployment, verify the contracts on XDC Apothem Explorer:

```bash
# Verify factory contract
npx hardhat verify --network apothem <FACTORY_ADDRESS>

# Verify pool contracts
npx hardhat verify --network apothem <POOL_ADDRESS> <CONSTRUCTOR_ARGS>
```

## Token Addresses (Apothem Testnet)

The following token addresses are configured in `configs/apothem.json`:

```json
{
    "FXD": "0xDf29cB40Cb92a1b8E8337F542E3846E185DefF96",
    "XDC": "0xE99500AB4A413164DA49Af83B9824749059b46ce",
    "CGO": "0x97EC6730Fd5F138fCB167cb62A9a4c1A8Be2eD7d"
}
```

## Contract Interaction

You can interact with the deployed contracts using:

1. Hardhat console:
```bash
npx hardhat console --network apothem
```

2. Using the provided interface in Remix IDE (copy `ITokenStaking.sol`)

## Troubleshooting

### Common Issues

1. **Nonce too high error**:
```bash
# Clear pending transactions
npx hardhat deploy --reset --network apothem
```

2. **Gas price errors**:
```bash
# Try with higher gas price
APOTHEM_GAS_PRICE=20000000000 npx hardhat deploy --network apothem
```

3. **Compilation errors**:
```bash
# Clean and recompile
npx hardhat clean
rm -rf artifacts cache typechain-types
npx hardhat compile
```

### Deployment Verification

After deploying each pool, verify:
1. Pool is registered in factory
2. Pool parameters are set correctly
3. Pool can accept stakes
4. Rewards are calculated correctly

## Security Considerations

1. All contracts use OpenZeppelin's secure implementations
2. Reentrancy protection is implemented
3. Owner functions are properly protected
4. Stake amounts are validated
5. Cooloff periods are enforced

## License

MIT

## Support

For support, please open an issue in the repository or contact the development team. 