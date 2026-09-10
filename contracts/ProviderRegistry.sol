// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ProviderRegistry
 * @notice Manages onboarded permissioned providers (payment gateways/firms).
 */
contract ProviderRegistry is AccessControl {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    struct Provider {
        bool isRegistered;
        bool kycApproved;
        address wallet;
        string name;
    }

    mapping(address => Provider) public providers;

    event ProviderOnboarded(address indexed wallet, string name);
    event ProviderOffboarded(address indexed wallet);
    event KYCStatusUpdated(address indexed wallet, bool status);

    error NotOwner();
    error ProviderAlreadyRegistered();
    error ProviderNotRegistered();

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
    }

    modifier onlyOwner() {
        if (!hasRole(OWNER_ROLE, msg.sender)) revert NotOwner();
        _;
    }

    function onboardProvider(address _wallet, string calldata _name, bool _kycApproved) external onlyOwner {
        if (providers[_wallet].isRegistered) revert ProviderAlreadyRegistered();

        providers[_wallet] = Provider({
            isRegistered: true,
            kycApproved: _kycApproved,
            wallet: _wallet,
            name: _name
        });

        emit ProviderOnboarded(_wallet, _name);
        if (_kycApproved) {
            emit KYCStatusUpdated(_wallet, true);
        }
    }

    function offboardProvider(address _wallet) external onlyOwner {
        if (!providers[_wallet].isRegistered) revert ProviderNotRegistered();

        providers[_wallet].isRegistered = false;
        providers[_wallet].kycApproved = false;

        emit ProviderOffboarded(_wallet);
    }

    function updateKYCStatus(address _wallet, bool _kycApproved) external onlyOwner {
        if (!providers[_wallet].isRegistered) revert ProviderNotRegistered();
        
        providers[_wallet].kycApproved = _kycApproved;
        emit KYCStatusUpdated(_wallet, _kycApproved);
    }

    function isProviderApproved(address _wallet) external view returns (bool) {
        Provider memory p = providers[_wallet];
        return p.isRegistered && p.kycApproved;
    }
}
