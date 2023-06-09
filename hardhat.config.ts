import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-deploy"
import "@nomiclabs/hardhat-ethers"

import * as dotenv from "dotenv";

dotenv.config();

import "./tasks"

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
const privateKey =
  process.env.PRIVATE_KEY_1;
const privateKey2 = process.env.PRIVATE_KEY_2;
const ertherScanApiKey = process.env.ETHER_SCAN_API_KEY as string;

const config: HardhatUserConfig = {
  solidity: "0.8.17",
  defaultNetwork: "anvil",
  networks: {
    hardhat: {
      chainId: 1337,
      forking: {
        url: "https://bsc-dataseed.binance.org",
        enabled: true

      },
      accounts: [{ privateKey: `${privateKey}`, balance: "100000000000000000000000" }, { privateKey: `${privateKey2}`, balance: "100000000000000000000000" }]
    },
    xdc: {
      url: "https://rpc.xdcrpc.com",
      chainId: 50,
      accounts: [`${privateKey}`, `${privateKey2}`],
    },
    anvil: {
      url: `${process.env.ANVIL_FORKING_RPC}`,
      chainId: parseInt(process.env.ANVIL_FORKING_CHAIN_ID as string),
      accounts: [`${process.env.ANVIL_FORKING_RPC_ACCOUNT}`],
    },
  },

  namedAccounts: {
    deployer: {
      default: 0
    },
    feeCollector: {}
  }
};

export default config;
