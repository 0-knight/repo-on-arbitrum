// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title MockUSYC — Test yield-bearing collateral token
/// @notice Represents a tokenized short-term treasury (like Hashnote USYC).
///         Yield is distributed separately via MockYieldDistributor, not via rebase.
contract MockUSYC is ERC20 {
    constructor() ERC20("Mock USYC", "USYC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
