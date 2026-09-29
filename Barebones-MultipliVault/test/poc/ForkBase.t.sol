// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

// PoC 基座：fork Avalanche C-Chain，直接操作线上 xUSDC 代理（不要调用实现合约）
// 运行: AVAX_RPC=<rpc> forge test --match-path test/poc/*.t.sol -vvv
// 建议固定区块: FORK_BLOCK=<n>

import { Test, console2 } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MultipliVault } from "../../src/vault/MultipliVault.sol";
import { VaultFundManager } from "../../src/managers/VaultFundManager.sol";
import { VariableVaultFee } from "../../src/fees/VariableVaultFee.sol";
import { RolesAuthority } from "solmate/auth/authorities/RolesAuthority.sol";

abstract contract ForkBase is Test {
    MultipliVault internal constant VAULT = MultipliVault(0xCF0Eb4ac018C06a16ED5c63484823C7805e7599D);
    address internal constant IMPL = 0xb63601A11c5bDC79D511B8F73871d7C0d8B57AE9;
    VaultFundManager internal constant FM = VaultFundManager(0x01e676EAA0C9780A88395c651349Cf08Fe52368e);
    RolesAuthority internal constant AUTH = RolesAuthority(0xf580B985e2Fd8A8b0e4a56C2a7E24bC28e872609);
    VariableVaultFee internal constant FEE = VariableVaultFee(0x4E5FEa916ef8458b8D877BD760B6930Fb4f28B72);
    IERC20 internal constant USDC = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    address internal constant OWNER = 0xf25c404c101D40d88b5dCD64B82583dBC918Dd25;

    uint8 internal constant ROLE_ADMIN = 1;
    uint8 internal constant ROLE_FUND_MANAGER = 2;
    uint8 internal constant ROLE_FM_CONTRACT = 3;

    address internal attacker = makeAddr("attacker");
    address internal alice = makeAddr("alice");
    address internal operator = makeAddr("fundManagerEOA"); // 测试用运营者，由 owner 在 fork 上授予 FUND_MANAGER

    function setUp() public virtual {
        uint256 blk = vm.envOr("FORK_BLOCK", uint256(0));
        string memory rpc = vm.envString("AVAX_RPC");
        if (blk == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, blk);
        assertEq(block.chainid, 43114, "not avalanche");

        vm.prank(OWNER);
        AUTH.setUserRole(operator, ROLE_FUND_MANAGER, true);

        vm.label(address(VAULT), "xUSDC");
        vm.label(address(FM), "VaultFundManager");
        vm.label(address(AUTH), "RolesAuthority");
        vm.label(address(FEE), "VariableVaultFee");
        vm.label(address(USDC), "USDC");
    }

    // ---- 常用操作 ----
    function _fund(address who, uint256 amt) internal { deal(address(USDC), who, amt); }

    function _deposit(address who, uint256 amt) internal returns (uint256 shares) {
        _fund(who, amt);
        vm.startPrank(who);
        USDC.approve(address(VAULT), amt);
        shares = VAULT.deposit(amt, who);
        vm.stopPrank();
    }

    function _requestRedeem(address who, uint256 shares) internal returns (uint256) {
        vm.prank(who);
        return VAULT.requestRedeem(shares, who, who);
    }

    /// 运营者走正式路径: FUND_MANAGER -> vault.manage -> FM -> vault 回调
    function _manageFM(bytes memory data) internal {
        vm.prank(operator);
        VAULT.manage(address(FM), data, 0);
    }

    function _printNav(string memory tag) internal view {
        console2.log("==", tag);
        console2.log(" totalAssets   ", VAULT.totalAssets());
        console2.log(" totalSupply   ", VAULT.totalSupply());
        console2.log(" aggregated    ", VAULT.aggregatedUnderlyingBalances());
        console2.log(" idle          ", USDC.balanceOf(address(VAULT)));
        console2.log(" pendingAssets ", VAULT.totalPendingAssets());
        console2.log(" pps(1e6 share)", VAULT.convertToAssets(1e6));
    }
}

/// 冒烟测试：确认 fork 与接线正确
contract ForkSmoke is ForkBase {
    function test_wiring() public {
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(address(uint160(uint256(vm.load(address(VAULT), implSlot)))), IMPL, "impl slot");
        assertEq(address(FM.vault()), address(VAULT));
        assertEq(address(VAULT.authority()), address(AUTH));
        assertTrue(AUTH.doesUserHaveRole(address(FM), ROLE_FM_CONTRACT));
        _printNav("live");
        uint256 s = _deposit(alice, 100e6);
        assertGt(s, 0);
        _requestRedeem(alice, s);
        _printNav("after alice deposit+request");
    }
}
