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
import {OperatorSet} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ServiceManagerMock} from "../mocks/ServiceManagerMock.sol";

contract End2EndForkTest is Test {
    using OperatorLib for *;

    function _createOperators(uint256 numOperators, uint256 startIndex) internal returns (OperatorLib.Operator[] memory) {
        OperatorLib.Operator[] memory operators = new OperatorLib.Operator[](numOperators);
        for (uint256 i = 0; i < numOperators; i++) {
            operators[i] = OperatorLib.createOperator(string(abi.encodePacked("operator-", i + startIndex)));
        }
        return operators;
    }

    function _registerOperatorsAsEigenLayerOperators(
        OperatorLib.Operator[] memory operators,
        address delegationManager
    ) internal {
        for (uint256 i = 0; i < operators.length; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.registerAsOperator(operators[i], delegationManager);
            vm.stopPrank();
        }
    }

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
        (OperatorLib.Operator[] memory operators, CoreDeploymentLib.DeploymentData memory coreDeployment,
         MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment,
         MiddlewareDeploymentLib.ConfigData memory middlewareConfig) = _setupInitialState();

        _setupOperatorsAndTokens(operators, coreDeployment, middlewareDeployment);

        _setupFirstQuorumAndOperatorSet(operators, middlewareConfig, coreDeployment, middlewareDeployment);

        _setupSecondQuorumAndOperatorSet(operators, middlewareConfig, coreDeployment, middlewareDeployment);

        _executeSlashing(operators, middlewareConfig, middlewareDeployment);
    }

    function _setupInitialState() internal returns (
        OperatorLib.Operator[] memory operators,
        CoreDeploymentLib.DeploymentData memory coreDeployment,
        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment,
        MiddlewareDeploymentLib.ConfigData memory middlewareConfig
    ) {
        // Fork Holesky testnet
        string memory rpcUrl = vm.envString("HOLESKY_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // Create 5 operators using helper function
        operators = _createOperators(5, 100);

        // Read core deployment data from json
        coreDeployment = CoreDeploymentLib.readCoreDeploymentJson("./script/config", 17000, "preprod");

        // Setup middleware deployment data
        middlewareConfig.proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
        middlewareConfig.admin = address(this);
        middlewareConfig.numQuorums = 1;
        middlewareConfig.operatorParams = new uint256[](3);
        middlewareConfig.operatorParams[0] = 10;
        middlewareConfig.operatorParams[1] = 100;
        middlewareConfig.operatorParams[2] = 100;

        middlewareDeployment = MiddlewareDeploymentLib.deployContracts(coreDeployment, middlewareConfig);
        MiddlewareDeploymentLib.upgradeContracts(middlewareDeployment, middlewareConfig, coreDeployment);
    }

    function _setupOperatorsAndTokens(
        OperatorLib.Operator[] memory operators,
        CoreDeploymentLib.DeploymentData memory coreDeployment,
        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment
    ) internal {
        // Verify and register operators
        for (uint256 i = 0; i < 5; i++) {
            bool isRegistered = IDelegationManager(coreDeployment.delegationManager).isOperator(operators[i].key.addr);
            assertFalse(isRegistered, "Operator should not be registered");
        }

        _registerOperatorsAsEigenLayerOperators(operators, coreDeployment.delegationManager);

        for (uint256 i = 0; i < 5; i++) {
            bool isRegistered = IDelegationManager(coreDeployment.delegationManager).isOperator(operators[i].key.addr);
            assertTrue(isRegistered, "Operator should be registered");
        }

        // Setup tokens and verify balances
        uint256 mintAmount = 1000 * 1e18;
        for (uint256 i = 0; i < 5; i++) {
            OperatorLib.mintMockTokens(operators[i], middlewareDeployment.token, mintAmount);
            uint256 balance = IERC20(middlewareDeployment.token).balanceOf(operators[i].key.addr);
            assertEq(balance, mintAmount, "Operator should have correct token balance");
        }

        // Handle deposits
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

            shares = IStrategy(middlewareDeployment.strategy).shares(operators[i].key.addr);
            assertEq(shares, mintAmount, "Operator shares should equal deposit amount");
        }
    }

    function _setupFirstQuorumAndOperatorSet(
        OperatorLib.Operator[] memory operators,
        MiddlewareDeploymentLib.ConfigData memory middlewareConfig,
        CoreDeploymentLib.DeploymentData memory coreDeployment,
        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment
    ) internal {
        vm.startPrank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).enableOperatorSets();

        // Create first quorum
        IRegistryCoordinator.OperatorSetParam memory operatorSetParams = IRegistryCoordinator.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 100,
            kickBIPsOfTotalStake: 100
        });

        IStakeRegistry.StrategyParams[] memory strategyParams = new IStakeRegistry.StrategyParams[](1);
        strategyParams[0] = IStakeRegistry.StrategyParams({
            strategy: IStrategy(middlewareDeployment.strategy),
            multiplier: 1 ether
        });

        RegistryCoordinator(middlewareDeployment.registryCoordinator).createTotalDelegatedStakeQuorum(
            operatorSetParams,
            100,
            strategyParams
        );
        vm.stopPrank();

        // Register operators
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 1;

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

        vm.roll(block.number + 10);

        // Update operators for quorum
        address[][] memory registeredOperators = _getAndSortOperators(operators);
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(1));

        vm.prank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).updateOperatorsForQuorum(
            registeredOperators,
            quorumNumbers
        );
    }

    function _setupSecondQuorumAndOperatorSet(
        OperatorLib.Operator[] memory operators,
        MiddlewareDeploymentLib.ConfigData memory middlewareConfig,
        CoreDeploymentLib.DeploymentData memory coreDeployment,
        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment
    ) internal {
        // Create second quorum
        vm.startPrank(middlewareConfig.admin);
        IStakeRegistry.StrategyParams[] memory strategyParams = new IStakeRegistry.StrategyParams[](1);
        strategyParams[0] = IStakeRegistry.StrategyParams({
            strategy: IStrategy(middlewareDeployment.strategy),
            multiplier: 1 ether
        });

        IRegistryCoordinator.OperatorSetParam memory operatorSetParams = IRegistryCoordinator.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });

        RegistryCoordinator(middlewareDeployment.registryCoordinator).createSlashableStakeQuorum(
            operatorSetParams,
            100,
            strategyParams,
            1 days
        );
        vm.stopPrank();

        _setupOperatorAllocations(operators, coreDeployment, middlewareDeployment);

        // Register and update operators for second quorum
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 2;

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

        vm.roll(block.number + 10);

        address[][] memory registeredOperators = _getAndSortOperators(operators);
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(2));

        vm.prank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).updateOperatorsForQuorum(
            registeredOperators,
            quorumNumbers
        );
    }

    function _setupOperatorAllocations(
        OperatorLib.Operator[] memory operators,
        CoreDeploymentLib.DeploymentData memory coreDeployment,
        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment
    ) internal {
        uint32 minDelay = 1;
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.setAllocationDelay(
                operators[i],
                address(coreDeployment.allocationManager),
                minDelay
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 100);

        IStrategy[] memory allocStrategies = new IStrategy[](1);
        allocStrategies[0] = IStrategy(middlewareDeployment.strategy);

        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = uint64(1 ether);

        OperatorSet memory operatorSet = OperatorSet({
            avs: address(middlewareDeployment.serviceManager),
            id: 2
        });

        IAllocationManagerTypes.AllocateParams[] memory allocParams = new IAllocationManagerTypes.AllocateParams[](1);
        allocParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet,
            strategies: allocStrategies,
            newMagnitudes: magnitudes
        });

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.modifyOperatorAllocations(
                operators[i],
                address(coreDeployment.allocationManager),
                allocParams
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 100);
    }

    function _executeSlashing(
        OperatorLib.Operator[] memory operators,
        MiddlewareDeploymentLib.ConfigData memory middlewareConfig,
        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment
    ) internal {
        address newSlasher = makeAddr("newSlasher");
        vm.startPrank(middlewareConfig.admin);
        ServiceManagerMock(middlewareDeployment.serviceManager).proposeNewSlasher(newSlasher);
        vm.warp(block.timestamp + 8 days);
        ServiceManagerMock(middlewareDeployment.serviceManager).acceptProposedSlasher();
        vm.stopPrank();

        IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
            operator: operators[0].key.addr,
            operatorSetId: 2,
            strategies: new IStrategy[](1),
            wadsToSlash: new uint256[](1),
            description: "Test slashing"
        });

        slashingParams.strategies[0] = IStrategy(middlewareDeployment.strategy);
        slashingParams.wadsToSlash[0] = 0.5e18;

        vm.prank(newSlasher);
        ServiceManagerMock(middlewareDeployment.serviceManager).slashOperator(slashingParams);
    }

    function _getAndSortOperators(OperatorLib.Operator[] memory operators) internal pure returns (address[][] memory) {
        address[][] memory registeredOperators = new address[][](1);
        registeredOperators[0] = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            registeredOperators[0][i] = operators[i].key.addr;
        }

        // Sort operator addresses
        for (uint256 i = 0; i < registeredOperators[0].length - 1; i++) {
            for (uint256 j = 0; j < registeredOperators[0].length - i - 1; j++) {
                if (registeredOperators[0][j] > registeredOperators[0][j + 1]) {
                    address temp = registeredOperators[0][j];
                    registeredOperators[0][j] = registeredOperators[0][j + 1];
                    registeredOperators[0][j + 1] = temp;
                }
            }
        }

        return registeredOperators;
    }

    function testEndToEndSetup_M2Migration() public {
        (OperatorLib.Operator[] memory operators, CoreDeploymentLib.DeploymentData memory coreDeployment,
         MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment,
         MiddlewareDeploymentLib.ConfigData memory middlewareConfig) = _setupInitialState();

        _setupOperatorsAndTokens(operators, coreDeployment, middlewareDeployment);

        _setupFirstQuorumAndOperatorSet(operators, middlewareConfig, coreDeployment, middlewareDeployment);

        _setupSecondQuorumAndOperatorSet(operators, middlewareConfig, coreDeployment, middlewareDeployment);

        _executeSlashing(operators, middlewareConfig, middlewareDeployment);
    }

    function _setupFirstQuorumAndOperatorSet_M2(
        OperatorLib.Operator[] memory operators,
        MiddlewareDeploymentLib.ConfigData memory middlewareConfig,
        CoreDeploymentLib.DeploymentData memory coreDeployment,
        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment
    ) internal {
        // Register operators to AVS through AllocationManager
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 1; // First operator set

        // Register each operator to the AVS through M2
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            bytes memory quorumNumbers = new bytes(1);
            quorumNumbers[0] = bytes1(uint8(1)); // Quorum 1
            OperatorLib.registerOperatorToAVS_M2(
                operators[i],
                coreDeployment.avsDirectory,
                middlewareDeployment.serviceManager,
                middlewareDeployment.registryCoordinator,
                quorumNumbers,
                "test-socket"
            );
            vm.stopPrank();
        }

        // Fast forward 10 blocks
        vm.roll(block.number + 10);

        // Get all registered operators and sort them
        address[][] memory registeredOperators = _getAndSortOperators(operators);

        // Update operators for quorum 1
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(1)); // Quorum 1

        vm.prank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).updateOperatorsForQuorum(
            registeredOperators,
            quorumNumbers
        );

        // Enable operator sets
        // Migrate AVS to operator sets
        vm.startPrank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).enableOperatorSets();
        vm.stopPrank();
    }

    function _setupSecondQuorumAndOperatorSet_M2(
        OperatorLib.Operator[] memory operators,
        MiddlewareDeploymentLib.ConfigData memory middlewareConfig,
        CoreDeploymentLib.DeploymentData memory coreDeployment,
        MiddlewareDeploymentLib.DeploymentData memory middlewareDeployment
    ) internal {
        // Create a second operator set for slashable stake
        IStakeRegistry.StrategyParams[] memory strategyParams2 = new IStakeRegistry.StrategyParams[](1);
        strategyParams2[0] = IStakeRegistry.StrategyParams({
            strategy: IStrategy(middlewareDeployment.strategy),
            multiplier: 1 ether
        });

        // Configure operator set params
        IRegistryCoordinator.OperatorSetParam memory operatorSetParams2 = IRegistryCoordinator.OperatorSetParam({
            maxOperatorCount: 10,
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });

        // Create quorum with slashable stake type
        vm.startPrank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).createSlashableStakeQuorum(
            operatorSetParams2,
            100, // minimumStake
            strategyParams2,
            1 days // lookAheadPeriod
        );
        vm.stopPrank();

        // Set allocation delay to 1 block for each operator
        uint32 minDelay = 1;
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.setAllocationDelay(
                operators[i],
                address(coreDeployment.allocationManager),
                minDelay
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 100);

        // Set up allocation parameters for each operator
        IStrategy[] memory allocStrategies = new IStrategy[](1);
        allocStrategies[0] = IStrategy(middlewareDeployment.strategy);

        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = uint64(1 ether); // Allocate full magnitude to meet minimum stake

        OperatorSet memory operatorSet = OperatorSet({
            avs: address(middlewareDeployment.serviceManager),
            id: 2 // Second operator set
        });

        IAllocationManagerTypes.AllocateParams[] memory allocParams = new IAllocationManagerTypes.AllocateParams[](1);
        allocParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet,
            strategies: allocStrategies,
            newMagnitudes: magnitudes
        });

        // Allocate stake for each operator using helper function
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.modifyOperatorAllocations(
                operators[i],
                address(coreDeployment.allocationManager),
                allocParams
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 100);

        // Register operators to second operator set
        uint32[] memory operatorSetIds2 = new uint32[](1);
        operatorSetIds2[0] = 2; // Second operator set

        // Register each operator to the second set
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(operators[i].key.addr);
            OperatorLib.registerOperatorFromAVS_OpSet(
                operators[i],
                coreDeployment.allocationManager,
                middlewareDeployment.registryCoordinator,
                middlewareDeployment.serviceManager,
                operatorSetIds2
            );
            vm.stopPrank();
        }

        vm.roll(block.number + 10);

        // Get all registered operators for second set and sort them
        address[][] memory registeredOperators2 = _getAndSortOperators(operators);

        // Update operators for quorum 2
        bytes memory quorumNumbers2 = new bytes(1);
        quorumNumbers2[0] = bytes1(uint8(2)); // Quorum 2

        vm.prank(middlewareConfig.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).updateOperatorsForQuorum(
            registeredOperators2,
            quorumNumbers2
        );
    }
}
