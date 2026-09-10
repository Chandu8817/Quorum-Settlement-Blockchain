// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ProofOfPaymentRegistry
 * @notice Stores references to off-chain bank deposits (hash + timestamp).
 */
contract ProofOfPaymentRegistry is AccessControl {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    struct Proof {
        bytes32 documentHash;
        address submitter;
        uint256 timestamp;
        bool isUsed;
        uint256 linkedProposalId;
    }

    // Mapping from a unique reference ID (e.g. bank transaction reference) to its Proof
    mapping(bytes32 => Proof) public proofs;

    event ProofSubmitted(bytes32 indexed referenceId, bytes32 documentHash, address submitter);
    event ProofLinked(bytes32 indexed referenceId, uint256 proposalId);

    error NotAuthorized();
    error ProofAlreadyExists();
    error ProofDoesNotExist();
    error ProofAlreadyUsed();

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(RELAYER_ROLE, msg.sender); // Relayers or admins can submit proofs
    }

    modifier onlyAuthorized() {
        if (!hasRole(OWNER_ROLE, msg.sender) && !hasRole(RELAYER_ROLE, msg.sender)) revert NotAuthorized();
        _;
    }

    function submitProof(bytes32 _referenceId, bytes32 _documentHash) external onlyAuthorized {
        if (proofs[_referenceId].timestamp != 0) revert ProofAlreadyExists();

        proofs[_referenceId] = Proof({
            documentHash: _documentHash,
            submitter: msg.sender,
            timestamp: block.timestamp,
            isUsed: false,
            linkedProposalId: 0
        });

        emit ProofSubmitted(_referenceId, _documentHash, msg.sender);
    }

    function linkProofToProposal(bytes32 _referenceId, uint256 _proposalId) external onlyAuthorized {
        if (proofs[_referenceId].timestamp == 0) revert ProofDoesNotExist();
        if (proofs[_referenceId].isUsed) revert ProofAlreadyUsed();

        proofs[_referenceId].isUsed = true;
        proofs[_referenceId].linkedProposalId = _proposalId;

        emit ProofLinked(_referenceId, _proposalId);
    }
    
    function isProofValid(bytes32 _referenceId) external view returns (bool) {
        return proofs[_referenceId].timestamp != 0 && !proofs[_referenceId].isUsed;
    }
}
