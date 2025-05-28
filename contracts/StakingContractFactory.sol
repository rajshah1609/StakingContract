// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./TokenStaking.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingContractFactory is Ownable {
    mapping(address => address[]) private pools;
    
    event PoolDeployed(
        address indexed token,
        address indexed pool,
        uint256 interest,
        uint256 decimals,
        uint256 index
    );

    function deploy(
        IERC20 token,
        uint256 interest,
        uint256 decimals,
        string calldata name
    ) external onlyOwner returns (address pool) {
        pool = address(new TokenStaking(token, interest, decimals, name));
        pools[address(token)].push(pool);
        
        TokenStaking(pool).transferOwnership(owner());

        emit PoolDeployed(
            address(token),
            pool,
            interest,
            decimals,
            pools[address(token)].length
        );
    }

    function getPools(address token) external view returns (address[] memory) {
        return pools[token];
    }
} 