// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISlashingRegistryCoordinator} from "../interfaces/ISlashingRegistryCoordinator.sol";
import {SlasherBase} from "./base/SlasherBase.sol";

contract InstantSlasher is SlasherBase {
    constructor(
        IAllocationManager _allocationManager,
        ISlashingRegistryCoordinator _slashingRegistryCoordinator,
        address _slasher
    ) SlasherBase(_allocationManager, _slashingRegistryCoordinator) {}

    function initialize(
        address _slasher
    ) external initializer {
        __SlasherBase_init(_slasher);
    }

    function fulfillSlashingRequest(
        IAllocationManager.SlashingParams memory _slashingParams
    ) external virtual onlySlasher {
        uint256 requestId = nextRequestId++;
        _fulfillSlashingRequest(requestId, _slashingParams);
    }
}
