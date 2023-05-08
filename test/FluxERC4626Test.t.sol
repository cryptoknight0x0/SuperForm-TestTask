// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "erc4626-tests/ERC4626.test.sol";

// import {ERC20} from "solmate/tokens/ERC20.sol";

import { IFERC20, ERC20 } from "../src/vaults/utils/flux/IFERC20.sol";
import { IComptroller } from "../src/vaults/utils/flux/IComptroller.sol";
import { FluxERC4626Factory } from "../src/vaults/FluxERC4626Factory.sol";
import { FluxERC4626Wrapper } from "../src/vaults/FluxERC4626Wrapper.sol";

contract ERC4626StdTest is ERC4626Test {

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant fUSDC = 0x465a5a630482f3abD6d3b84B39B29b07214d19e5;
    address public constant COMPTROLLER = 0x95Af143a021DF745bc78e845b54591C53a8B3A51;
    address public constant COMPOUND_ETHER = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 public constant BLOCK_NO = 17215000;

    IFERC20 public fToken;
    FluxERC4626Factory public factory;
    FluxERC4626Wrapper public fluxERC4626;
    
    function setUp() public override {
        uint256 fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        vm.rollFork(BLOCK_NO);

        _underlying_ = USDC;
        fToken = IFERC20(fUSDC);
        factory = new FluxERC4626Factory(IComptroller(COMPTROLLER), COMPOUND_ETHER, msg.sender);
        fluxERC4626 = FluxERC4626Wrapper(address(factory.createERC4626(ERC20(_underlying_))));
        _vault_ = address(fluxERC4626);
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        // _unlimitedAmount = false;



        // _underlying_ = address(new MockERC20("Mock ERC20", "MERC20", 18));
        // // _vault_ = address(new ERC4626Mock(MockERC20(__underlying__), "Mock ERC4626", "MERC4626"));
        // _delta_ = 0;
        // _vaultMayBeEmpty = false;
        // _unlimitedAmount = false;
    }
}