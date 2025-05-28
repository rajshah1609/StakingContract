import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Contract } from "ethers";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import apothemConfig from "../configs/apothem.json";

// Load environment variables from .env file
dotenvConfig({ path: resolve(__dirname, "../.env") });

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

// XDC Pool Configurations
const XDC_POOLS: StakingPoolConfig[] = [
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
    factory: Contract,
    signer: any,
    nonce: number,
    ethers: any
): Promise<{ nonce: number; poolAddress: string }> => {
    console.log(`\nDeploying pool: ${poolConfig.name}`);
    console.log("Configuration:", JSON.stringify(poolConfig, null, 2));

    // Create pool through factory
    console.log("Creating pool through factory...");
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
    console.log("Create pool transaction hash:", createPoolTx.hash);
    const receipt = await createPoolTx.wait();
    nonce++;

    // Get pool address from event logs
    const poolDeployedEvent = receipt.events?.find((e: { event: string }) => e.event === "PoolDeployed");
    if (!poolDeployedEvent) {
        throw new Error("Pool deployment failed - PoolDeployed event not found");
    }
    const poolAddress = poolDeployedEvent.args?.pool;
    console.log("Pool deployed to:", poolAddress);

    // Get pool contract instance
    const stakingPool = await ethers.getContractAt("TokenStaking", poolAddress);

    // Initialize the pool
    console.log("Initializing staking pool...");
    const initTx = await stakingPool.initialize(
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
    console.log("Initialize transaction hash:", initTx.hash);
    await initTx.wait();
    nonce++;

    // Verify deployment
    const minStake = await stakingPool.minStakeAmount();
    if (minStake.toString() === "0") {
        throw new Error("Pool initialization verification failed - minStakeAmount is 0");
    }

    console.log(`Pool ${poolConfig.name} created successfully at ${poolAddress}`);
    return { nonce, poolAddress };
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    try {
        const { getNamedAccounts, deployments, ethers } = hre;
        const { get } = deployments;
        const { deployer } = await getNamedAccounts();

        // Log deployment info
        console.log("Deployer account:", deployer);
        const balance = await ethers.provider.getBalance(deployer);
        console.log("Account balance:", ethers.utils.formatEther(balance));

        // Get factory contract
        let factory: Contract;
        try {
            const factoryDeployment = await get("StakingContractFactory");
            console.log("Found factory at:", factoryDeployment.address);
            factory = await ethers.getContractAt("StakingContractFactory", factoryDeployment.address);
        } catch {
            throw new Error("StakingContractFactory not found. Please deploy factory first using 00_deploy_staking_factory.ts");
        }

        // Get signer and nonce
        const signer = await ethers.getSigner(deployer);
        let nonce = await signer.getTransactionCount("pending");
        console.log("Starting nonce:", nonce);

        // Send clearing transaction
        console.log("Sending clearing transaction...");
        const clearingTx = await signer.sendTransaction({
            to: deployer,
            value: 0,
            nonce: nonce,
            gasPrice: (await ethers.provider.getGasPrice()).mul(2)
        });
        console.log("Clearing transaction hash:", clearingTx.hash);
        await clearingTx.wait();
        nonce = await signer.getTransactionCount("pending");

        // Deploy each pool configuration
        const deployedPools: { name: string; address: string }[] = [];
        for (const poolConfig of XDC_POOLS) {
            const { nonce: newNonce, poolAddress } = await deployPool(
                poolConfig,
                factory,
                signer,
                nonce,
                ethers
            );
            nonce = newNonce;
            deployedPools.push({ name: poolConfig.name, address: poolAddress });
        }

        // Log summary of all deployed pools
        console.log("\nDeployment Summary:");
        console.log("==================");
        for (const pool of deployedPools) {
            console.log(`${pool.name}: ${pool.address}`);
        }

    } catch (error) {
        console.error("Deployment failed with error:", error);
        throw error;
    }
};

func.tags = ["xdc-pools"];
func.dependencies = ["factory"]; // Requires factory to be deployed first

export default func; 