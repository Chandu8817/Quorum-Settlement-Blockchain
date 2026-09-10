// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISettlementToken
 * @notice Interface for the DAO-gated settlement token.
 */
interface ISettlementToken {
    function requestMint(address _providerId, uint256 _amount, bytes32 _proofOfPaymentId) external returns (uint256 proposalId);
    
    function executeMint(uint256 _proposalId) external;
    
    function requestBurn(address _providerId, uint256 _amount, bytes32 _payoutInstructionHash) external returns (uint256 proposalId);
    
    function executeBurn(uint256 _proposalId) external;
    
    function requestInternalTransfer(address _fromProvider, address _toProvider, uint256 _amount) external returns (uint256 proposalId);
    
    function executeInternalTransfer(uint256 _proposalId, address _toProvider) external;
}
