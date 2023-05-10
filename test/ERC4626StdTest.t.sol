// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import "erc4626-tests/ERC4626.test.sol";
import "../src/vaults/FluxERC4626Factory.sol";

/// @title ERC4626 Property Tests
/// @author Taken from https://github.com/a16z/erc4626-tests
/// @dev Modified to work with a deployed vault whose address is read from env.
/// It also provides the `_needsRolling` property and support for vaults where `deal()` can't find the storage slot.
contract ERC4626StdTest is ERC4626Test {
    address public userWithAssets;

    address public UNDERLYING = vm.envAddress("UNDERLYING");
    address public COMPTROLLER = vm.envAddress("COMPTROLLER");
    string public MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 public BLOCK_NO = vm.envUint("BLOCK_NO");

    FluxERC4626Factory public factory;
    FluxERC4626Wrapper public fluxERC4626;
    bool _needsRolling;

    function setUp() public override {
        fork();
        _underlying_ = UNDERLYING;
        factory = new FluxERC4626Factory(
            IComptroller(COMPTROLLER),
            msg.sender
        );
        FluxERC4626Wrapper vaultImpl = new FluxERC4626Wrapper();
        fluxERC4626 = factory.createERC4626(ERC20(UNDERLYING), address(vaultImpl));
        _vault_ = address(fluxERC4626);
        userWithAssets = 0x7066fb331a6932563369eE8cbd297856F75A3Bd5;
        _underlying_ = address(ERC4626(_vault_).asset());
        _delta_ = 10;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
        // some protocols will revert if doing a deposit followed by a withdrawal on the same block
        _needsRolling = true;
    }

    function setUpVault(Init memory init) public override {
        uint256 maxAssetPerUser;

        if (userWithAssets != address(0)) {
            // init vault
            vm.startPrank(userWithAssets);
            ERC20(_underlying_).approve(_vault_, type(uint256).max);
            IERC4626(_vault_).deposit(
                1 * 10 ** ERC20(_underlying_).decimals(),
                userWithAssets
            );
            vm.stopPrank();

            // user asset balance
            uint256 assetBal = ERC20(_underlying_).balanceOf(userWithAssets);
            maxAssetPerUser = assetBal / 2 / N;
        }

        // setup initial shares and assets for individual users
        for (uint256 i = 0; i < N; i++) {
            address user = init.user[i];
            vm.assume(_isEOA(user));
            vm.assume(user != address(0));

            // shares
            if (userWithAssets == address(0)) {
                uint256 shares = init.share[i];
                deal(_underlying_, user, shares);
                _approve(_underlying_, user, _vault_, shares);
                vm.prank(user);
                try IERC4626(_vault_).deposit(shares, user) {} catch {
                    vm.assume(false);
                }
            } else {
                init.share[i] = bound(init.share[i], 100, maxAssetPerUser);
                uint256 shares = init.share[i];
                vm.prank(userWithAssets);
                ERC4626(_vault_).deposit(shares, user);
            }

            // assets
            if (userWithAssets == address(0)) {
                uint256 assets = init.asset[i];
                deal(_underlying_, user, assets);
            } else {
                init.asset[i] = bound(init.asset[i], 100, maxAssetPerUser);
                uint256 assets = init.asset[i];
                vm.prank(userWithAssets);
                ERC20(_underlying_).transfer(user, assets);
            }

            if (_needsRolling) vm.roll(block.number + 1);
        }
    }

    function fork() internal {
        vm.createSelectFork(MAINNET_RPC_URL, BLOCK_NO); // create a fork
    }
}
