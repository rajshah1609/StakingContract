import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { getConfigData } from "../utils";
import { ethers, network } from "hardhat";
import * as fs from "fs";
import { AkkaRouter } from "../typechain";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {};

func.tags = ["staking"] // specefic for deploy sth ...
export default func;
