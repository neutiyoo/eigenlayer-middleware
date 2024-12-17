// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {OperatorLib} from "../../script/utils/OperatorLib.sol";
import {BN254} from "../../src/libraries/BN254.sol";

contract OperatorLibTest is Test {
    using OperatorLib for *;

    function testCreateOperator() public {
        uint256 index = 1;
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
}

