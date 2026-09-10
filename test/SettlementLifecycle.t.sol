// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/SettlementToken.sol";
import "../contracts/DAOGovernor.sol";
import "../contracts/ProviderRegistry.sol";
import "../contracts/ProofOfPaymentRegistry.sol";

contract SettlementLifecycleTest is Test {
    SettlementToken token;
    DAOGovernor governor;
    ProviderRegistry providerRegistry;
    ProofOfPaymentRegistry proofRegistry;

    address admin = address(0x1);
    address daoMember1 = address(0x2);
    address daoMember2 = address(0x3);
    address daoMember3 = address(0x4);
    address providerA = address(0x5);
    address providerB = address(0x6);

    bytes32 constant DAO_MEMBER_ROLE = keccak256("DAO_MEMBER_ROLE");
    bytes32 constant TOKEN_ROLE = keccak256("TOKEN_ROLE");

    function setUp() public {
        vm.startPrank(admin);
        
        // 1. Deploy Registries
        providerRegistry = new ProviderRegistry();
        proofRegistry = new ProofOfPaymentRegistry();
        
        // 2. Deploy Governor (2 out of 3 quorum, 1 day voting period)
        governor = new DAOGovernor(2, 86400);

        // 3. Deploy Token
        token = new SettlementToken(address(governor), address(providerRegistry), address(proofRegistry));

        // 4. Setup Roles
        governor.grantRole(TOKEN_ROLE, address(token));
        proofRegistry.grantRole(proofRegistry.RELAYER_ROLE(), address(token));
        
        governor.grantRole(DAO_MEMBER_ROLE, daoMember1);
        governor.grantRole(DAO_MEMBER_ROLE, daoMember2);
        governor.grantRole(DAO_MEMBER_ROLE, daoMember3);

        // 5. Onboard Providers
        providerRegistry.onboardProvider(providerA, "Provider A", true);
        providerRegistry.onboardProvider(providerB, "Provider B", true);
        
        vm.stopPrank();
    }

    function test_Lifecycle_MintHoldTransferBurn() public {
        // --- STEP 1: Mint Request & Execution ---
        bytes32 proofId = bytes32("TXN-12345");
        bytes32 docHash = keccak256("BankStatement");

        // Admin submits proof
        vm.prank(admin);
        proofRegistry.submitProof(proofId, docHash);

        // Provider A requests mint
        vm.prank(providerA);
        uint256 mintProposalId = token.requestMint(providerA, 100_000e18, proofId);

        // DAO members vote to approve mint
        vm.prank(daoMember1);
        governor.castVote(mintProposalId, true);
        vm.prank(daoMember2);
        governor.castVote(mintProposalId, true);

        // Execute mint
        vm.prank(providerA);
        token.executeMint(mintProposalId);

        assertEq(token.balanceOf(providerA), 100_000e18);

        // --- STEP 2: Internal Transfer ---
        vm.prank(providerA);
        uint256 transferProposalId = token.requestInternalTransfer(providerA, providerB, 20_000e18);

        // DAO members vote
        vm.prank(daoMember2);
        governor.castVote(transferProposalId, true);
        vm.prank(daoMember3);
        governor.castVote(transferProposalId, true);

        // Execute transfer
        vm.prank(providerA);
        token.executeInternalTransfer(transferProposalId, providerB);

        assertEq(token.balanceOf(providerA), 80_000e18);
        assertEq(token.balanceOf(providerB), 20_000e18);

        // --- STEP 3: Burn (Withdrawal) ---
        bytes32 payoutHash = keccak256("WireTransferDetails");
        vm.prank(providerB);
        uint256 burnProposalId = token.requestBurn(providerB, 20_000e18, payoutHash);

        // DAO members vote
        vm.prank(daoMember1);
        governor.castVote(burnProposalId, true);
        vm.prank(daoMember3);
        governor.castVote(burnProposalId, true);

        // Execute burn
        vm.prank(providerB);
        token.executeBurn(burnProposalId);

        assertEq(token.balanceOf(providerB), 0);
        assertEq(token.totalBurned(), 20_000e18);
    }
}
