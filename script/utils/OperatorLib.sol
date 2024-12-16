// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";

import {console2 as console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStakeRegistry} from "../../src/interfaces/IStakeRegistry.sol";
import {IRegistryCoordinator} from "../../src/RegistryCoordinator.sol";
import {OperatorStateRetriever} from "../../src/OperatorStateRetriever.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {UpgradeableProxyLib} from "./UpgradeableProxyLib.sol";
import {CoreDeploymentLib} from "./CoreDeploymentLib.sol";
import {ERC20Mock} from "./MiddlewareDeploymentLib.sol";

library OperatorLib {

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    /// TODO BLS Wallet
    struct Operator {
        Vm.Wallet key;
        Vm.Wallet signingKey;
    }

    function signWithOperatorKey(
        Operator memory operator,
        bytes32 digest
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator.key.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signWithSigningKey(
        Operator memory operator,
        bytes32 digest
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operator.signingKey.privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function mintMockTokens(Operator memory operator, address token, uint256 amount) internal {
        ERC20Mock(token).mint(operator.key.addr, amount);
    }

    function depositTokenIntoStrategy(
        Operator memory operator,
        address strategyManager,
        address strategy,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        /// TODO :make sure strategy associated with token
        IStrategy strategy = IStrategy(strategy);
        require(address(strategy) != address(0), "Strategy was not found");
        IStrategyManager strategyManager = IStrategyManager(strategyManager);

        ERC20Mock(token).approve(address(strategyManager), amount);
        uint256 shares = strategyManager.depositIntoStrategy(strategy, IERC20(token), amount);

        return shares;
    }

    function registerAsOperator(
        Operator memory operator,
        address delegationManager
    ) internal {
        IDelegationManager delegationManagerInstance = IDelegationManager(delegationManager);

        delegationManagerInstance.registerAsOperator(
            operator.key.addr,
            0,
            ""
        );
    }

    function registerOperatorToAVS_M2(
        Operator memory operator,
        address avsDirectory,
        address serviceManager
    ) internal {
        IAVSDirectory avsDirectory = IAVSDirectory(avsDirectory);

        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, operator.key.addr));
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 operatorRegistrationDigestHash = avsDirectory
            .calculateOperatorAVSRegistrationDigestHash(
            operator.key.addr, serviceManager, salt, expiry
        );

        bytes memory signature = signWithOperatorKey(operator, operatorRegistrationDigestHash);

        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature = ISignatureUtils
            .SignatureWithSaltAndExpiry({signature: signature, salt: salt, expiry: expiry});

        /// TODO: call the registry
    }

    function deregisterOperatorFromAVS_M2() internal {
        /// TODO: call the registry

    }

    function registerOperatorFromAVS_OpSet() internal {
        /// TODO: call the ALM
    }

    function deregisterOperatorFromAVS_OpSet() internal {
        /// TODO: call the ALM
    }

    function createAndAddOperator(uint256 salt) internal returns (Operator memory) {
        Vm.Wallet memory operatorKey =
            vm.createWallet(string.concat("operator", vm.toString(salt)));
        /// TODO: BLS Key for signing key.  Integrate G2Operations.sol
        Vm.Wallet memory signingKey =
            vm.createWallet(string.concat("signing", vm.toString(salt)));

        Operator memory newOperator = Operator({key: operatorKey, signingKey: signingKey});

        return newOperator;
    }
}