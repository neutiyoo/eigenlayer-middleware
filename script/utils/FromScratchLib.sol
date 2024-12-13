// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {UpgradeableProxyLib} from "./UpgradeableProxyLib.sol";
import {CoreDeploymentLib} from "./CoreDeploymentLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BLSApkRegistry} from "../../src/BLSApkRegistry.sol";
import {IBLSApkRegistry} from "../../src/interfaces/IBLSApkRegistry.sol";
import {IndexRegistry} from "../../src/IndexRegistry.sol";
import {IIndexRegistry} from "../../src/interfaces/IIndexRegistry.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
import {RegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {StakeRegistry} from "../../src/StakeRegistry.sol";
import {IStakeRegistry, StakeType} from "../../src/interfaces/IStakeRegistry.sol";
import {IRegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

import {PauserRegistry, IPauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";

library DeploymentLib {
    using stdJson for *;
    using Strings for *;
    using UpgradeableProxyLib for address;

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct DeploymentData {
        address registryCoordinator;
        address serviceManager;
        address operatorStateRetriever;
        address blsapkRegistry;
        address indexRegistry;
        address stakeRegistry;
        address socketRegistry;
        address strategy;
        address token;
    }

    struct ConfigData {
        address proxyAdmin;
        address admin;
        uint256 numQuorums;
        uint256[] operatorParams;
    }

    function deployContracts(
        ConfigData memory config
    ) internal returns (DeploymentData memory) {
        /// read EL deployment address
        CoreDeploymentLib.DeploymentData memory core =
            CoreDeploymentLib.readCoreDeploymentJson("script/deployments/core/", block.chainid);

        DeploymentData memory result;
        // First, deploy upgradeable proxy contracts that will point to the implementations.
        result.stakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        result.registryCoordinator = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        result.blsapkRegistry = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        result.indexRegistry = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        result.socketRegistry = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        OperatorStateRetriever operatorStateRetriever = new OperatorStateRetriever();
        /// TODO: Create strategy
        // result.strategy = strategy;
        result.operatorStateRetriever = address(operatorStateRetriever);
        // Deploy the implementation contracts, using the proxy contracts as inputs
        address stakeRegistryImpl = address(
            new StakeRegistry(
                IRegistryCoordinator(result.registryCoordinator),
                IDelegationManager(core.delegationManager),
                IAVSDirectory(core.avsDirectory),
                IServiceManager(result.serviceManager)
            )
        );

        address[] memory pausers = new address[](2);
        pausers[0] = config.admin;
        pausers[1] = config.admin;
        PauserRegistry pausercontract = new PauserRegistry(pausers, config.admin);

        address blsApkRegistryImpl = address(new BLSApkRegistry(IRegistryCoordinator(result.registryCoordinator)));
        address indexRegistryimpl = address(new IndexRegistry(IRegistryCoordinator(result.registryCoordinator)));
        address registryCoordinatorImpl = address(
            new RegistryCoordinator(
                IServiceManager(result.serviceManager),
                IStakeRegistry(result.stakeRegistry),
                IBLSApkRegistry(result.blsapkRegistry),
                IIndexRegistry(result.indexRegistry),
                IAVSDirectory(core.avsDirectory),
                IPauserRegistry(pausercontract)
            )
        );



        IStrategy[1] memory deployedStrategyArray = [IStrategy(result.strategy)];
        uint256 numStrategies = deployedStrategyArray.length;

        uint256 numQuorums = config.numQuorums;
        IRegistryCoordinator.OperatorSetParam[] memory quorumsOperatorSetParams =
            new IRegistryCoordinator.OperatorSetParam[](numQuorums);
        uint256[] memory operator_params = config.operatorParams;

        for (uint256 i = 0; i < numQuorums; i++) {
            quorumsOperatorSetParams[i] = IRegistryCoordinator.OperatorSetParam({
                maxOperatorCount: uint32(operator_params[i]),
                kickBIPsOfOperatorStake: uint16(operator_params[i + 1]),
                kickBIPsOfTotalStake: uint16(operator_params[i + 2])
            });
        }
        // set to 0 for every quorum
        uint96[] memory quorumsMinimumStake = new uint96[](numQuorums);
        IStakeRegistry.StrategyParams[][] memory quorumsStrategyParams =
            new IStakeRegistry.StrategyParams[][](numQuorums);
        for (uint256 i = 0; i < numQuorums; i++) {
            quorumsStrategyParams[i] = new IStakeRegistry.StrategyParams[](numStrategies);
            for (uint256 j = 0; j < numStrategies; j++) {
                quorumsStrategyParams[i][j] = IStakeRegistry.StrategyParams({
                    strategy: deployedStrategyArray[j],
                    // setting this to 1 ether since the divisor is also 1 ether
                    // therefore this allows an operator to register with even just 1 token
                    // see https://github.com/Layr-Labs/eigenlayer-middleware/blob/m2-mainnet/src/StakeRegistry.sol#L484
                    //    weight += uint96(sharesAmount * strategyAndMultiplier.multiplier / WEIGHTING_DIVISOR);
                    multiplier: 1 ether
                });
            }
        }

        bytes memory upgradeCall = abi.encodeCall(
            RegistryCoordinator.initialize,
            (
                config.admin,
                config.admin,
                config.admin,
                uint256(0),
                quorumsOperatorSetParams,
                quorumsMinimumStake,
                quorumsStrategyParams,
                new StakeType[](0),
                new uint32[](0)
            )
        );

        UpgradeableProxyLib.upgrade(result.stakeRegistry, stakeRegistryImpl);
        UpgradeableProxyLib.upgrade(result.blsapkRegistry, blsApkRegistryImpl);
        UpgradeableProxyLib.upgrade(result.indexRegistry, indexRegistryimpl);
        UpgradeableProxyLib.upgradeAndCall(result.registryCoordinator, registryCoordinatorImpl, upgradeCall);

        return result;
    }

}