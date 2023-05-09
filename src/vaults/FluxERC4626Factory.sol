// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {FluxERC4626Wrapper, IFERC20, ERC20, ERC4626, IComptroller} from "./FluxERC4626Wrapper.sol";
import {ERC4626Factory} from "./utils/ERC4626Factory.sol";

/// @title FluxERC4626Factory
/// @notice Factory for creating FluxERC4626 contracts
contract FluxERC4626Factory is ERC4626Factory {

    // Immutable params

    ERC20 public immutable comp; // The Flux token contract
    IComptroller public immutable comptroller; // The Compound comptroller contract
    address internal immutable cEtherAddress; // The Compound cEther address

    // Storage variables

    mapping(ERC20 => IFERC20) public underlyingToFToken; // Maps underlying asset to the corresponding fToken

    // Errors

    error FluxERC4626Factory__fTokenNonexistent(); // Thrown when trying to deploy an FluxERC4626 vault using an asset without a fToken
    error ZeroAddressError(); // Thrown when trying to set a variable to zero address


    /**
    * @dev Constructor function that initializes the Comptroller contract and the address of cETH.
    * @param comptroller_ The address of the Comptroller contract.
    * @param cEtherAddress_ The address of the cETH contract.
    * @notice If cEtherAddress_ is the zero address, it will revert with a ZeroAddressError.
    * @notice The function will also initialize the underlyingToFToken mapping using getAllMarkets function of Comptroller contract.
    */
    constructor(IComptroller comptroller_, address cEtherAddress_) {
        if(cEtherAddress_ == address(0)) {
            revert ZeroAddressError();
        }
        comptroller = comptroller_;
        cEtherAddress = cEtherAddress_;
        comp = ERC20(comptroller_.getCompAddress());

        // initialize underlyingToFToken
        IFERC20[] memory allfTokens = comptroller_.getAllMarkets();
        uint256 numFTokens = allfTokens.length;
        IFERC20 fToken;
        for (uint256 i; i < numFTokens;) {
            fToken = allfTokens[i];
            if (address(fToken) != cEtherAddress_) {
                underlyingToFToken[fToken.underlying()] = fToken;
            }

            unchecked {
                ++i;
            }
        }
    }

    // External functions

    /**
    * @notice Creates a new instance of an ERC4626 vault for a given ERC20 asset.
    * @dev The vault is created by deploying a new instance of FluxERC4626Wrapper contract.
    * @param asset The ERC20 asset for which a vault is being created.
    * @return vault The newly created instance of the ERC4626 vault.
    * @dev The vault will be created using the underlying fToken associated with the asset.
    * @dev If the underlying fToken does not exist, the function will revert.
    * @dev The vault is created with a salt value of 0 to ensure uniqueness.
    * @dev Emits a CreateERC4626 event with details of the asset and vault.
    */
    function createERC4626(ERC20 asset) external virtual override returns (ERC4626 vault) {
        IFERC20 fToken = underlyingToFToken[asset];
        if (address(fToken) == address(0)) {
            revert FluxERC4626Factory__fTokenNonexistent();
        }

        vault = new FluxERC4626Wrapper{salt: bytes32(0)}(asset, fToken, comptroller);

        emit CreateERC4626(asset, vault);
    }

    /**
    * @dev Computes the address of the ERC4626 vault for the given ERC20 asset using create2.
    * @param asset The ERC20 asset for which the ERC4626 vault address is being computed.
    * @return vault The computed ERC4626 vault address.
    * This function computes the address of the ERC4626 vault for a given ERC20 asset using the create2 function, which allows for deterministic deployment of contracts. The computed address is based on the keccak256 hash of the deployment bytecode of the FluxERC4626Wrapper contract and the constructor arguments, which include the asset, the underlying fToken address, and the Comptroller address.
    */
    function computeERC4626Address(ERC20 asset) external view virtual override returns (ERC4626 vault) {
        vault = ERC4626(
            _computeCreate2Address(
                keccak256(
                    abi.encodePacked(
                        // Deployment bytecode:
                        type(FluxERC4626Wrapper).creationCode,
                        // Constructor arguments:
                        abi.encode(asset, underlyingToFToken[asset], comptroller)
                    )
                )
            )
        );
    }

    /** 
    * @notice Updates the underlyingToFToken mapping in order to support newly added fTokens
    * @dev This is needed because Compound doesn't have an onchain registry of fTokens corresponding to underlying assets.
    * @param newFTokenIndices The indices of the new fTokens to register in the comptroller.allMarkets array
    */
    function updateUnderlyingToFToken(uint256[] calldata newFTokenIndices) external {
        uint256 numFTokens = newFTokenIndices.length;
        IFERC20 fToken;
        uint256 index;
        for (uint256 i; i < numFTokens;) {
            index = newFTokenIndices[i];
            fToken = comptroller.allMarkets(index);
            if (address(fToken) != cEtherAddress) {
                underlyingToFToken[fToken.underlying()] = fToken;
            }

            unchecked {
                ++i;
            }
        }
    }
}