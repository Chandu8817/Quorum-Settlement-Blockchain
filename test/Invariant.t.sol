// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/SettlementToken.sol";
import "../contracts/DAOGovernor.sol";
import "../contracts/ProviderRegistry.sol";
import "../contracts/ProofOfPaymentRegistry.sol";

// Contract to handle the calls for invariant testing
contract Handler is Test {
    SettlementToken token;
    DAOGovernor governor;
    ProviderRegistry providerRegistry;
    ProofOfPaymentRegistry proofRegistry;

    address admin = address(0x1);
    address daoMember1 = address(0x2);
    address daoMember2 = address(0x3);
    address providerA = address(0x5);

    uint256 public historicalMinted;

    constructor(
        SettlementToken _token,
        DAOGovernor _governor,
        ProviderRegistry _providerRegistry,
        ProofOfPaymentRegistry _proofRegistry
    ) {
        token = _token;
        governor = _governor;
        providerRegistry = _providerRegistry;
        proofRegistry = _proofRegistry;
        
        vm.startPrank(admin);
        governor.grantRole(governor.DAO_MEMBER_ROLE(), daoMember1);
        governor.grantRole(governor.DAO_MEMBER_ROLE(), daoMember2);
        providerRegistry.onboardProvider(providerA, "Provider A", true);
        vm.stopPrank();
    }

    function mint(uint256 amount) public {
        amount = bound(amount, 1, 100_000_000e18);
        bytes32 proofId = bytes32(uint256(keccak256(abi.encodePacked(amount, block.timestamp))));
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

        historicalMinted += amount;
    }

    function burn(uint256 amount) public {
        uint256 balance = token.balanceOf(providerA);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        
        bytes32 payoutHash = keccak256("WireTransferDetails");

        vm.prank(providerA);
        uint256 proposalId = token.requestBurn(providerA, amount, payoutHash);

        vm.prank(daoMember1);
        governor.castVote(proposalId, true);
        vm.prank(daoMember2);
        governor.castVote(proposalId, true);

        vm.prank(providerA);
        token.executeBurn(proposalId);
    }
}

contract InvariantTest is Test {
    SettlementToken token;
    DAOGovernor governor;
    ProviderRegistry providerRegistry;
    ProofOfPaymentRegistry proofRegistry;
    Handler handler;

    function setUp() public {
        address admin = address(0x1);
        vm.startPrank(admin);
        providerRegistry = new ProviderRegistry();
        proofRegistry = new ProofOfPaymentRegistry();
        governor = new DAOGovernor(2, 86400);
        token = new SettlementToken(address(governor), address(providerRegistry), address(proofRegistry));
        
        governor.grantRole(governor.TOKEN_ROLE(), address(token));
        proofRegistry.grantRole(proofRegistry.RELAYER_ROLE(), address(token));
        vm.stopPrank();

        handler = new Handler(token, governor, providerRegistry, proofRegistry);
        targetContract(address(handler));
    }

    function invariant_SupplyAccounting() public view {
        // Enforce the core invariant: historicalMinted - totalBurned == totalSupply
        assertEq(handler.historicalMinted() - token.totalBurned(), token.totalSupply());
    }
}
