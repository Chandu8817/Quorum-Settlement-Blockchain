// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/SettlementToken.sol";
import "../contracts/DAOGovernor.sol";
import "../contracts/ProviderRegistry.sol";
import "../contracts/ProofOfPaymentRegistry.sol";

contract DeployV2 is Script {
    function run() external {
        // Read deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Read DAO config from environment
        uint256 quorumThreshold = vm.envOr("QUORUM_THRESHOLD", uint256(3));
        uint256 votingPeriod = vm.envOr("VOTING_PERIOD", uint256(86400));

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying V2 Settlement Layer Contracts...");
        console.log("Deployer:", deployerAddress);

        // 1. Deploy Registries
        ProviderRegistry providerRegistry = new ProviderRegistry();
        console.log("ProviderRegistry deployed at:", address(providerRegistry));

        ProofOfPaymentRegistry proofRegistry = new ProofOfPaymentRegistry();
        console.log("ProofOfPaymentRegistry deployed at:", address(proofRegistry));

        // 2. Deploy Governor
        DAOGovernor governor = new DAOGovernor(quorumThreshold, votingPeriod);
        console.log("DAOGovernor deployed at:", address(governor));

        // 3. Deploy Token
        SettlementToken token = new SettlementToken(
            address(governor),
            address(providerRegistry),
            address(proofRegistry)
        );
        console.log("SettlementToken deployed at:", address(token));

        // 4. Wire up permissions
        console.log("Granting TOKEN_ROLE to SettlementToken on DAOGovernor...");
        governor.grantRole(governor.TOKEN_ROLE(), address(token));

        console.log("Granting RELAYER_ROLE to SettlementToken on ProofOfPaymentRegistry...");
        proofRegistry.grantRole(proofRegistry.RELAYER_ROLE(), address(token));

        // The deployer will need to manually grant DAO_MEMBER_ROLE to the initial bootstrap members.
        console.log("Deployment complete. Ensure you bootstrap DAO_MEMBER_ROLE via script or CLI before onboarding providers.");

        vm.stopBroadcast();
    }
}
