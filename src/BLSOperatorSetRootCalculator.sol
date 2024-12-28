// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import { OperatorSet } from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import { IAllocationManager } from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import { IDelegationManager } from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import { IStrategy } from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import { Merkle } from "eigenlayer-contracts/src/contracts/libraries/Merkle.sol";

import { BN254 } from "./libraries/BN254.sol";

import { IOperatorSetRootCalculator } from "./interfaces/IOperatorSetRootCalculator.sol";
import { IBLSApkRegistry } from "./interfaces/IBLSApkRegistry.sol";
import { IStakeRegistry } from "./interfaces/IStakeRegistry.sol";

contract BLSOperatorSetRootCalculator is IOperatorSetRootCalculator {
    using BN254 for BN254.G1Point;
    using Merkle for bytes32[];
    
    IDelegationManager public immutable delegationManager;
    IAllocationManager public immutable allocationManager;

    IStakeRegistry public immutable stakeRegistry;
    IBLSApkRegistry public immutable blsApkRegistry;

    constructor(
        IAllocationManager _allocationManager,
        IDelegationManager _delegationManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry
    ) {
        allocationManager = _allocationManager;
        stakeRegistry = _stakeRegistry;
        delegationManager = _delegationManager;
        blsApkRegistry = _blsApkRegistry;
    }

    /**
	 * @notice called offchain by provers in order to get the operatorSetRoot
	 * @param operatorSet the operatorSet to get the operatorSetRoot for
	 * @return the operatorSetRoot
	 */
	function getOperatorSetRoot(
		OperatorSet calldata operatorSet
	) external view returns(bytes32) {
        // Get operators
        address[] memory operators = allocationManager.getMembers(operatorSet);

        // Get strategy params. TODO: replace this is gross
        IStakeRegistry.StrategyParams[] memory strategyParams = new IStakeRegistry.StrategyParams[](stakeRegistry.strategyParamsLength(uint8(operatorSet.id)));
        IStrategy[] memory strategies = new IStrategy[](strategyParams.length);
        for (uint256 i = 0; i < strategyParams.length; i++) {
            strategyParams[i] = stakeRegistry.strategyParamsByIndex(uint8(operatorSet.id), i);
            strategies[i] = strategyParams[i].strategy;
        }

        // Get delegated stake
        uint256[][] memory delegatedStakes = delegationManager.getOperatorsShares(operators, strategies);
        // Get slashable stake
        uint256[][] memory slashableStakes = allocationManager.getMinimumSlashableStake(operatorSet, operators, strategies, uint32(block.number + 14 days / 12 seconds));
        // Get pubkey hashes    
        BN254.G1Point[] memory pubkeys = new BN254.G1Point[](operators.length);
        for (uint256 i = 0; i < operators.length; i++) {
            (pubkeys[i], ) = blsApkRegistry.getRegisteredPubkey(operators[i]);
        }

        // keep track of totals
        uint256 totalDelegatedStake = 0;
        uint256 totalSlashableStake = 0;
        BN254.G1Point memory aggPubkey = BN254.G1Point(0, 0);

        // operator specific values
        uint256 delegatedStake = 0;
        uint256 slashableStake = 0;

        // Get operator leaves
        bytes32[] memory leaves = new bytes32[](operators.length);
        for (uint256 i = 0; i < operators.length; i++) {
            // get operator specific values
            for (uint256 j = 0; j < strategies.length; j++) {
                delegatedStake += delegatedStakes[i][j] * strategyParams[j].multiplier;
                slashableStake += slashableStakes[i][j] * strategyParams[j].multiplier;
            }

            // add to totals
            totalDelegatedStake += delegatedStake;
            totalSlashableStake += slashableStake;
            aggPubkey = aggPubkey.plus(pubkeys[i]);

            // get operator leaf
            leaves[i] = keccak256(abi.encodePacked(
                delegatedStake,
                slashableStake,
                pubkeys[i].X,
                pubkeys[i].Y
            ));
        }

        // get operator tree root
        bytes32 operatorTreeRoot = leaves.merkleizeKeccak256();

        // get operator set root
        bytes32 operatorSetRoot = keccak256(abi.encodePacked(
            operatorTreeRoot,
            keccak256(abi.encodePacked(
                totalDelegatedStake,
                totalSlashableStake,
                aggPubkey.X,
                aggPubkey.Y
            ))
        ));

        return operatorSetRoot;
	}
}