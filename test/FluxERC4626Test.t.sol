// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IComptroller} from "../src/vaults/utils/flux/IComptroller.sol";
import "../src/vaults/FluxERC4626Factory.sol";

contract FluxERC4626Test is Test {
    uint256 public ethFork;
    address public alice;
    ERC20 public asset;
    FluxERC4626Wrapper public vault;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address public UNDERLYING = vm.envAddress("UNDERLYING");
    address public COMPTROLLER = vm.envAddress("COMPTROLLER");
    address public weth = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    function setUp() public {
        ethFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(ethFork);
        asset =  ERC20(UNDERLYING);
        FluxERC4626Factory factory = new FluxERC4626Factory(
            IComptroller(COMPTROLLER),
            msg.sender
        );
        FluxERC4626Wrapper vaultImpl = new FluxERC4626Wrapper();
        vault = FluxERC4626Wrapper(
            address(factory.createERC4626(ERC20(asset), address(vaultImpl)))
        );
        vm.prank(msg.sender);
        vault.setRoute(3000, weth, 3000);
        alice = address(0x1);
        deal(address(asset), alice, 1000 ether);
    }

    function testDepositWithdraw() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);

        uint256 aliceUnderlyingAmount = amount;

        SafeTransferLib.safeApprove(asset, address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vault.withdraw(aliceAssetsToWithdraw, alice, alice);
    }

    function testERC4626Deployments() public {
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        address OUSG = 0x1B19C19393e2d034D8Ff31ff34c81252FcBbee92;

        FluxERC4626Factory fluxFactory = new FluxERC4626Factory(IComptroller(COMPTROLLER), msg.sender);
        FluxERC4626Wrapper vaultLogic = new FluxERC4626Wrapper();

        vault = FluxERC4626Wrapper(
            address(fluxFactory.createERC4626(ERC20(USDC), address(vaultLogic)))
        );
        vault = FluxERC4626Wrapper(
            address(fluxFactory.createERC4626(ERC20(DAI), address(vaultLogic)))
        );
        vault = FluxERC4626Wrapper(
            address(fluxFactory.createERC4626(ERC20(USDT), address(vaultLogic)))
        );
        vault = FluxERC4626Wrapper(
            address(fluxFactory.createERC4626(ERC20(FRAX), address(vaultLogic)))
        );
        vault = FluxERC4626Wrapper(
            address(fluxFactory.createERC4626(ERC20(OUSG), address(vaultLogic)))
        );
    }

    // Failing swap thorugh Uniswap router for Reward token
    function testHarvest() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);

        uint256 aliceUnderlyingAmount = amount;

        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        vm.roll(block.number + 100);
        vault.harvest(0);
        assertGt(vault.totalAssets(), aliceUnderlyingAmount);
        vault.withdraw(aliceAssetsToWithdraw, alice, alice);
    }
}
