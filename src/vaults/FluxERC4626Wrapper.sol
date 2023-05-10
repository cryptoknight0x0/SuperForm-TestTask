// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ERC4626, Initializable} from "./utils/flux/tokens/ERC4626.sol";
import {IFERC20, ERC20} from "./utils/flux/IFERC20.sol";
import {IComptroller} from "./utils/flux/IComptroller.sol";
import {ISwapRouter} from "./utils/flux/ISwapRouter.sol";

/// @title FluxERC4626Wrapper - Custom implementation of yield-daddy wrappers with flexible reinvesting logic
/// Rationale: Forked protocols often implement custom functions and modules on top of forked code.
/// Example: Staking systems. Very common in DeFi. Re-investing/Re-Staking rewards on the Vault level can be included in permissionless way.
contract FluxERC4626Wrapper is ERC4626 {
    // Libraries usage
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // Constants
    uint256 internal constant NO_ERROR = 0;
    ISwapRouter public immutable SWAP_ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // Immutable params
    address private _manager; // Access Control for harvest() route
    ERC20 private _reward; // The FLUX-like token contract
    IFERC20 private _fToken; // The Flux fToken contract
    IComptroller private _comptroller; // The Flux comptroller contract

    // Storage Variables
    bytes public swapPath;

    // Errors
    /// @param errorCode The error code returned by Flux
    error FluxERC4626__FluxError(uint256 errorCode); // Thrown when a call to Flux returned an error.
    error ZeroAddressError(); // Thrown when trying to set a zero address in a variable.
    error INVALID_ACCESS_ERROR(); // Thrown when caller donot have access rights.
    error INVALID_FEE_ERROR(); // Thrown when pool fee is incorrect.
    error MIN_AMOUNT_ERROR(); // Thrown when min amount rrquired not met.


    /**
    * @dev Constructor function for the contract.
    * Note: The _disableInitializers() function is used to prevent any further initialization of the contract
    * in the future, making it impossible to upgrade or modify the deployed logic contract.
    */
    constructor() {
        _disableInitializers(); // using this so that the deployed logic contract later cannot be initialized
    }

    /* INITIALZER
     ****************************************************************************************************************/
    /**
    * @dev Initializes a new instance of the vault contract.
    * @param asset_ The underlying asset contract of the vault.
    * @param reward_ The reward token contract for yield farming.
    * @param fToken_ The interest-bearing asset contract.
    * @param comptroller_ The contract that manages the minting and redeeming of fTokens.
    * @param manager_ The address of the manager who has the authority to modify the vault parameters.
    */
    function initialize(ERC20 asset_, ERC20 reward_, IFERC20 fToken_, IComptroller comptroller_, address manager_) external initializer {
        __ERC4626_init(asset_, _vaultName(asset_), _vaultSymbol(asset_));
        _reward = reward_;
        _fToken = fToken_;
        _comptroller = comptroller_;
        if (manager_ == address(0)) {
            revert ZeroAddressError();
        }
        _manager = manager_;
    }

    /// @notice sets the swap path for reinvesting rewards
    /// @param poolFee1_ fee for first swap
    /// @param tokenMid_ token for first swap
    /// @param poolFee2_ fee for second swap
    function setRoute(
        uint24 poolFee1_,
        address tokenMid_,
        uint24 poolFee2_
    ) external {
        if (msg.sender != _manager) revert INVALID_ACCESS_ERROR();
        if (poolFee1_ == 0) revert INVALID_FEE_ERROR();
        if (poolFee2_ == 0 || tokenMid_ == address(0))
            swapPath = abi.encodePacked(_reward, poolFee1_, address(_asset));
        else
            swapPath = abi.encodePacked(
                _reward,
                poolFee1_,
                tokenMid_,
                poolFee2_,
                address(_asset)
            );
        ERC20(_reward).approve(address(SWAP_ROUTER), type(uint256).max); /// max approve
    }

    /// @notice Claims liquidity mining rewards from Flux and performs low-lvl swap with instant reinvesting
    /// Calling harvest() claims COMP-Fork token through direct Pair swap for best control and lowest cost
    /// harvest() can be called by anybody. ideally this function should be adjusted per needs (e.g add fee for harvesting)
    function harvest(uint256 minAmountOut_) external {
        IFERC20[] memory fTokens = new IFERC20[](1);
        fTokens[0] = _fToken;
        _comptroller.claimComp(address(this), fTokens);

        uint256 earned = ERC20(_reward).balanceOf(address(this));
        uint256 reinvestAmount;
        /// @dev Swap rewards to asset
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: swapPath,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: earned,
                amountOutMinimum: minAmountOut_
            });

        // Executes the swap.
        reinvestAmount = SWAP_ROUTER.exactInput(params);
        if (reinvestAmount < minAmountOut_) {
            revert MIN_AMOUNT_ERROR();
        }
        afterDeposit(_asset.balanceOf(address(this)), 0);
    }

    /// ERC4626 overrides

    /**
     * @dev Returns the total assets held by this contract, in terms of the underlying asset.
     * Total assets are calculated as the product of the balance of this contract in the underlying asset, and the current exchange rate of the fToken.
     * @return The total assets held by this contract, in terms of the underlying asset.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return
            _fToken.balanceOf(address(this)).mulWadDown(
                _fToken.exchangeRateStored()
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
        uint256 errorCode = _fToken.redeemUnderlying(assets);
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
        _asset.safeApprove(address(_fToken), assets);

        // deposit into fToken
        uint256 errorCode = _fToken.mint(assets);
        if (errorCode != NO_ERROR) {
            revert FluxERC4626__FluxError(errorCode);
        }
    }

    /**
     * @dev Returns the maximum deposit allowed for the given fToken contract address.
     * @return The maximum deposit amount allowed as an unsigned integer of type uint256.
     */
    function maxDeposit(address) public view override returns (uint256) {
        if (_comptroller.mintGuardianPaused(_fToken)) return 0;
        return type(uint256).max;
    }

    /**
     * @dev Returns the maximum possible tokens that can be minted.
     * @dev Returns a `uint256` value representing the maximum mint value of the `uint256` type.
     * If minting of the `fToken` is paused by the guardian, the function returns `0`.
     */
    function maxMint(address) public view override returns (uint256) {
        if (_comptroller.mintGuardianPaused(_fToken)) return 0;
        return type(uint256).max;
    }

    /**
     * @dev Calculates the maximum amount of underlying assets that can be withdrawn by the specified owner from this contract,
     * taking into account the current cash balance and the owner's balance of fTokens.
     * @param owner The address of the owner whose maximum withdrawal amount needs to be calculated.
     * @dev Returns the maximum amount of underlying assets that can be withdrawn by the specified owner.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = _fToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    /**
     * @dev Returns the maximum amount of shares that can be redeemed by the owner.
     * @param owner The address of the account for which to retrieve the maximum amount of shares redeemable.
     * @return The maximum amount of shares that can be redeemed by the owner
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = _fToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    // Getters

    /**
     * @dev Returns the manager of this ERC4626 Vault.
     */
    function manager() public view virtual returns (address) {
        return _manager;
    }

    /**
     * @dev Returns the reward collected from comptroller of this ERC4626 Vault.
     */
    function reward() public view virtual returns (ERC20) {
        return _reward;
    }

    /**
     * @dev Returns the fToken of this ERC4626 Vault.
     */
    function fToken() public view virtual returns (IFERC20) {
        return _fToken;
    }

    /**
     * @dev Returns the comptroller of this ERC4626 Vault.
     */
    function comptroller() public view virtual returns (IComptroller) {
        return _comptroller;
    }

    // ERC20 metadata generation

    /**
     * @dev Returns the name of the vault for the given ERC20 asset.
     * The name is constructed by concatenating the prefix "FluxERC4626- " with the symbol of the asset.
     * @param asset_ ERC20 token to get the vault name for
     * @return vaultName The name of the vault for the asset
     */
    function _vaultName(
        ERC20 asset_
    ) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("FluxERC4626- ", asset_.symbol());
    }

    /**
     * @dev Returns the symbol of the vault token as a concatenation of "fS-" and the symbol of the asset.
     * @param asset_ The ERC20 asset used to generate the vault token symbol.
     */
    function _vaultSymbol(
        ERC20 asset_
    ) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("fS-", asset_.symbol());
    }
}
