// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/SettlementToken.sol";
import "../contracts/DAOGovernor.sol";
import "../contracts/ProviderRegistry.sol";
import "../contracts/ProofOfPaymentRegistry.sol";

contract AccessControlTest is Test {
    SettlementToken token;
    DAOGovernor governor;
    ProviderRegistry providerRegistry;
    ProofOfPaymentRegistry proofRegistry;

    address admin = address(0x1);
    address daoMember1 = address(0x2);
    address daoMember2 = address(0x3);
    address unapprovedProvider = address(0x6);
    address nonDaoMember = address(0x7);

    bytes32 constant DAO_MEMBER_ROLE = keccak256("DAO_MEMBER_ROLE");
    bytes32 constant TOKEN_ROLE = keccak256("TOKEN_ROLE");

    function setUp() public {
        vm.startPrank(admin);
        
        providerRegistry = new ProviderRegistry();
        proofRegistry = new ProofOfPaymentRegistry();
        governor = new DAOGovernor(2, 86400);
        token = new SettlementToken(address(governor), address(providerRegistry), address(proofRegistry));

        governor.grantRole(TOKEN_ROLE, address(token));
        proofRegistry.grantRole(proofRegistry.RELAYER_ROLE(), address(token));
        
        governor.grantRole(DAO_MEMBER_ROLE, daoMember1);
        governor.grantRole(DAO_MEMBER_ROLE, daoMember2);
        
        vm.stopPrank();
    }

    function test_RevertIf_UnapprovedProviderRequestsMint() public {
        bytes32 proofId = bytes32("TXN-12345");
        bytes32 docHash = keccak256("BankStatement");

        vm.prank(admin);
        proofRegistry.submitProof(proofId, docHash);

        vm.prank(unapprovedProvider);
        vm.expectRevert(SettlementToken.NotAuthorized.selector);
        token.requestMint(unapprovedProvider, 100_000e18, proofId);
    }

    function test_RevertIf_NonDaoMemberVotes() public {
        // First onboard a provider and create a valid proposal
        vm.prank(admin);
        providerRegistry.onboardProvider(unapprovedProvider, "Provider A", true);
        
        bytes32 proofId = bytes32("TXN-12345");
        bytes32 docHash = keccak256("BankStatement");

        vm.prank(admin);
        proofRegistry.submitProof(proofId, docHash);

        vm.prank(unapprovedProvider);
        uint256 proposalId = token.requestMint(unapprovedProvider, 100_000e18, proofId);

        // Try to vote with a non-DAO member
        vm.prank(nonDaoMember);
        vm.expectRevert();
        governor.castVote(proposalId, true);
    }

    function test_RevertIf_TransferBetweenUnapproved() public {
        vm.prank(unapprovedProvider);
        vm.expectRevert(SettlementToken.InvalidTransfer.selector);
        token.transfer(address(0x8), 100);
    }
}
