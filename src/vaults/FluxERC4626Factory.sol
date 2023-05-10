// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Clones} from "openzeppelin-contract/proxy/Clones.sol";

import {FluxERC4626Wrapper, IFERC20, ERC20, ERC4626, IComptroller} from "./FluxERC4626Wrapper.sol";

/// @title FluxERC4626Factory
/// @notice Factory for creating FluxERC4626 contracts
contract FluxERC4626Factory {
    // Library Usage
    using Clones for address;

    // Immutable params
    ERC20 public immutable flux; // The Flux comptroller reward contract
    address public immutable rewardRecipient; // The address that will receive the liquidity mining rewards (if any)
    IComptroller public immutable comptroller; // The Flux comptroller contract

    // Storage variables
    mapping(ERC20 => IFERC20) public underlyingToFToken; // Maps underlying asset to the corresponding fToken

    // Events
    event CreateERC4626(ERC20 indexed asset, ERC4626 vault); // Emitted when a new ERC4626 vault has been created

    // Errors
    error FluxERC4626Factory__fTokenNonexistent(); // Thrown when trying to deploy an FluxERC4626 vault using an asset without a fToken
    error ZeroAddressError(); // Thrown when trying to set a variable to zero address

    /**
     * @dev Constructor function for the contract.
     * @param comptroller_ The address of the Comptroller contract.
     * @param rewardRecipient_ The address of the reward recipient.
     * @notice Initializes the variables comptroller, rewardRecipient, and flux.
     * @dev Throws a ZeroAddressError if rewardRecipient_ is the zero address.
     */
    constructor(
        IComptroller comptroller_,
        address rewardRecipient_
    ) {
        if (rewardRecipient_ == address(0)) {
            revert ZeroAddressError();
        }
        comptroller = comptroller_;
        rewardRecipient = rewardRecipient_;
        flux = ERC20(comptroller_.getCompAddress());

        // initialize underlyingToFToken
        IFERC20[] memory allfTokens = comptroller_.getAllMarkets();
        uint256 numFTokens = allfTokens.length;
        IFERC20 fToken;
        for (uint256 i; i < numFTokens; ) {
            fToken = allfTokens[i];
            underlyingToFToken[fToken.underlying()] = fToken;

            unchecked {
                ++i;
            }
        }
    }

    // External functions

    /**
    *n @dev Creates a new FluxERC4626Vault with the specified ERC20 asset and implementation contract.
    * @param asset The ERC20 asset to be wrapped by the new vault.
    * @param implementation The address of the implementation contract to be used for the new vault.
    * @return vault The newly created FluxERC4626Vault instance.
    * Requirements:
       . The fToken corresponding to the input asset must exist.
    * Effects:
       . Creates a new FluxERC4626Vault contract instance with the specified ERC20 asset and implementation contract.
       . Initializes the newly created vault with the given parameters.
       .  Emits a CreateERC4626 event with the newly created vault address and the input asset.
    */
    function createERC4626(
        ERC20 asset,
        address implementation
    ) external virtual returns (FluxERC4626Wrapper vault) {
        IFERC20 fToken = underlyingToFToken[asset];
        if (address(fToken) == address(0)) {
            revert FluxERC4626Factory__fTokenNonexistent();
        }
        bytes32 salt = keccak256(abi.encode(address(fToken)));

        vault = FluxERC4626Wrapper(implementation.cloneDeterministic(salt));
        vault.initialize(asset, flux, fToken, comptroller, rewardRecipient);

        emit CreateERC4626(asset, vault);
    }

    /**
    * @dev Computes the address of the ERC4626 vault for the given ERC20 asset and implementation.
    * @param asset The ERC20 asset for which the vault address is to be computed.
    * @param implementation The address of the implementation contract for the ERC4626 vault.
    * @return vault The computed address of the ERC4626 vault.
    * This function computes the address of the ERC4626 vault using the predictDeterministicAddress function of the Clones library.
    */
    function computeERC4626Address(
        ERC20 asset, address implementation
    ) external view virtual returns (ERC4626 vault) {
        bytes32 salt = _getSalt(asset);
        vault = ERC4626(Clones.predictDeterministicAddress(implementation, salt, address(this)));
    }

    /**
     * @notice Updates the underlyingToFToken mapping in order to support newly added fTokens
     * @dev This is needed because Flux doesn't have an onchain registry of fTokens corresponding to underlying assets.
     * @param newFTokenIndices The indices of the new fTokens to register in the comptroller.allMarkets array
     */
    function updateUnderlyingToFToken(
        uint256[] calldata newFTokenIndices
    ) external {
        uint256 numFTokens = newFTokenIndices.length;
        IFERC20 fToken;
        uint256 index;
        for (uint256 i; i < numFTokens; ) {
            index = newFTokenIndices[i];
            fToken = comptroller.allMarkets(index);
            underlyingToFToken[fToken.underlying()] = fToken;

            unchecked {
                ++i;
            }
        }
    }

    /**
    * @dev Internal function to get the salt for a new FluxERC4626 contract based on the underlying asset.
    * @param asset The ERC20 asset used to determine the salt.
    * @return bytes32 The salt value used for creating a new FluxERC4626 contract.
    * @notice The function will revert if the corresponding fToken for the asset does not exist.
    * @notice The salt value is determined by the keccak256 hash of the fToken address.
    */
    function _getSalt(ERC20 asset) internal view returns(bytes32) {
        IFERC20 fToken = underlyingToFToken[asset];
        if (address(fToken) == address(0)) {
            revert FluxERC4626Factory__fTokenNonexistent();
        }
        return keccak256(abi.encode(address(fToken)));
    }
}
