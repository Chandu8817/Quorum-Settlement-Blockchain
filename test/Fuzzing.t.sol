// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/SettlementToken.sol";
import "../contracts/DAOGovernor.sol";
import "../contracts/ProviderRegistry.sol";
import "../contracts/ProofOfPaymentRegistry.sol";

contract FuzzingTest is Test {
    SettlementToken token;
    DAOGovernor governor;
    ProviderRegistry providerRegistry;
    ProofOfPaymentRegistry proofRegistry;

    address admin = address(0x1);
    address daoMember1 = address(0x2);
    address daoMember2 = address(0x3);
    address daoMember3 = address(0x4);
    address providerA = address(0x5);

    bytes32 constant DAO_MEMBER_ROLE = keccak256("DAO_MEMBER_ROLE");
    bytes32 constant TOKEN_ROLE = keccak256("TOKEN_ROLE");

    function setUp() public {
        vm.startPrank(admin);
        
        providerRegistry = new ProviderRegistry();
        proofRegistry = new ProofOfPaymentRegistry();
        
        // 2 out of 3 quorum
        governor = new DAOGovernor(2, 86400);

        token = new SettlementToken(address(governor), address(providerRegistry), address(proofRegistry));

        governor.grantRole(TOKEN_ROLE, address(token));
        proofRegistry.grantRole(proofRegistry.RELAYER_ROLE(), address(token));
        
        governor.grantRole(DAO_MEMBER_ROLE, daoMember1);
        governor.grantRole(DAO_MEMBER_ROLE, daoMember2);
        governor.grantRole(DAO_MEMBER_ROLE, daoMember3);

        providerRegistry.onboardProvider(providerA, "Provider A", true);
        vm.stopPrank();
    }

    function testFuzz_MintingAmounts(uint256 amount) public {
        // Bound amount to prevent realistic overflow but allow huge numbers
        amount = bound(amount, 1, 100_000_000e18);

        bytes32 proofId = bytes32(uint256(keccak256(abi.encodePacked(amount))));
        bytes32 docHash = keccak256("BankStatement");

        vm.prank(admin);
        proofRegistry.submitProof(proofId, docHash);

        vm.prank(providerA);
        uint256 proposalId = token.requestMint(providerA, amount, proofId);

        vm.prank(daoMember1);
        governor.castVote(proposalId, true);
        vm.prank(daoMember2);
        governor.castVote(proposalId, true);

        vm.prank(providerA);
        token.executeMint(proposalId);

        assertEq(token.balanceOf(providerA), amount);
        assertEq(token.totalSupply(), amount);
    }
    
    function testFuzz_VotingExpiry(uint256 warpTime) public {
        warpTime = bound(warpTime, 86401, type(uint256).max - block.timestamp);
        
        bytes32 proofId = bytes32("TXN-EXPIRY");
        bytes32 docHash = keccak256("BankStatement");

        vm.prank(admin);
        proofRegistry.submitProof(proofId, docHash);

        vm.prank(providerA);
        uint256 proposalId = token.requestMint(providerA, 1000, proofId);

        // Warp time past expiry
        vm.warp(block.timestamp + warpTime);

        // Voting should revert
        vm.prank(daoMember1);
        vm.expectRevert(DAOGovernor.ProposalNotActive.selector);
        governor.castVote(proposalId, true);
    }
}
