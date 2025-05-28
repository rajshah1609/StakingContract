import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    try {
        const { getNamedAccounts, deployments, ethers } = hre;
        const { deploy } = deployments;
        const { deployer } = await getNamedAccounts();

        // Log deployer info
        console.log("Deploying contracts with account:", deployer);
        const balance = await ethers.provider.getBalance(deployer);
        console.log("Account balance:", ethers.utils.formatEther(balance));

        // Get signer and nonce
        const signer = await ethers.getSigner(deployer);
        let nonce = await signer.getTransactionCount("pending");
        console.log("Starting nonce:", nonce);

        // Send a zero value transaction to clear any pending transactions
        console.log("Sending clearing transaction...");
        const clearingTx = await signer.sendTransaction({
            to: deployer,
            value: 0,
            nonce: nonce,
            gasPrice: (await ethers.provider.getGasPrice()).mul(2) // 2x current gas price
        });
        console.log("Clearing transaction hash:", clearingTx.hash);
        await clearingTx.wait();

        // Get new nonce
        nonce = await signer.getTransactionCount("pending");
        console.log("New nonce after clearing:", nonce);

        // Deploy factory with explicit nonce
        console.log("Deploying StakingContractFactory...");
        const factoryDeployment = await deploy("StakingContractFactory", {
            from: deployer,
            args: [],
            log: true,
            waitConfirmations: 1,
            nonce: nonce,
            gasPrice: (await ethers.provider.getGasPrice()).mul(2) // 2x current gas price
        });

        console.log("StakingContractFactory deployed to:", factoryDeployment.address);

    } catch (error) {
        console.error("Deployment failed with error:", error);
        throw error;
    }
};

func.tags = ["factory"];
export default func; 