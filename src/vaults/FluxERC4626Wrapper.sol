// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IFERC20, ERC20} from "./utils/flux/IFERC20.sol";
import {IComptroller} from "./utils/flux/IComptroller.sol";

/// @title FluxERC4626Wrapper - Custom implementation of yield-daddy wrappers with flexible reinvesting logic
/// Rationale: Forked protocols often implement custom functions and modules on top of forked code.
/// Example: Staking systems. Very common in DeFi. Re-investing/Re-Staking rewards on the Vault level can be included in permissionless way.
contract FluxERC4626Wrapper is ERC4626 {

    // Libraries usage
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // Constants

    uint256 internal constant NO_ERROR = 0;

    // Immutable params

    IFERC20 public immutable fToken; // The Flux fToken contract
    IComptroller public immutable comptroller; // The Flux comptroller contract

    // Errors

    /// @param errorCode The error code returned by Flux
    error FluxERC4626__FluxError(uint256 errorCode); // Thrown when a call to Flux returned an error.

    /**
    * @dev Constructor function for the vault contract.
    * @param asset_ Address of the underlying asset of the vault.
    * @param fToken_ Address of the IFERC20 implementation for the Flux concept of a share.
    * @param comptroller_ Address of the Comptroller contract.
    * @notice This function initializes the vault with the given parameters and sets the fToken and comptroller variables.
    */
    constructor(
        ERC20 asset_, // underlying
        IFERC20 fToken_, // Flux concept of a share
        IComptroller comptroller_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        fToken = fToken_;
        comptroller = comptroller_;
    }

    /// ERC4626 overrides

    /**
    * @dev Returns the total assets held by this contract, in terms of the underlying asset.
    * Total assets are calculated as the product of the balance of this contract in the underlying asset, and the current exchange rate of the fToken.
    * @return The total assets held by this contract, in terms of the underlying asset.
    */
    function totalAssets() public view virtual override returns (uint256) {
        return
            fToken.balanceOf(address(this)).mulWadDown(
                fToken.exchangeRateStored()
            );
    }

    /**
    * @dev This function is called before withdrawing assets from Flux, which is an external contract.
    * @param assets The amount of assets to be withdrawn.
    * @notice This function is an internal, virtual function and is only intended to be called within the contract itself or from a contract that inherits from this contract.
    * @notice This function uses the fToken contract's redeemUnderlying() function to withdraw the specified amount of assets from Flux.
    * @notice If the redeemUnderlying() function returns an error code other than NO_ERROR, the function will revert and throw a FluxERC4626__FluxError with the corresponding error code.
    */
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

    /**
    * @dev Internal function that deposits assets into Flux and mints fTokens.
    * @param assets The amount of assets to be deposited.
    */
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

    /**
    * @dev Returns the maximum deposit allowed for the given fToken contract address.
    * @return The maximum deposit amount allowed as an unsigned integer of type uint256.
    */
    function maxDeposit(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(fToken)) return 0;
        return type(uint256).max;
    }

    /**
    * @dev Returns the maximum possible tokens that can be minted.
    * @dev Returns a `uint256` value representing the maximum mint value of the `uint256` type.
    * If minting of the `fToken` is paused by the guardian, the function returns `0`.
    */
    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(fToken)) return 0;
        return type(uint256).max;
    }

    /**
    * @dev Calculates the maximum amount of underlying assets that can be withdrawn by the specified owner from this contract,
    * taking into account the current cash balance and the owner's balance of fTokens.
    * @param owner The address of the owner whose maximum withdrawal amount needs to be calculated.
    * @dev Returns the maximum amount of underlying assets that can be withdrawn by the specified owner.
    */
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = fToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /**
    * @dev Returns the maximum amount of shares that can be redeemed by the owner.
    * @param owner The address of the account for which to retrieve the maximum amount of shares redeemable.
    * @return The maximum amount of shares that can be redeemed by the owner
    */
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = fToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    // ERC20 metadata generation

    /**
    * @dev Returns the name of the vault for the given ERC20 asset.
    * The name is constructed by concatenating the prefix "FluxERC4626- " with the symbol of the asset.
    * @param asset_ ERC20 token to get the vault name for
    * @return vaultName The name of the vault for the asset
    */
    function _vaultName(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultName)
    {
        vaultName = string.concat("FluxERC4626- ", asset_.symbol());
    }

    /**
    * @dev Returns the symbol of the vault token as a concatenation of "fS-" and the symbol of the asset.
    * @param asset_ The ERC20 asset used to generate the vault token symbol.
    */
    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("fS-", asset_.symbol());
    }
}
