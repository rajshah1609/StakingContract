import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import getConfigData from "../utils/read-networks-configs";
import { parseEther } from "ethers/lib/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {

    const { getNamedAccounts, deployments, } = hre; //hardhat config (run)

    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();
    const avnilForkingChainName = process.env.ANVIL_FORKING_CHAIN_NAME as string

    const configs = await getConfigData(hre.network.name === 'anvil' ? avnilForkingChainName : hre.network.name)
    if (!configs) throw new Error("Please provide a correct config file!");

    await deploy("StakeFXD", {
        from: deployer,
        log: true,
        args:[configs["FXD"], "1"]
    });

};

func.tags = ["staking"] // specefic for deploy sth ...
export default func;
