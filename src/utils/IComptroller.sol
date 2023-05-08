// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {IFERC20} from "./IFERC20.sol";

interface IComptroller {
    function getCompAddress() external view returns (address);

    function getAllMarkets() external view returns (IFERC20[] memory);

    function allMarkets(uint256 index) external view returns (IFERC20);

    function claimComp(address holder, IFERC20[] memory fTokens) external;

    function mintGuardianPaused(IFERC20 fToken) external view returns (bool);
}
