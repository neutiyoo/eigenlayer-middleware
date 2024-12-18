// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2 as console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {OperatorLib} from "../../script/utils/OperatorLib.sol";
import {CoreDeploymentLib} from "../../script/utils/CoreDeploymentLib.sol";
import {UpgradeableProxyLib} from "../../script/utils/UpgradeableProxyLib.sol";
import {MiddlewareDeploymentLib} from "../../script/utils/MiddlewareDeploymentLib.sol";
import {BN254} from "../../src/libraries/BN254.sol";
import {IDelegationManager} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAllocationManagerTypes} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategy} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IServiceManager} from "../../src/interfaces/IServiceManager.sol";
import {IStakeRegistry, StakeType} from "../../src/interfaces/IStakeRegistry.sol";
import {RegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {IRegistryCoordinator} from "../../src/interfaces/IRegistryCoordinator.sol";
import { OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";


contract OperatorLibTest is Test {
    using OperatorLib for *;

    function testCreateOperator() public {
        OperatorLib.Operator memory operator = OperatorLib.createOperator("operator-1");

        assertTrue(operator.key.addr != address(0), "VM wallet address should be non-zero");

        assertTrue(operator.signingKey.privateKey != 0, "BLS private key should be non-zero");

        assertTrue(operator.signingKey.publicKeyG1.X != 0 || operator.signingKey.publicKeyG1.X != 0, "BLS public key G1 X should be non-zero");
        assertTrue(operator.signingKey.publicKeyG1.Y != 0 || operator.signingKey.publicKeyG1.Y!= 0, "BLS public key G1 Y should be non-zero");

        assertTrue(operator.signingKey.publicKeyG2.X[0] != 0 || operator.signingKey.publicKeyG2.X[1] != 0, "BLS public key G2 X should be non-zero");
        assertTrue(operator.signingKey.publicKeyG2.Y[0] != 0 || operator.signingKey.publicKeyG2.Y[1] != 0, "BLS public key G2 Y should be non-zero");
    }

    function testSignAndVerifyMessage() public {
        OperatorLib.Operator memory operator = OperatorLib.createOperator("operator-1");

        bytes32 messageHash = keccak256(abi.encodePacked("Test message"));
        BN254.G1Point memory signature = OperatorLib.signMessageWithOperator(operator, messageHash);
        BN254.G1Point memory messagePoint = BN254.hashToG1(messageHash);

        bool isValid = BN254.pairing(
            BN254.negate(signature),
            BN254.generatorG2(),
            messagePoint,
            operator.signingKey.publicKeyG2
        );
        assertTrue(isValid, "Signature should be valid");
    }

    function testEndToEndSetup() public {
        // Fork Holesky testnet
        string memory rpcUrl = vm.envString("HOLESKY_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Create 5 operators
        OperatorLib.Operator[] memory operators = new OperatorLib.Operator[](5);
        for (uint256 i = 0; i < 5; i++) {
            operators[i] = OperatorLib.createOperator(string(abi.encodePacked("operator-", i + 100)));
        }

        // Read core deployment data from json
        CoreDeploymentLib.DeploymentData memory coreDeployment = CoreDeploymentLib.readCoreDeploymentJson("./script/config", 17000, "preprod");

        // Setup middleware deployment data
        MiddlewareDeploymentLib.ConfigData memory middlewareConfig;
        middlewareConfig.proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
        middlewareConfig.admin = address(this);
        middlewareConfig.numQuorums = 1;
        middlewareConfig.operatorParams = new uint256[](3);
        middlewareConfig.operatorParams[0] = 10;
        middlewareConfig.operatorParams[1] = 100;
        middlewareConfig.operatorParams[2] = 100;

        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment = MiddlewareDeploymentLib.deployContracts(coreDeployment, middlewareConfig);

        // Upgrade contracts
        MiddlewareDeploymentLib.upgradeContracts(middlewareDeployment, middlewareConfig, coreDeployment);

                // Verify operators are registered
        for (uint256 i = 0; i < 5; i++) {
            bool isRegistered = IDelegationManager(coreDeployment.delegationManager).isOperator(operators[i].key.addr);
            assertFalse(isRegistered, "Operator should not be registered");
        }
        // Register operators
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr); /// TODO: for script need to just vm.startBroadcast from operator
            OperatorLib.registerAsOperator(operators[i], coreDeployment.delegationManager);
            vm.stopPrank();
        }

        // Verify operators are registered
        for (uint256 i = 0; i < 5; i++) {
            bool isRegistered = IDelegationManager(coreDeployment.delegationManager).isOperator(operators[i].key.addr);
            assertTrue(isRegistered, "Operator should be registered");
        }

        // Mint mock tokens to each operator
        uint256 mintAmount = 1000 * 1e18;
        for (uint256 i = 0; i < 5; i++) {
            OperatorLib.mintMockTokens(operators[i], middlewareDeployment.token, mintAmount);
        }

        // Verify token balances
        for (uint256 i = 0; i < 5; i++) {
            uint256 balance = IERC20(middlewareDeployment.token).balanceOf(operators[i].key.addr);
            assertEq(balance, mintAmount, "Operator should have correct token balance");
        }

        // Deposit tokens into strategy for each operator
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            uint256 shares = OperatorLib.depositTokenIntoStrategy(
                operators[i],
                coreDeployment.strategyManager,
                middlewareDeployment.strategy,
                middlewareDeployment.token,
                mintAmount
            );
            assertTrue(shares > 0, "Should have received shares for deposit");
            vm.stopPrank();
        }

        // Verify strategy shares for each operator
        for (uint256 i = 0; i < 5; i++) {
            uint256 shares = IStrategy(middlewareDeployment.strategy).shares(operators[i].key.addr);
            assertEq(shares, mintAmount, "Operator shares should equal deposit amount");
        }

        IAllocationManagerTypes.CreateSetParams[] memory params = new IAllocationManagerTypes.CreateSetParams[](1);
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(middlewareDeployment.strategy);
        params[0] = IAllocationManagerTypes.CreateSetParams({
            operatorSetId: 0,
            strategies: strategies
        });
        // Migrate AVS to operator sets
        vm.startPrank(middlewareConfig.admin);

        // Enable operator sets
        RegistryCoordinator(middlewareDeployment.registryCoordinator).enableOperatorSets();

        // Create quorum for non-slashable stake
        IRegistryCoordinator.OperatorSetParam memory operatorSetParams = IRegistryCoordinator.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 100, // 1%
            kickBIPsOfTotalStake: 100 // 1%
        });

        IStakeRegistry.StrategyParams[] memory strategyParams = new IStakeRegistry.StrategyParams[](1);
        strategyParams[0] = IStakeRegistry.StrategyParams({
            strategy: IStrategy(middlewareDeployment.strategy),
            multiplier: 1 ether
        });

        RegistryCoordinator(middlewareDeployment.registryCoordinator).createTotalDelegatedStakeQuorum(
            operatorSetParams,
            100 ether, // Minimum stake of 100 tokens
            strategyParams
        );

        vm.stopPrank();

        // Register operators to AVS through AllocationManager
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 1; // First operator set

        // Register each operator to the AVS through AllocationManager
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.registerOperatorFromAVS_OpSet(
                operators[i],
                coreDeployment.allocationManager,
                middlewareDeployment.registryCoordinator,
                middlewareDeployment.serviceManager,
                operatorSetIds
            );
            vm.stopPrank();
        }
    }
}

