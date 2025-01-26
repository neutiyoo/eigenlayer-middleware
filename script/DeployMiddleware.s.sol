// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/Test.sol";
import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {CoreDeploymentLib} from "./utils/CoreDeploymentLib.sol";
import {MiddlewareDeploymentLib} from "./utils/MiddlewareDeploymentLib.sol";
import {OperatorLib} from "./utils/OperatorLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManagerTypes} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {RegistryCoordinator} from "../src/RegistryCoordinator.sol";
import {IStakeRegistry, StakeType} from "../src/interfaces/IStakeRegistry.sol";
import {IRegistryCoordinator} from "../src/interfaces/IRegistryCoordinator.sol";
import {BitmapUtils} from "../src/libraries/BitmapUtils.sol";

contract DeployMiddleware is Script {
    CoreDeploymentLib.DeploymentData internal core;
    MiddlewareDeploymentLib.ConfigData internal config;
    MiddlewareDeploymentLib.DeploymentData internal middlewareDeployment;
    address internal deployer;

    // Configuration for operators and strategies
    uint256 constant BATCH_SIZE = 1;
    uint256 constant TOKENS_PER_OPERATOR = 1000;
    uint256 constant NUM_STRATEGIES = 1; // Number of strategies to use
    uint96 constant STRATEGY_MULTIPLIER = 1 ether;
    uint256 constant MINIMUM_STAKE = 0;
    uint256 constant LOOK_AHEAD_PERIOD = 1 days;
    uint32 constant MAX_OPERATOR_COUNT = 200;

    // Arrays to store deployed tokens and strategies
    address[] internal tokens;
    address[] internal strategies;

    function setUp() public {
        string memory rpcUrl = vm.envString("HOLESKY_RPC_URL");
        vm.createSelectFork(rpcUrl, 3212140); /// Block after upgrade
        console.log("Forked Holesky testnet");
        /// TODO: Right now we're only supporting pre-prod
        deployer = vm.rememberKey(vm.envUint("HOLESKY_PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        // Read core deployment data from json
        core = CoreDeploymentLib.readCoreDeploymentJson("./script/config", block.chainid, "preprod");

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

    function doIt() external {
        // Deploy multiple tokens and strategies first
        console.log("Deploying tokens and strategies...");
        tokens = new address[](NUM_STRATEGIES);
        strategies = new address[](NUM_STRATEGIES);

        for (uint256 i = 0; i < NUM_STRATEGIES; i++) {
            // Deploy token and strategy using MiddlewareDeploymentLib
            vm.startPrank(deployer);
            (tokens[i], strategies[i]) = MiddlewareDeploymentLib._deployTokenAndStrategy(core.strategyFactory);
            console.log("Token %d deployed at: %s", i, tokens[i]);
            console.log("Strategy %d deployed at: %s", i, strategies[i]);
            vm.stopPrank();
        }

        // 2. Deploy middleware contracts
        address proxyAdmin = UpgradeableProxyLib.deployProxyAdmin();
        middlewareDeployment = MiddlewareDeploymentLib.deployContracts(proxyAdmin, core, config);
        labelContracts(core, middlewareDeployment);
        MiddlewareDeploymentLib.upgradeContracts(middlewareDeployment, config, core);
        logDeploymentDetails(middlewareDeployment);
        console.log("Middleware contracts deployed");

        // Enable operator sets
        vm.startPrank(config.admin);
        RegistryCoordinator(middlewareDeployment.registryCoordinator).enableOperatorSets();
        console.log("Operator sets enabled");

        // Create slashing quorum with multiple strategies
        IStakeRegistry.StrategyParams[] memory strategyParams = new IStakeRegistry.StrategyParams[](NUM_STRATEGIES);

        // Configure strategies with different multipliers
        for (uint256 i = 0; i < NUM_STRATEGIES; i++) {
            strategyParams[i] = IStakeRegistry.StrategyParams({
                strategy: IStrategy(strategies[i]),
                multiplier: uint96((i + 1) * STRATEGY_MULTIPLIER) // Different multiplier for each strategy
            });
        }

        // Configure operator set params for slashing quorum
        IRegistryCoordinator.OperatorSetParam memory operatorSetParams = IRegistryCoordinator.OperatorSetParam({
            maxOperatorCount: MAX_OPERATOR_COUNT,
            kickBIPsOfOperatorStake: 0,
            kickBIPsOfTotalStake: 0
        });

        // Create slashing quorum
        RegistryCoordinator(middlewareDeployment.registryCoordinator).createSlashableStakeQuorum(
            operatorSetParams,
            0,
            strategyParams,
            7 days
        );
        vm.stopPrank();
        console.log("Slashing quorum created with %d unique strategies", NUM_STRATEGIES);

        // Verify quorum configuration
        require(config.numQuorums >= 1, "At least one quorum must be configured");
        require(config.operatorParams.length >= 3, "Operator params must be configured");

        // 3. Create and register operators in batches
        uint256 numOperators = MAX_OPERATOR_COUNT;
        uint256 batchSize = 1;
        OperatorLib.Operator[] memory operators = new OperatorLib.Operator[](numOperators);
        console.log("Creating and registering %d operators in batches of %d...", numOperators, batchSize);

        for (uint256 i = 0; i < numOperators; i += batchSize) {
            uint256 endIndex = i + batchSize > numOperators ? numOperators : i + batchSize;

            // Create and register batch
            for (uint256 j = i; j < endIndex; j++) {
                operators[j] = OperatorLib.createOperator(string(abi.encodePacked("operator-", j)));

                vm.startPrank(operators[j].key.addr);
                OperatorLib.registerAsOperator(operators[j], core.delegationManager);
                vm.stopPrank();
            }

            // Verify batch registration
            for (uint256 j = i; j < endIndex; j++) {
                bool isRegistered = IDelegationManager(core.delegationManager).isOperator(operators[j].key.addr);
                require(isRegistered, string(abi.encodePacked("Operator registration failed for operator-", j)));
            }

            console.log("Progress: operators %d to %d registered", i, endIndex - 1);

            // Clear memory after each batch
            if (endIndex < numOperators) {
                assembly {
                    mstore(0x40, mload(0x40))
                }
            }
        }
        console.log("All operators created and registered");

        // 4. Mint tokens and deposit into strategies in batches
        uint256 mintAmount = 1000 * 1e18; // 1000 tokens
        console.log("Minting tokens and depositing into strategies in batches...");

        for (uint256 i = 0; i < numOperators; i += batchSize) {
            uint256 endIndex = i + batchSize > numOperators ? numOperators : i + batchSize;

            for (uint256 j = i; j < endIndex; j++) {
                // Mint and deposit each token type
                for (uint256 k = 0; k < NUM_STRATEGIES; k++) {
                    // Mint tokens
                    OperatorLib.mintMockTokens(operators[j], tokens[k], mintAmount);
                    uint256 balance = IERC20(tokens[k]).balanceOf(operators[j].key.addr);
                    require(balance == mintAmount, string(abi.encodePacked("Token ", k, " minting failed for operator-", j)));

                    // Deposit into corresponding strategy
                    vm.startPrank(operators[j].key.addr);
                    uint256 shares = OperatorLib.depositTokenIntoStrategy(
                        operators[j],
                        core.strategyManager,
                        strategies[k],
                        tokens[k],
                        mintAmount
                    );
                    require(shares > 0, string(abi.encodePacked("Strategy ", k, " deposit failed for operator-", j)));
                    vm.stopPrank();

                    // Verify strategy shares
                    uint256 strategyShares = IStrategy(strategies[k]).shares(operators[j].key.addr);
                    require(strategyShares == mintAmount, string(abi.encodePacked("Strategy ", k, " shares mismatch for operator-", j)));
                }
            }

            console.log("Progress: operators %d to %d funded and staked with all tokens", i, endIndex - 1);

            // Clear memory after each batch
            if (endIndex < numOperators) {
                assembly {
                    mstore(0x40, mload(0x40))
                }
            }
        }
        console.log("All operators funded and staked with all tokens");

        // 5. Register operators to slashing quorum through allocation manager
        uint256 numSlashingOperators = MAX_OPERATOR_COUNT;
        console.log("Registering %d operators to slashing quorum...", numSlashingOperators);

        // Verify allocation manager setup
        require(address(core.allocationManager) != address(0), "Allocation manager not configured");
        require(address(middlewareDeployment.serviceManager) != address(0), "Service manager not configured");

        // Set minimum allocation delay in batches
        uint32 minDelay = 1;
        for (uint256 i = 0; i < numSlashingOperators; i += batchSize) {
            uint256 endIndex = i + batchSize > numSlashingOperators ? numSlashingOperators : i + batchSize;

            for (uint256 j = i; j < endIndex; j++) {
                vm.startPrank(operators[j].key.addr);
                OperatorLib.setAllocationDelay(
                    operators[j],
                    address(core.allocationManager),
                    minDelay
                );
                vm.stopPrank();
            }

            console.log("Progress: allocation delay set for operators %d to %d", i, endIndex - 1);
        }

        vm.roll(block.number + 100);

        // Setup allocation parameters with multiple strategies
        IStrategy[] memory allocStrategies = new IStrategy[](NUM_STRATEGIES);
        uint64[] memory magnitudes = new uint64[](NUM_STRATEGIES);

        for (uint256 i = 0; i < NUM_STRATEGIES; i++) {
            allocStrategies[i] = IStrategy(strategies[i]);
            magnitudes[i] = uint64(1 ether); // Different magnitude for each strategy
        }

        OperatorSet memory operatorSet = OperatorSet({
            avs: address(middlewareDeployment.serviceManager),
            id: 1 // Slashing quorum operator set ID
        });

        IAllocationManagerTypes.AllocateParams[] memory allocParams = new IAllocationManagerTypes.AllocateParams[](1);
        allocParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet,
            strategies: allocStrategies,
            newMagnitudes: magnitudes
        });

        // Allocate stake for operators in batches
        for (uint256 i = 0; i < numSlashingOperators; i += batchSize) {
            uint256 endIndex = i + batchSize > numSlashingOperators ? numSlashingOperators : i + batchSize;

            for (uint256 j = i; j < endIndex; j++) {
                vm.startPrank(operators[j].key.addr);
                OperatorLib.modifyOperatorAllocations(
                    operators[j],
                    address(core.allocationManager),
                    allocParams
                );
                vm.stopPrank();
            }

            console.log("Progress: operators %d to %d allocated stake", i, endIndex - 1);

            // Clear memory after each batch
            if (endIndex < numSlashingOperators) {
                assembly {
                    mstore(0x40, mload(0x40))
                }
            }
        }

        console.log("All operators allocated stake");

        // Register operators to operator sets
        console.log("Registering operators to operator sets...");

        // Create operator set IDs array
        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = 1; // Slashing quorum operator set ID

        // Register each operator to the operator set
        for (uint256 i = 0; i < numSlashingOperators; i += batchSize) {
            uint256 endIndex = i + batchSize > numSlashingOperators ? numSlashingOperators : i + batchSize;

            for (uint256 j = i; j < endIndex; j++) {
                vm.startPrank(operators[j].key.addr);
                OperatorLib.registerOperatorFromAVS_OpSet(
                    operators[j],
                    core.allocationManager,
                    middlewareDeployment.registryCoordinator,
                    middlewareDeployment.serviceManager,
                    operatorSetIds
                );
                vm.stopPrank();

                // Verify operator is registered for slashing quorum
                bytes32 operatorId = RegistryCoordinator(middlewareDeployment.registryCoordinator).getOperatorId(operators[j].key.addr);
                uint192 currentBitmap = RegistryCoordinator(middlewareDeployment.registryCoordinator).getCurrentQuorumBitmap(operatorId);
                require(
                    BitmapUtils.isSet(currentBitmap, 1), // Check bit 1 is set (slashing quorum)
                    string(abi.encodePacked("Operator ", j, " not registered for slashing quorum"))
                );
            }

            console.log("Progress: operators %d to %d registered to operator sets", i, endIndex - 1);
        }

        vm.roll(block.number + 10);

        console.log("All operators registered to operator sets");

        // 6. Update operator stakes for the slashing quorum
        console.log("Updating operator stakes for slashing quorum...");

        // Create array of operator addresses for the quorum
        address[][] memory operatorsPerQuorum = new address[][](1);
        operatorsPerQuorum[0] = new address[](numSlashingOperators);

        // Fill the array with operator addresses and sort them
        for (uint256 i = 0; i < numSlashingOperators; i++) {
            operatorsPerQuorum[0][i] = operators[i].key.addr;
        }

        // Sort operator addresses in ascending order
        for (uint256 i = 0; i < numSlashingOperators - 1; i++) {
            for (uint256 j = 0; j < numSlashingOperators - i - 1; j++) {
                if (operatorsPerQuorum[0][j] > operatorsPerQuorum[0][j + 1]) {
                    address temp = operatorsPerQuorum[0][j];
                    operatorsPerQuorum[0][j] = operatorsPerQuorum[0][j + 1];
                    operatorsPerQuorum[0][j + 1] = temp;
                }
            }
        }

        // Create quorum numbers array for the slashing quorum (ID 2)
        bytes memory quorumNumbers = new bytes(1);
        quorumNumbers[0] = bytes1(uint8(1));

        // Log gas before call
        uint256 gasBefore = gasleft();

        // Update operator stakes
        RegistryCoordinator(middlewareDeployment.registryCoordinator).updateOperatorsForQuorum(
            operatorsPerQuorum,
            quorumNumbers
        );

        // Log gas used
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for updateOperatorsForQuorum:", gasUsed);

        console.log("Test completed successfully!");
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
