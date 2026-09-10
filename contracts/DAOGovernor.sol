// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IDAOGovernor.sol";

/**
 * @title DAOGovernor
 * @notice Lightweight DAOGovernor managing proposals for mint/burn/transfers.
 */
contract DAOGovernor is AccessControl, IDAOGovernor {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant DAO_MEMBER_ROLE = keccak256("DAO_MEMBER_ROLE");
    bytes32 public constant TOKEN_ROLE = keccak256("TOKEN_ROLE"); // Settlement token can execute proposals

    uint256 public proposalCount;
    uint256 public quorumThreshold;
    uint256 public votingPeriod; // in seconds

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed id, ProposalType proposalType, address targetProvider, uint256 amount, bytes32 payloadHash, uint256 expiry);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId);
    event QuorumThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    error NotOwner();
    error NotDAOMember();
    error NotToken();
    error ProposalDoesNotExist();
    error ProposalNotActive();
    error AlreadyVoted();
    error QuorumNotReached();
    error ProposalAlreadyExecuted();

    constructor(uint256 _quorumThreshold, uint256 _votingPeriod) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        quorumThreshold = _quorumThreshold;
        votingPeriod = _votingPeriod;
    }

    modifier onlyOwner() {
        if (!hasRole(OWNER_ROLE, msg.sender)) revert NotOwner();
        _;
    }

    modifier onlyDAOMember() {
        if (!hasRole(DAO_MEMBER_ROLE, msg.sender)) revert NotDAOMember();
        _;
    }

    function setQuorumThreshold(uint256 _newThreshold) external onlyOwner {
        uint256 oldThreshold = quorumThreshold;
        quorumThreshold = _newThreshold;
        emit QuorumThresholdUpdated(oldThreshold, _newThreshold);
    }

    function createProposal(
        ProposalType _type,
        address _targetProvider,
        uint256 _amount,
        bytes32 _payloadHash
    ) external returns (uint256) {
        // Typically called by the token contract or a relayer
        uint256 id = ++proposalCount;
        uint256 expiry = block.timestamp + votingPeriod;

        proposals[id] = Proposal({
            id: id,
            proposalType: _type,
            targetProvider: _targetProvider,
            amount: _amount,
            payloadHash: _payloadHash,
            votesFor: 0,
            votesAgainst: 0,
            executed: false,
            expiry: expiry,
            state: ProposalState.PENDING
        });

        emit ProposalCreated(id, _type, _targetProvider, _amount, _payloadHash, expiry);
        return id;
    }

    function castVote(uint256 _proposalId, bool _support) external onlyDAOMember {
        Proposal storage proposal = proposals[_proposalId];
        
        if (proposal.id == 0) revert ProposalDoesNotExist();
        if (block.timestamp > proposal.expiry) {
            proposal.state = ProposalState.EXPIRED;
            revert ProposalNotActive();
        }
        if (proposal.state != ProposalState.PENDING) revert ProposalNotActive();
        if (hasVoted[_proposalId][msg.sender]) revert AlreadyVoted();

        hasVoted[_proposalId][msg.sender] = true;

        if (_support) {
            proposal.votesFor += 1;
        } else {
            proposal.votesAgainst += 1;
        }

        // Auto-approve if quorum reached
        if (proposal.votesFor >= quorumThreshold) {
            proposal.state = ProposalState.APPROVED;
        } else if (proposal.votesAgainst >= quorumThreshold) {
            proposal.state = ProposalState.REJECTED;
        }

        emit VoteCast(_proposalId, msg.sender, _support);
    }

    function executeProposal(uint256 _proposalId) external {
        if (!hasRole(TOKEN_ROLE, msg.sender) && !hasRole(DAO_MEMBER_ROLE, msg.sender)) revert NotToken();
        
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.id == 0) revert ProposalDoesNotExist();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        
        // Ensure state is updated if voting period passed
        if (block.timestamp > proposal.expiry && proposal.state == ProposalState.PENDING) {
            proposal.state = ProposalState.EXPIRED;
        }

        if (proposal.state != ProposalState.APPROVED) revert QuorumNotReached();

        proposal.executed = true;
        proposal.state = ProposalState.EXECUTED;

        emit ProposalExecuted(_proposalId);
    }

    function getProposal(uint256 _proposalId) external view returns (Proposal memory) {
        return proposals[_proposalId];
    }
    
    function getProposalState(uint256 _proposalId) external view returns (ProposalState) {
        Proposal storage p = proposals[_proposalId];
        if (p.id == 0) return ProposalState.PENDING; // or revert
        if (p.state == ProposalState.PENDING && block.timestamp > p.expiry) {
            return ProposalState.EXPIRED;
        }
        return p.state;
    }
}
