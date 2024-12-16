// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Vm} from "forge-std/Vm.sol";
import {console2 as console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
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
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
import {ServiceManagerMock} from "../../test/mocks/ServiceManagerMock.sol";


import {PauserRegistry, IPauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";

import {UpgradeableProxyLib} from "./UpgradeableProxyLib.sol";
import {CoreDeploymentLib} from "./CoreDeploymentLib.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("", "") {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}

library MiddlewareDeploymentLib {
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
        address strategy;
        address token;
        address pauserRegistry;
    }

    struct ConfigData {
        address proxyAdmin;
        address admin;
        uint256 numQuorums;
        uint256[] operatorParams;
    }

    function deployContracts(
        CoreDeploymentLib.DeploymentData memory core,
        ConfigData memory config
    ) internal returns (DeploymentData memory) {
        DeploymentData memory result;
        address[] memory pausers = new address[](2);
        pausers[0] = config.admin;
        pausers[1] = config.admin;
        PauserRegistry pausercontract = new PauserRegistry(pausers, config.admin);
        result.pauserRegistry = address(pausercontract);
        result.stakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        result.registryCoordinator = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        result.blsapkRegistry = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        result.indexRegistry = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        result.serviceManager = UpgradeableProxyLib.setUpEmptyProxy(config.proxyAdmin);
        OperatorStateRetriever operatorStateRetriever = new OperatorStateRetriever();
        result.operatorStateRetriever = address(operatorStateRetriever);

        ERC20Mock token = new ERC20Mock();
        result.token = address(token);

        // Create a new strategy using the strategy factory
        IStrategyFactory strategyFactory = IStrategyFactory(core.strategyFactory);
        IStrategy strategy = strategyFactory.deployNewStrategy(IERC20(result.token));
        result.strategy = address(strategy);
        result.token = address(token);

        return result;
    }

    function upgradeContracts(
        DeploymentData memory deployment,
        ConfigData memory config,
        CoreDeploymentLib.DeploymentData memory core
    ) internal {

        address serviceManagerImpl = address(
            new ServiceManagerMock(
                IAVSDirectory(core.avsDirectory),
                IRewardsCoordinator(core.rewardsCoordinator),
                IRegistryCoordinator(deployment.registryCoordinator),
                IStakeRegistry(deployment.stakeRegistry),
                IAllocationManager(core.allocationManager)
            )
        );
        address stakeRegistryImpl = address(
            new StakeRegistry(
                IRegistryCoordinator(deployment.registryCoordinator),
                IDelegationManager(core.delegationManager),
                IAVSDirectory(core.avsDirectory),
                IServiceManager(deployment.serviceManager)
            )
        );

        address blsApkRegistryImpl = address(new BLSApkRegistry(IRegistryCoordinator(deployment.registryCoordinator)));
        address indexRegistryimpl = address(new IndexRegistry(IRegistryCoordinator(deployment.registryCoordinator)));
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

        IStrategy[1] memory deployedStrategyArray = [IStrategy(deployment.strategy)];
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

        uint96[] memory quorumsMinimumStake = new uint96[](numQuorums);
        IStakeRegistry.StrategyParams[][] memory quorumsStrategyParams =
            new IStakeRegistry.StrategyParams[][](numQuorums);
        for (uint256 i = 0; i < numQuorums; i++) {
            quorumsStrategyParams[i] = new IStakeRegistry.StrategyParams[](numStrategies);
            for (uint256 j = 0; j < numStrategies; j++) {
                quorumsStrategyParams[i][j] = IStakeRegistry.StrategyParams({
                    strategy: deployedStrategyArray[j],
                    multiplier: 1 ether
                });
            }
        }

        bytes memory registryCoordinatorUpgradeCall = abi.encodeCall(
            RegistryCoordinator.initialize,
            (
                config.admin,
                config.admin,
                config.admin,
                uint256(0),
                quorumsOperatorSetParams,
                quorumsMinimumStake,
                quorumsStrategyParams,
                new StakeType[](1),
                new uint32[](1)
            )
        );

        bytes memory serviceManagerUpgradeCall = abi.encodeCall(
            ServiceManagerMock.initialize,
            (
                config.admin,
                config.admin,
                config.admin
            )
        );

        UpgradeableProxyLib.upgradeAndCall(deployment.serviceManager, serviceManagerImpl, serviceManagerUpgradeCall);
        UpgradeableProxyLib.upgrade(deployment.stakeRegistry, stakeRegistryImpl);
        UpgradeableProxyLib.upgrade(deployment.blsapkRegistry, blsApkRegistryImpl);
        UpgradeableProxyLib.upgrade(deployment.indexRegistry, indexRegistryimpl);
        UpgradeableProxyLib.upgradeAndCall(deployment.registryCoordinator, registryCoordinatorImpl, registryCoordinatorUpgradeCall);
    }

}