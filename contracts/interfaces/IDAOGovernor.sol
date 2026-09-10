// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDAOGovernor
 * @notice Interface for the lightweight DAO Governor managing proposals for the settlement network.
 */
interface IDAOGovernor {
    enum ProposalType { DEPOSIT, WITHDRAWAL, INTERNAL_TRANSFER }
    enum ProposalState { PENDING, APPROVED, REJECTED, EXECUTED, EXPIRED }

    struct Proposal {
        uint256 id;
        ProposalType proposalType;
        address targetProvider;
        uint256 amount;
        bytes32 payloadHash;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
        uint256 expiry;
        ProposalState state;
    }

    function createProposal(
        ProposalType _type,
        address _targetProvider,
        uint256 _amount,
        bytes32 _payloadHash
    ) external returns (uint256);

    function castVote(uint256 _proposalId, bool _support) external;

    function executeProposal(uint256 _proposalId) external;

    function getProposal(uint256 _proposalId) external view returns (Proposal memory);
    
    function getProposalState(uint256 _proposalId) external view returns (ProposalState);
}
