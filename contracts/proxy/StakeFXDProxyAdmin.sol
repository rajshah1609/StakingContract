// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.17;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract StakeFXDProxyAdmin is ProxyAdmin {
    constructor() ProxyAdmin(){
    }
}
