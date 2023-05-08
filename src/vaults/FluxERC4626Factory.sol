// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IFERC20} from "./utils/flux/IFERC20.sol";
import {FluxERC4626Wrapper} from "./FluxERC4626Wrapper.sol";
import {IComptroller} from "./utils/flux/IComptroller.sol";
import {ERC4626Factory} from "./utils/ERC4626Factory.sol";
import "forge-std/console.sol";

/// @title FluxERC4626Factory
/// @notice Factory for creating FluxERC4626 contracts
contract FluxERC4626Factory is ERC4626Factory {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when trying to deploy an FluxERC4626 vault using an asset without a fToken
    error FluxERC4626Factory__fTokenNonexistent();
    /// @notice Thrown when trying to set a variable to zero address
    error ZeroAddressError();

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Flux token contract
    ERC20 public immutable comp;

    /// @notice The address that will receive the liquidity mining rewards (if any)
    address public immutable rewardRecipient;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// @notice The Compound cEther address
    address internal immutable fEtherAddress;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Maps underlying asset to the corresponding fToken
    mapping(ERC20 => IFERC20) public underlyingToFToken;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(IComptroller comptroller_, address cEtherAddress_, address rewardRecipient_) {
        if(cEtherAddress_ == address(0) || rewardRecipient_ == address(0)) {
            revert ZeroAddressError();
        }
        comptroller = comptroller_;
        fEtherAddress = cEtherAddress_;
        rewardRecipient = rewardRecipient_;
        comp = ERC20(comptroller_.getCompAddress());

        // initialize underlyingToFToken
        IFERC20[] memory allfTokens = comptroller_.getAllMarkets();
        uint256 numFTokens = allfTokens.length;
        console.log("Length is", numFTokens);
        IFERC20 fToken;
        for (uint256 i; i < numFTokens;) {
            fToken = allfTokens[i];
            console.log("F token is", address(fToken));
            if (address(fToken) != cEtherAddress_) {
                underlyingToFToken[fToken.underlying()] = fToken;
            }

            unchecked {
                ++i;
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc ERC4626Factory
    function createERC4626(ERC20 asset) external virtual override returns (ERC4626 vault) {
        IFERC20 fToken = underlyingToFToken[asset];
        if (address(fToken) == address(0)) {
            revert FluxERC4626Factory__fTokenNonexistent();
        }

        vault = new FluxERC4626Wrapper{salt: bytes32(0)}(asset, comp, fToken, comptroller, rewardRecipient);

        emit CreateERC4626(asset, vault);
    }

    /// @inheritdoc ERC4626Factory
    function computeERC4626Address(ERC20 asset) external view virtual override returns (ERC4626 vault) {
        vault = ERC4626(
            _computeCreate2Address(
                keccak256(
                    abi.encodePacked(
                        // Deployment bytecode:
                        type(FluxERC4626Wrapper).creationCode,
                        // Constructor arguments:
                        abi.encode(asset, comp, underlyingToFToken[asset], rewardRecipient, comptroller)
                    )
                )
            )
        );
    }

    /// @notice Updates the underlyingToFToken mapping in order to support newly added fTokens
    /// @dev This is needed because Compound doesn't have an onchain registry of fTokens corresponding to underlying assets.
    /// @param newFTokenIndices The indices of the new fTokens to register in the comptroller.allMarkets array
    function updateUnderlyingToFToken(uint256[] calldata newFTokenIndices) external {
        uint256 numFTokens = newFTokenIndices.length;
        IFERC20 fToken;
        uint256 index;
        for (uint256 i; i < numFTokens;) {
            index = newFTokenIndices[i];
            fToken = comptroller.allMarkets(index);
            if (address(fToken) != fEtherAddress) {
                underlyingToFToken[fToken.underlying()] = fToken;
            }

            unchecked {
                ++i;
            }
        }
    }
}