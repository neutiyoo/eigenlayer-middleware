// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/Test.sol";
import {UpgradeableProxyLib} from "./UpgradeableProxyLib.sol";
import {CoreDeploymentLib} from "./CoreDeploymentLib.sol";
import {MiddlewareDeploymentLib} from "./MiddlewareDeploymentLib.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract MiddlewareUpgrade is Script {
    using stdJson for string;

    CoreDeploymentLib.DeploymentData internal core;
    MiddlewareDeploymentLib.DeploymentData internal middlewareDeployment;
    address internal deployer;

    function setUp() public {
        deployer = vm.rememberKey(vm.envUint("HOLESKY_PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        // Read core deployment data from json
        core = CoreDeploymentLib.readCoreDeploymentJson("./script/config", 17000, "preprod");

        // Read existing middleware deployment from json
        middlewareDeployment = MiddlewareDeploymentLib.readDeploymentJson("./script/deployments", 17000, "preprod");

    }

    function run() external {
        vm.startBroadcast(deployer);

        // Upgrade contracts
        MiddlewareDeploymentLib.upgradeContracts(middlewareDeployment, core);

        // Write updated deployment info to json
        string memory deploymentJson = generateDeploymentJson();
        vm.writeFile(string(abi.encodePacked("./script/deployments/", vm.toString(uint256(17000)), "-preprod.json")), deploymentJson);

        logDeploymentDetails(middlewareDeployment);

        vm.stopBroadcast();
    }

    function generateDeploymentJson() internal view returns (string memory) {
        return string.concat(
            "{",
            string.concat(
                '"serviceManager":"', vm.toString(middlewareDeployment.serviceManager), '",',
                '"registryCoordinator":"', vm.toString(middlewareDeployment.registryCoordinator), '",',
                '"blsapkRegistry":"', vm.toString(middlewareDeployment.blsapkRegistry), '",',
                '"indexRegistry":"', vm.toString(middlewareDeployment.indexRegistry), '",',
                '"stakeRegistry":"', vm.toString(middlewareDeployment.stakeRegistry), '",',
                '"operatorStateRetriever":"', vm.toString(middlewareDeployment.operatorStateRetriever), '",',
                '"token":"', vm.toString(middlewareDeployment.token), '",',
                '"strategy":"', vm.toString(middlewareDeployment.strategy), '"'
            ),
            "}"
        );
    }

    function logDeploymentDetails(MiddlewareDeploymentLib.DeploymentData memory result) internal pure {
        console.log("Upgrade completed");
        console.log("ServiceManager:", result.serviceManager);
        console.log("RegistryCoordinator:", result.registryCoordinator);
        console.log("BLSApkRegistry:", result.blsapkRegistry);
        console.log("IndexRegistry:", result.indexRegistry);
        console.log("StakeRegistry:", result.stakeRegistry);
        console.log("OperatorStateRetriever:", result.operatorStateRetriever);
        console.log("Token:", result.token);
        console.log("Strategy:", result.strategy);
    }
}
