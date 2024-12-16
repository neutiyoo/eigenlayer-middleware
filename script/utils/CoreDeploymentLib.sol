
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

library CoreDeploymentLib {
    using stdJson for string;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct StrategyManagerConfig {
        uint256 initPausedStatus;
        uint256 initWithdrawalDelayBlocks;
    }

    struct SlasherConfig {
        uint256 initPausedStatus;
    }

    struct DelegationManagerConfig {
        uint256 initPausedStatus;
        uint256 withdrawalDelayBlocks;
    }

    struct EigenPodManagerConfig {
        uint256 initPausedStatus;
    }

    struct RewardsCoordinatorConfig {
        uint256 initPausedStatus;
        uint256 maxRewardsDuration;
        uint256 maxRetroactiveLength;
        uint256 maxFutureLength;
        uint256 genesisRewardsTimestamp;
        address updater;
        uint256 activationDelay;
        uint256 calculationIntervalSeconds;
        uint256 globalOperatorCommissionBips;
    }

    struct StrategyFactoryConfig {
        uint256 initPausedStatus;
    }

    struct DeploymentData {
        address delegationManager;
        address avsDirectory;
        address allocationManager;
        address strategyManager;
        address eigenPodManager;
        address rewardsCoordinator;
        address eigenPodBeacon;
        address pauserRegistry;
        address strategyFactory;
        address strategyBeacon;
    }

    function readCoreDeploymentJson(string memory path, uint256 chainId) internal view returns (CoreDeploymentLib.DeploymentData memory) {
        string memory filePath = string(abi.encodePacked(path, "/", chainId, ".json"));
        return parseCoreJson(filePath);
    }

    function readCoreDeploymentJson(string memory path, uint256 chainId, string memory environment) internal view returns (CoreDeploymentLib.DeploymentData memory) {
        string memory filePath = string(abi.encodePacked(path, "/", chainId, "-", environment, ".json"));
        return parseCoreJson(filePath);
    }

    function parseCoreJson(string memory filePath) internal view returns (CoreDeploymentLib.DeploymentData memory) {
        string memory json = vm.readFile(filePath);
        CoreDeploymentLib.DeploymentData memory deploymentData;

        deploymentData.delegationManager = json.readAddress(".ZEUS_DEPLOYED_DelegationManager_Proxy");
        deploymentData.avsDirectory = json.readAddress(".ZEUS_DEPLOYED_AVSDirectory_Proxy");
        deploymentData.allocationManager = json.readAddress(".ZEUS_DEPLOYED_AllocationManager_Proxy");
        deploymentData.strategyManager = json.readAddress(".ZEUS_DEPLOYED_StrategyManager_Proxy");
        deploymentData.eigenPodManager = json.readAddress(".ZEUS_DEPLOYED_EigenPodManager_Proxy");
        deploymentData.rewardsCoordinator = json.readAddress(".ZEUS_DEPLOYED_RewardsCoordinator_Proxy");
        deploymentData.eigenPodBeacon = json.readAddress(".ZEUS_DEPLOYED_EigenPod_Beacon");
        deploymentData.pauserRegistry = json.readAddress(".ZEUS_DEPLOYED_PauserRegistry_Impl");
        deploymentData.strategyFactory = json.readAddress(".ZEUS_DEPLOYED_StrategyFactory_Proxy");
        deploymentData.strategyBeacon = json.readAddress(".ZEUS_DEPLOYED_StrategyBase_Beacon");

        return deploymentData;
    }
}