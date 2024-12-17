// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {OperatorLib} from "../../script/utils/OperatorLib.sol";

contract OperatorLibTest is Test {
    using OperatorLib for *;

    function testCreateOperator() public {
        uint256 index = 1;
        OperatorLib.Operator memory operator = OperatorLib.createOperator(index);

        // Check that the operator's VM wallet address is non-zero
        assertTrue(operator.key.addr != address(0), "VM wallet address should be non-zero");

        // Check that the operator's BLS private key is non-zero
        assertTrue(operator.signingKey.privateKey != 0, "BLS private key should be non-zero");

        // Check that the operator's BLS public key G1 is non-zero
        assertTrue(operator.signingKey.publicKeyG1.X != 0 || operator.signingKey.publicKeyG1.X != 0, "BLS public key G1 X should be non-zero");
        assertTrue(operator.signingKey.publicKeyG1.Y != 0 || operator.signingKey.publicKeyG1.Y!= 0, "BLS public key G1 Y should be non-zero");

        // Check that the operator's BLS public key G2 is non-zero
        assertTrue(operator.signingKey.publicKeyG2.X[0] != 0 || operator.signingKey.publicKeyG2.X[1] != 0, "BLS public key G2 X should be non-zero");
        assertTrue(operator.signingKey.publicKeyG2.Y[0] != 0 || operator.signingKey.publicKeyG2.Y[1] != 0, "BLS public key G2 Y should be non-zero");
    }
}

