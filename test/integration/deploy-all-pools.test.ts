import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { Contract } from "ethers";
import apothemConfig from "../../configs/apothem.json";

describe("Staking Pools Deployment Integration Test", function () {
    // Increase timeout for all tests in this file since we're deploying multiple contracts
    this.timeout(300000); // 5 minutes

    let factory: Contract;
    let deployer: string;
    let deployerSigner: any;

    // Pool Configuration Interface
    interface StakingPoolConfig {
        tokenAddress: string;
        name: string;
        minStakeAmount: number;
        maxStakeAmount: number;
        coolOff: number;
        redeemInterval: number;
        maxPoolAmount: number;
        interestPrecision: number;
        interest: number;
        decimals: number;
    }

    // Combined pool configurations from all deployment scripts
    const ALL_POOLS: StakingPoolConfig[] = [
        // CGO Pool
        {
            tokenAddress: apothemConfig.CGO,
            name: "CGO Staking Pool B",
            minStakeAmount: 1000,
            maxStakeAmount: 500000,
            coolOff: 172800, // 2 days in seconds
            redeemInterval: 43200, // 12 hours in seconds
            maxPoolAmount: 2000000,
            interestPrecision: 1000000,
            interest: 15, // 15% APY
            decimals: 18,
        },
        // FXD Pool
        {
            tokenAddress: apothemConfig.FXD,
            name: "FXD Growth Pool",
            minStakeAmount: 5000,
            maxStakeAmount: 500000,
            coolOff: 172800, // 2 days in seconds
            redeemInterval: 43200, // 12 hours in seconds
            maxPoolAmount: 2000000,
            interestPrecision: 1000000,
            interest: 12, // 12% APY
            decimals: 18,
        },
        // XDC Pool
        {
            tokenAddress: apothemConfig.XDC,
            name: "XDC Premium Pool",
            minStakeAmount: 10000,
            maxStakeAmount: 1000000,
            coolOff: 259200, // 3 days in seconds
            redeemInterval: 43200, // 12 hours in seconds
            maxPoolAmount: 5000000,
            interestPrecision: 1000000,
            interest: 7, // 7% APY
            decimals: 18,
        }
    ];

    const deployPool = async (
        poolConfig: StakingPoolConfig,
        nonce: number
    ): Promise<{ nonce: number; pool: Contract }> => {
        console.log(`\nDeploying pool: ${poolConfig.name}`);
        
        // Deploy pool through factory
        const createPoolTx = await factory.deploy(
            poolConfig.tokenAddress,
            poolConfig.interest,
            poolConfig.decimals,
            poolConfig.name,
            {
                nonce: nonce,
                gasPrice: (await ethers.provider.getGasPrice()).mul(2)
            }
        );
        const receipt = await createPoolTx.wait();
        nonce++;

        // Get pool address from event logs
        const poolDeployedEvent = receipt.events?.find((e: any) => e.event === "PoolDeployed");
        if (!poolDeployedEvent) {
            throw new Error("Pool deployment failed - PoolDeployed event not found");
        }
        const poolAddress = poolDeployedEvent.args?.pool;

        // Get pool contract instance
        const pool = await ethers.getContractAt("TokenStaking", poolAddress);

        // Initialize the pool
        const initTx = await pool.initialize(
            poolConfig.minStakeAmount,
            poolConfig.maxStakeAmount,
            poolConfig.coolOff,
            poolConfig.redeemInterval,
            poolConfig.maxPoolAmount,
            poolConfig.interestPrecision,
            {
                nonce: nonce,
                gasPrice: (await ethers.provider.getGasPrice()).mul(2)
            }
        );
        await initTx.wait();
        nonce++;

        return { nonce, pool };
    };

    before(async () => {
        // Get accounts
        const accounts = await getNamedAccounts();
        deployer = accounts.deployer;
        deployerSigner = await ethers.getSigner(deployer);

        // Deploy factory first
        await deployments.fixture(["factory"]);
        const factoryDeployment = await deployments.get("StakingContractFactory");
        factory = await ethers.getContractAt("StakingContractFactory", factoryDeployment.address);
    });

    it("should deploy and initialize all staking pools", async () => {
        // Send clearing transaction
        let nonce = await deployerSigner.getTransactionCount("pending");
        const clearingTx = await deployerSigner.sendTransaction({
            to: deployer,
            value: 0,
            nonce: nonce,
            gasPrice: (await ethers.provider.getGasPrice()).mul(2)
        });
        await clearingTx.wait();
        nonce = await deployerSigner.getTransactionCount("pending");

        // Deploy and verify each pool
        const deployedPools: Contract[] = [];
        for (const poolConfig of ALL_POOLS) {
            const { nonce: newNonce, pool } = await deployPool(poolConfig, nonce);
            nonce = newNonce;
            deployedPools.push(pool);

            // Verify pool configuration
            const minStake = await pool.minStakeAmount();
            const maxStake = await pool.maxStakeAmount();
            const coolOff = await pool.coolOff();
            const redeemInterval = await pool.redeemInterval();
            const maxPoolAmount = await pool.maxPoolAmount();
            const interest = await pool.interest();
            const token = await pool.stakingToken();
            const name = await pool.poolName();

            // Assert pool configuration
            expect(minStake).to.equal(poolConfig.minStakeAmount);
            expect(maxStake).to.equal(poolConfig.maxStakeAmount);
            expect(coolOff).to.equal(poolConfig.coolOff);
            expect(redeemInterval).to.equal(poolConfig.redeemInterval);
            expect(maxPoolAmount).to.equal(poolConfig.maxPoolAmount);
            expect(interest).to.equal(poolConfig.interest);
            expect(token.toLowerCase()).to.equal(poolConfig.tokenAddress.toLowerCase());
            expect(name).to.equal(poolConfig.name);

            console.log(`✓ Verified ${poolConfig.name} at ${pool.address}`);
        }

        // Verify total number of pools deployed
        const factoryPoolCount = await factory.getPoolCount();
        expect(factoryPoolCount).to.equal(ALL_POOLS.length);

        // Verify each pool is registered in factory
        for (let i = 0; i < deployedPools.length; i++) {
            const poolAddress = await factory.getPool(i);
            expect(poolAddress).to.equal(deployedPools[i].address);
        }
    });
}); 