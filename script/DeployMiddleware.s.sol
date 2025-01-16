// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/Test.sol";
import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {CoreDeploymentLib} from "./utils/CoreDeploymentLib.sol";
import {MiddlewareDeploymentLib} from "./utils/MiddlewareDeploymentLib.sol";

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

        uint256[] memory operatorParams = new uint256[](6);
        operatorParams[0] = 10000; // maxOperatorCount for quorum 0
        operatorParams[1] = 2000;  // kickBIPsOfOperatorStake for quorum 0 (20%)
        operatorParams[2] = 500;   // kickBIPsOfTotalStake for quorum 0 (5%)
        operatorParams[3] = 10000; // maxOperatorCount for quorum 1
        operatorParams[4] = 2000;  // kickBIPsOfOperatorStake for quorum 1 (20%)
        operatorParams[5] = 500;   // kickBIPsOfTotalStake for quorum 1 (5%)
        config.operatorParams = operatorParams;
    }

    function run() external {
        vm.startBroadcast(deployer);

        address proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
        middlewareDeployment = MiddlewareDeploymentLib.deployContracts(proxyAdmin, core, config);

        labelContracts(core, middlewareDeployment);

        MiddlewareDeploymentLib.upgradeContracts(middlewareDeployment, config, core);

        logDeploymentDetails(middlewareDeployment);

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
        console.log("Token:", result.token);
        console.log("Strategy:", result.strategy);
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
            vm.label(middlewareData.strategy, "Strategy");
            vm.label(middlewareData.token, "Token");
            vm.label(middlewareData.pauserRegistry, "PauserRegistry");
        }
}
