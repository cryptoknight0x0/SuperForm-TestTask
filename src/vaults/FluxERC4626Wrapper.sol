// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IFERC20} from "./utils/flux/IFERC20.sol";
// import {LibFlux} from "./utils/Flux/LibFlux.sol";
import {IComptroller} from "./utils/flux/IComptroller.sol";

import {DexSwap} from "./utils/swapUtils.sol";
import "forge-std/console.sol";

/// @title FluxERC4626Wrapper - Custom implementation of yield-daddy wrappers with flexible reinvesting logic
/// Rationale: Forked protocols often implement custom functions and modules on top of forked code.
/// Example: Staking systems. Very common in DeFi. Re-investing/Re-Staking rewards on the Vault level can be included in permissionless way.
contract FluxERC4626Wrapper is ERC4626 {

    // Libraries usage
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // Compact struct to make two swaps (PancakeSwap on BSC)
    // A => B (using pair1) then B => asset (of Wrapper) (using pair2)
    struct SwapInfo {
        address token;
        address pair1;
        address pair2;
    }

    // Constants

    uint256 internal constant NO_ERROR = 0;

    // Immutable params

    address public immutable manager; // Access Control for harvest() route
    ERC20 public immutable reward; // The FLUX-like token contract
    IFERC20 public immutable fToken; // The Flux fToken contract
    IComptroller public immutable comptroller; // The Flux comptroller contract

    // Storage variables

    SwapInfo public swapInfo; // Pointer to SwapInfo

    // Errors

    /// @param errorCode The error code returned by Flux
    error FluxERC4626__FluxError(uint256 errorCode); // Thrown when a call to Flux returned an error.
    error ZeroAddressError(); // Thrown when trying to set a variable to zero address.
    error CallerNotOwner(address caller); // Thrown when caller is not owner.

    // Constructor

    constructor(
        ERC20 asset_, // underlying
        ERC20 reward_, // comp token or other
        IFERC20 fToken_, // Flux concept of a share
        IComptroller comptroller_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        reward = reward_;
        fToken = fToken_;
        comptroller = comptroller_;
        if(manager_ == address(0)) {
            revert ZeroAddressError();
        }
        manager = manager_;
    }

    // Flux liquidity mining

    function setRoute(
        address token,
        address pair1,
        address pair2
    ) external {
        if(msg.sender != owner) {
            revert CallerNotOwner(msg.sender);
        }
        swapInfo = SwapInfo(token, pair1, pair2);
        ERC20(reward).approve(swapInfo.pair1, type(uint256).max); /// max approve
        ERC20(swapInfo.token).approve(swapInfo.pair2, type(uint256).max); /// max approve
    }

    /// @notice Claims liquidity mining rewards from Flux and performs low-lvl swap with instant reinvesting
    /// Calling harvest() claims COMP-Fork token through direct Pair swap for best control and lowest cost
    /// harvest() can be called by anybody. ideally this function should be adjusted per needs (e.g add fee for harvesting)
    function harvest() external {
        console.log("Harvest called");
        IFERC20[] memory fTokens = new IFERC20[](1);
        fTokens[0] = fToken;
        console.log("Before claim comp");
        comptroller.claimComp(address(this), fTokens);
        console.log("Before reward transfer");
        console.log("reward.balanceOf(address(this))",reward.balanceOf(address(this)));
        // reward.safeTransfer(address(this), reward.balanceOf(address(this)));

        uint256 earned = ERC20(reward).balanceOf(address(this));
        address rewardToken = address(reward);

        console.log("Before swap process start");

        /// If only one swap needed (high liquidity pair) - set SwapInfo.token0/token/pair2 to 0x
        if (swapInfo.token == address(asset)) {
            DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, // from REWARD (because of liquidity)
                address(asset), /// to target underlying of this Vault ie USDC
                swapInfo.pair1 /// pairToken (pool)
            );
            /// If two swaps needed
        } else {
            uint256 swapTokenAmount = DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, /// fromToken REWARD
                swapInfo.token, /// to intermediary token with high liquidity (no direct pools)
                swapInfo.pair1 /// pairToken (pool)
            );

            DexSwap.swap(
                swapTokenAmount,
                swapInfo.token, // from received BUSD (because of liquidity)
                address(asset), /// to target underlying of this Vault ie USDC
                swapInfo.pair2 /// pairToken (pool)
            );
        }
        console.log("Before after withdraw");

        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// ERC4626 overrides

    function totalAssets() public view virtual override returns (uint256) {
        return
            fToken.balanceOf(address(this)).mulWadDown(
                fToken.exchangeRateStored()
            );
    }

    function beforeWithdraw(
        uint256 assets,
        uint256 /*positions*/
    ) internal virtual override {
        // Withdraw assets from Flux
        uint256 errorCode = fToken.redeemUnderlying(assets);
        if (errorCode != NO_ERROR) {
            revert FluxERC4626__FluxError(errorCode);
        }
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        // Deposit assets into Flux
        // approve to fToken
        asset.safeApprove(address(fToken), assets);

        // deposit into fToken
        uint256 errorCode = fToken.mint(assets);
        if (errorCode != NO_ERROR) {
            revert FluxERC4626__FluxError(errorCode);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(fToken)) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(fToken)) return 0;
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = fToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = fToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    // ERC20 metadata generation

    function _vaultName(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultName)
    {
        vaultName = string.concat("FluxERC4626- ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("fS-", asset_.symbol());
    }
}
