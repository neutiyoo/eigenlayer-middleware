// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Test, console2 as console} from "forge-std/Test.sol";
import {CoreDeploymentLib } from "../../script/utils/CoreDeploymentLib.sol";

contract ZeusDeploymentTests is Test {
    using CoreDeploymentLib for string;

    function testParseZeusJson() public {
        string memory path = "script/config";
        uint256 chainId = 17000;
        string memory environment = "preprod";

        CoreDeploymentLib.DeploymentData memory deploymentData = CoreDeploymentLib.readCoreDeploymentJson(path, chainId, environment);

        assertEq(deploymentData.delegationManager, 0x75dfE5B44C2E530568001400D3f704bC8AE350CC);
        assertEq(deploymentData.avsDirectory, 0x141d6995556135D4997b2ff72EB443Be300353bC);
        assertEq(deploymentData.allocationManager, 0xFdD5749e11977D60850E06bF5B13221Ad95eb6B4);
        assertEq(deploymentData.strategyManager, 0xF9fbF2e35D8803273E214c99BF15174139f4E67a);
        assertEq(deploymentData.eigenPodManager, 0xB8d8952f572e67B11e43bC21250967772fa883Ff);
        assertEq(deploymentData.rewardsCoordinator, 0xb22Ef643e1E067c994019A4C19e403253C05c2B0);
        assertEq(deploymentData.eigenPodBeacon, 0x92Cc4a800A1513E85C481dDDf3A06C6921211eaC);
        assertEq(deploymentData.pauserRegistry, 0x50712285cE831a6B9a11214A430f28999A5b4DAe);
        assertEq(deploymentData.strategyFactory, 0xad4A89E3cA9b3dc25AABe0aa7d72E61D2Ec66052);
        assertEq(deploymentData.strategyBeacon, 0xf2c2AcA859C685895E60ca7A14274365b64c0c2a);
        assertEq(deploymentData.eigenStrategy, 0x4e0125f8a928Eb1b9dB4BeDd3756BA3c200563C2);
        assertEq(deploymentData.eigen, 0xD58f6844f79eB1fbd9f7091d05f7cb30d3363926);
        assertEq(deploymentData.backingEigen, 0xA72942289a043874249E60469F68f08B8c6ECCe8);
        assertEq(deploymentData.permissionController, 0xa2348c77802238Db39f0CefAa500B62D3FDD682b);
    }
}
