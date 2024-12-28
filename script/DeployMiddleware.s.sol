// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/Test.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {CoreDeploymentLib} from "./utils/CoreDeploymentLib.sol";
import {MiddlewareDeploymentLib} from "./utils/MiddlewareDeploymentLib.sol";
import {OperatorLib} from "./utils/OperatorLib.sol";

contract DeployMiddleware is Script {
    CoreDeploymentLib.DeploymentData internal core;
    MiddlewareDeploymentLib.ConfigData internal config;
    MiddlewareDeploymentLib.DeploymentData internal middlewareDeployment;
    address internal deployer;

    function setUp() public {
        deployer = vm.rememberKey(vm.envUint("HOLESKY_PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        // Read core deployment data from json
        core = CoreDeploymentLib.readCoreDeploymentJson("./script/config", 17000, "preprod");

        config.admin = deployer;
        config.numQuorums = 1;
        config.numStrategies = 2;

        uint256[] memory operatorParams = new uint256[](3);
        operatorParams[0] = 10000; // maxOperatorCount for quorum 0
        operatorParams[1] = 2000;  // kickBIPsOfOperatorStake for quorum 0 (20%)
        operatorParams[2] = 500;   // kickBIPsOfTotalStake for quorum 0 (5%)
        // operatorParams[3] = 10000; // maxOperatorCount for quorum 1
        // operatorParams[4] = 2000;  // kickBIPsOfOperatorStake for quorum 1 (20%)
        // operatorParams[5] = 500;   // kickBIPsOfTotalStake for quorum 1 (5%)
        config.operatorParams = operatorParams;

        config.numOperators = new uint256[](1);
        config.numOperators[0] = 20;
    }

    function run() external {
        vm.startBroadcast(deployer);

        /// TODO: Pass proxy admin instead of config
        config.proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
        middlewareDeployment = MiddlewareDeploymentLib.deployContracts(core, config);

        labelContracts(core, middlewareDeployment);

        MiddlewareDeploymentLib.upgradeContracts(middlewareDeployment, config, core);

        logDeploymentDetails(middlewareDeployment);

        OperatorLib.Operator[][] memory operators = OperatorLib.createOperators(core, config, middlewareDeployment, deployer);

        OperatorLib.registerOperatorsToOperatorSets(core, config, middlewareDeployment, operators);

        // log all operators
        logAllOperators(operators);

        vm.stopBroadcast();        
    }

    function logDeploymentDetails(MiddlewareDeploymentLib.DeploymentData memory result) internal pure {
        console.log("Deployment completed");
        console.log("ServiceManager:", result.serviceManager);
        console.log("RegistryCoordinator:", result.registryCoordinator);
        console.log("BLSApkRegistry:", result.blsapkRegistry);
        console.log("IndexRegistry:", result.indexRegistry);
        console.log("StakeRegistry:", result.stakeRegistry);
        console.log("OperatorStateRetriever:", result.operatorStateRetriever);

        for (uint256 i = 0; i < result.strategies.length; i++) {
            console.log("Token:", address(result.tokens[i]));
            console.log("Strategy:", address(result.strategies[i]));
        }
    }

    function labelContracts(CoreDeploymentLib.DeploymentData memory coreData, MiddlewareDeploymentLib.DeploymentData memory middlewareData) internal {
        // Label core contracts
        vm.label(coreData.delegationManager, "DelegationManager");
        vm.label(coreData.avsDirectory, "AVSDirectory");
        vm.label(coreData.strategyManager, "StrategyManager");
        vm.label(coreData.eigenPodManager, "EigenPodManager");
        vm.label(coreData.rewardsCoordinator, "RewardsCoordinator");
        vm.label(coreData.eigenPodBeacon, "EigenPodBeacon");
        vm.label(coreData.pauserRegistry, "PauserRegistry");
        vm.label(coreData.strategyFactory, "StrategyFactory");
        vm.label(coreData.strategyBeacon, "StrategyBeacon");

        // Label middleware contracts
        vm.label(middlewareData.registryCoordinator, "RegistryCoordinator");
        vm.label(middlewareData.serviceManager, "ServiceManager");
        vm.label(middlewareData.operatorStateRetriever, "OperatorStateRetriever");
        vm.label(middlewareData.blsapkRegistry, "BLSApkRegistry");
        vm.label(middlewareData.indexRegistry, "IndexRegistry");
        vm.label(middlewareData.stakeRegistry, "StakeRegistry");
        for (uint256 i = 0; i < middlewareData.strategies.length; i++) {
            vm.label(address(middlewareData.strategies[i]), "Strategy");
            vm.label(address(middlewareData.tokens[i]), "Token");
        }
        vm.label(middlewareData.pauserRegistry, "PauserRegistry");
    }

    function logAllOperators(OperatorLib.Operator[][] memory operators) internal pure {
        for (uint256 i = 0; i < operators.length; i++) {
            for (uint256 j = 0; j < operators[i].length; j++) {
                console.log("Operator:", operators[i][j].addr);
            }
        }
    }
}
