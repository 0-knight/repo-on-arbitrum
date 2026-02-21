// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockPriceFeed — Admin-controlled price oracle for hackathon demo
/// @notice Prices are stored as USD value per 1 token unit, scaled to token decimals.
///         e.g. USYC at $1.00 with 6 decimals → price = 1e6
///         USYC at $0.96 with 6 decimals → price = 960000
contract MockPriceFeed {
    mapping(address => uint256) public prices;
    address public admin;

    error OnlyAdmin();
    error PriceNotSet(address token);

    constructor() {
        admin = msg.sender;
    }

    /// @notice Set price for a token (admin only)
    /// @param token Token address
    /// @param price Price per 1 full token unit in USD, scaled to token decimals
    function setPrice(address token, uint256 price) external {
        if (msg.sender != admin) revert OnlyAdmin();
        prices[token] = price;
    }

    /// @notice Get price for a token
    function getPrice(address token) external view returns (uint256) {
        uint256 p = prices[token];
        if (p == 0) revert PriceNotSet(token);
        return p;
    }

    /// @notice Calculate USD value of a token amount
    /// @param token Token address
    /// @param amount Token amount (in token decimals)
    /// @return value USD value (in token decimals, i.e. same scale as amount)
    function getValue(address token, uint256 amount) external view returns (uint256 value) {
        uint256 p = prices[token];
        if (p == 0) revert PriceNotSet(token);
        // value = amount * price / 1e_decimals
        // Since price is already scaled to decimals (e.g. 1e6 for $1 at 6 dec),
        // and amount is also in decimals: value = amount * price / 1e6
        value = (amount * p) / 1e6;
    }
}
