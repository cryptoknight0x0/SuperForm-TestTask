// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
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
        console.log("Created impl");
        vault = FluxERC4626Wrapper(
            address(factory.createERC4626(ERC20(asset), address(vaultImpl)))
        );
        vm.prank(msg.sender);
        vault.setRoute(3000, weth, 3000);
        console.log("vault", address(vault));
        alice = address(0x1);
        deal(address(asset), alice, 1000 ether);
    }

    function testDepositWithdraw() public {
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

        vault.withdraw(aliceAssetsToWithdraw, alice, alice);
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
        //vm.warp(block.timestamp + 10 days);
        vm.roll(block.number + 100);
        vault.harvest(0);
        assertGt(vault.totalAssets(), aliceUnderlyingAmount);
        vault.withdraw(aliceAssetsToWithdraw, alice, alice);
    }
}
