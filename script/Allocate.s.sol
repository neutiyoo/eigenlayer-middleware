// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/Test.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {CoreDeploymentLib} from "./utils/CoreDeploymentLib.sol";
import {MiddlewareDeploymentLib} from "./utils/MiddlewareDeploymentLib.sol";
import {OperatorLib} from "./utils/OperatorLib.sol";

contract DeployMiddleware is Script {
    CoreDeploymentLib.DeploymentData internal core;
    MiddlewareDeploymentLib.DeploymentData internal middlewareDeployment;
    OperatorLib.Operator[][] internal operators;
    address internal deployer;

    function setUp() public {
        deployer = vm.rememberKey(vm.envUint("HOLESKY_PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        // Read core deployment data from json
        core = CoreDeploymentLib.readCoreDeploymentJson("./script/config", 17000, "preprod");

//   ServiceManager: 0xF9084C9CB42171750d2FE0260DE4f0F0320458F6
// Token: 0x3815E3Ad9e4D00582bc5270Df58B03ab1C23395b
//   Strategy: 0x213107C40edCF04D7f22B599Ea3b762Cff900442
//   Token: 0x06FEC949BfCd568C791c514665b591ed54fEA76f
//   Strategy: 0x13c516FE2b077C30F249223d9693E7DC1de7af9d
//   Operator: 0x79EA1018ae7FF5DE610594f4a57d0DaB7b60Fc54
//   Operator: 0x3e14293Aa31CF0839442A65063D734fa5aD23193
//   Operator: 0xadf99D47140a79c9474e4c8035e08528a56709D7
//   Operator: 0x21e122e51f32D1F8dD5c730c44dB7Ce8AFeFf254
//   Operator: 0xF09f2E059c466fBfc5e4Bc43100FC2A741B8Adb9
//   Operator: 0x10Bd6d89bdF2d2534C0b11Eb14C2D6d6cE76D401
//   Operator: 0x107a61b41946555408935a33BdB8028f299569a0
//   Operator: 0xe44A2ea8A7E193961A4A5e79166Df8C17EF15371
//   Operator: 0xe804E25058713072fAf2a78d53535a1fF2F2F3a8
//   Operator: 0x4a80e28175957Ebd624eA56EE1Bf71A67Fe1D5dE
//   Operator: 0x144f94F38f5Dc4ddFA06BFC2e10A44f020767F7a
//   Operator: 0xdf36a12a5228d7e5849efd752B5bc63252C99290
//   Operator: 0x1a16dAEe423bFCd0F57f1DAaBD6458751F57e14d
//   Operator: 0x12A342dC2Cd505881690957B80c817e4769655Dd
//   Operator: 0x0a8261b0Ffec30A2e70B67D38efa4c5bdab62608
//   Operator: 0xf746c3034cA25B1C207671dAB8545226346Eb439
//   Operator: 0xd0D3e98470dA38cf6fE4C7eD07884f16aB3DD470
//   Operator: 0xD709b9D37cAEc3e016bE9Ad71D1A85163f727a9A
//   Operator: 0x7Bc44028B83904b57FE8417dE9b02D06C352823c
//   Operator: 0xa16B955216092523Bf6B67F857b4Df9Db4B9cdBc

        middlewareDeployment.serviceManager = address(0xF9084C9CB42171750d2FE0260DE4f0F0320458F6);
        middlewareDeployment.strategies = new IStrategy[](2);
        middlewareDeployment.strategies[0] = IStrategy(0x213107C40edCF04D7f22B599Ea3b762Cff900442);
        middlewareDeployment.strategies[1] = IStrategy(0x13c516FE2b077C30F249223d9693E7DC1de7af9d);

        operators.push();
        OperatorLib.Operator memory operator;

        // Add all operators from comments
        operator.addr = address(0x79EA1018ae7FF5DE610594f4a57d0DaB7b60Fc54);
        operators[0].push(operator);
        operator.addr = address(0x3e14293Aa31CF0839442A65063D734fa5aD23193);
        operators[0].push(operator);
        operator.addr = address(0xadf99D47140a79c9474e4c8035e08528a56709D7);
        operators[0].push(operator);
        operator.addr = address(0x21e122e51f32D1F8dD5c730c44dB7Ce8AFeFf254);
        operators[0].push(operator);
        operator.addr = address(0xF09f2E059c466fBfc5e4Bc43100FC2A741B8Adb9);
        operators[0].push(operator);
        operator.addr = address(0x10Bd6d89bdF2d2534C0b11Eb14C2D6d6cE76D401);
        operators[0].push(operator);
        operator.addr = address(0x107a61b41946555408935a33BdB8028f299569a0);
        operators[0].push(operator);
        operator.addr = address(0xe44A2ea8A7E193961A4A5e79166Df8C17EF15371);
        operators[0].push(operator);
        operator.addr = address(0xe804E25058713072fAf2a78d53535a1fF2F2F3a8);
        operators[0].push(operator);
        operator.addr = address(0x4a80e28175957Ebd624eA56EE1Bf71A67Fe1D5dE);
        operators[0].push(operator);
        operator.addr = address(0x144f94F38f5Dc4ddFA06BFC2e10A44f020767F7a);
        operators[0].push(operator);
        operator.addr = address(0xdf36a12a5228d7e5849efd752B5bc63252C99290);
        operators[0].push(operator);
        operator.addr = address(0x1a16dAEe423bFCd0F57f1DAaBD6458751F57e14d);
        operators[0].push(operator);
        operator.addr = address(0x12A342dC2Cd505881690957B80c817e4769655Dd);
        operators[0].push(operator);
        operator.addr = address(0x0a8261b0Ffec30A2e70B67D38efa4c5bdab62608);
        operators[0].push(operator);
        operator.addr = address(0xf746c3034cA25B1C207671dAB8545226346Eb439);
        operators[0].push(operator);
        operator.addr = address(0xd0D3e98470dA38cf6fE4C7eD07884f16aB3DD470);
        operators[0].push(operator);
        operator.addr = address(0xD709b9D37cAEc3e016bE9Ad71D1A85163f727a9A);
        operators[0].push(operator);
        operator.addr = address(0x7Bc44028B83904b57FE8417dE9b02D06C352823c);
        operators[0].push(operator);
        operator.addr = address(0xa16B955216092523Bf6B67F857b4Df9Db4B9cdBc);
        operators[0].push(operator);

    }

    function run() external {
        vm.startBroadcast(deployer);

        OperatorLib.allocateToOperatorSets(core, middlewareDeployment, operators);

        vm.stopBroadcast();
    }

}
