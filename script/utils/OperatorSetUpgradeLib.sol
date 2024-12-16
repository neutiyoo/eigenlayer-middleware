// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// Deploy L2AVS proxy

import {CoreDeploymentLib} from "./CoreDeploymentLib.sol";
import {MiddlewareDeploymentLib} from "./MiddlewareDeploymentLib.sol";

import {StakeRegistry} from "../../src/StakeRegistry.sol";
import {BLSApkRegistry} from "../../src/BLSApkRegistry.sol";
import {IndexRegistry} from "../../src/IndexRegistry.sol";
import {RegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";


library SlashingUpgradeLib {
    using CoreDeploymentLib for string;

    function parseCoreDeploymentJson(string memory path, uint256 chainId) internal returns (CoreDeploymentLib.DeploymentData memory) {
        return CoreDeploymentLib.readCoreDeploymentJson(path, chainId);
    }

    function parseCoreDeploymentJson(string memory path, uint256 chainId, string memory environment) internal returns (CoreDeploymentLib.DeploymentData memory) {
        return CoreDeploymentLib.readCoreDeploymentJson(path, chainId, environment);
    }

    function deployNewImplementations(
        CoreDeploymentLib.DeploymentData memory core,
        MiddlewareDeploymentLib.DeploymentData memory deployment
    ) internal {
        address stakeRegistryImpl = address(
            new StakeRegistry(
                IRegistryCoordinator(deployment.registryCoordinator),
                IDelegationManager(core.delegationManager),
                IAVSDirectory(core.avsDirectory),
                IServiceManager(deployment.serviceManager)
            )
        );

        address blsApkRegistryImpl = address(new BLSApkRegistry(IRegistryCoordinator(deployment.registryCoordinator)));
        address indexRegistryImpl = address(new IndexRegistry(IRegistryCoordinator(deployment.registryCoordinator)));
        address registryCoordinatorImpl = address(
            new RegistryCoordinator(
                IServiceManager(deployment.serviceManager),
                IStakeRegistry(deployment.stakeRegistry),
                IBLSApkRegistry(deployment.blsapkRegistry),
                IIndexRegistry(deployment.indexRegistry),
                IAVSDirectory(core.avsDirectory),
                IPauserRegistry(deployment.pauserRegistry)
            )
        );
    }
}