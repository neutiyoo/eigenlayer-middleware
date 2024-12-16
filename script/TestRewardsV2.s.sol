// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Script, stdJson} from "forge-std/Script.sol";

import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IServiceManager} from "src/interfaces/IServiceManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

contract TestRewardsV2 is Script {
    IRewardsCoordinator rewardsCoordinator =
        IRewardsCoordinator(0xAcc1fb458a1317E886dB376Fc8141540537E68fE);
    IServiceManager eigenDAServiceManager =
        IServiceManager(0xD4A7E1Bd8015057293f0D0A557088c286942e84b);

    IERC20 WETH = IERC20(0x94373a4919B3240D86eA41593D5eBa789FEF3848);

    // operators
    address OPERATOR_STAKELY = 0x06Fb6C463cC68100355624B6006471A960704126;
    address OPERATOR_EIGENYIELDS = 0x5ACCC90436492F24E6aF278569691e2c942A676d;
    address OPERATOR_XYZ = 0x758E016468E5E90cDB42e743881C2e921d8e7bF8;
    address OPERATOR_GALAXY = 0x0a3e3d83C99B27cA7540720b54105C79Cd58dbdD;
    address OPERATOR_SINOPMM = 0xB25430A1Ba8F2033834Ba30AAB8279CB1Cb6c9a6;

    //strategies
    IStrategy STRATEGY_WETH =
        IStrategy(0x80528D6e9A2BAbFc766965E0E26d5aB08D9CFaF9);
    IStrategy STRATEGY_STETH =
        IStrategy(0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3);

    IRewardsCoordinator.StrategyAndMultiplier[] defaultStrategyAndMultipliers;

    function _setupStrategyAndMultiplier() internal {
        defaultStrategyAndMultipliers = new IRewardsCoordinator.StrategyAndMultiplier[](
            2
        );

        defaultStrategyAndMultipliers[0] = IRewardsCoordinator
            .StrategyAndMultiplier({strategy: STRATEGY_WETH, multiplier: 2e18});

        defaultStrategyAndMultipliers[1] = IRewardsCoordinator
            .StrategyAndMultiplier({
                strategy: STRATEGY_STETH,
                multiplier: 1e18
            });

        defaultStrategyAndMultipliers = _sortStrategyArrayAsc(
            defaultStrategyAndMultipliers
        );
    }

    function _sortStrategyArrayAsc(
        IStrategy[] memory arr
    ) internal pure returns (IStrategy[] memory) {
        uint256 l = arr.length;
        for (uint256 i = 0; i < l; i++) {
            for (uint256 j = i + 1; j < l; j++) {
                if (address(arr[i]) > address(arr[j])) {
                    IStrategy temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }

    /// @dev Sort to ensure that the array is in ascending order for addresses
    function _sortAddressArrayAsc(
        address[] memory arr
    ) internal pure returns (address[] memory) {
        uint256 l = arr.length;
        for (uint256 i = 0; i < l; i++) {
            for (uint256 j = i + 1; j < l; j++) {
                if (arr[i] > arr[j]) {
                    address temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }

    function tx_1() public {
        _setupStrategyAndMultiplier();

        IRewardsCoordinator.RewardsSubmission[]
            memory rewardsSubmissions = new IRewardsCoordinator.RewardsSubmission[](
                1
            );

        rewardsSubmissions[0] = IRewardsCoordinator.RewardsSubmission({
            strategiesAndMultipliers: defaultStrategyAndMultipliers,
            token: WETH,
            amount: 1e18,
            startTimestamp: uint32(1734220800), // 2024-12-15 00:00:00 UTC
            duration: uint32(86400) // 1 day
        });

        vm.broadcast();
        eigenDAServiceManager.createAVSRewardsSubmission(rewardsSubmissions);
    }

    function tx_2() public {
        _setupStrategyAndMultiplier();

        IRewardsCoordinator.RewardsSubmission[]
            memory rewardsSubmissions = new IRewardsCoordinator.RewardsSubmission[](
                1
            );

        rewardsSubmissions[0] = IRewardsCoordinator.RewardsSubmission({
            strategiesAndMultipliers: defaultStrategyAndMultipliers,
            token: WETH,
            amount: 1e18,
            startTimestamp: uint32(1733788800), // 2024-12-10 00:00:00 UTC
            duration: uint32(518400) // 6 days
        });

        vm.broadcast();
        eigenDAServiceManager.createAVSRewardsSubmission(rewardsSubmissions);
    }

    function tx_5() public {
        _setupStrategyAndMultiplier();

        IRewardsCoordinator.OperatorReward[]
            memory operatorRewards = new IRewardsCoordinator.OperatorReward[](
                2
            );

        operatorRewards[0] = IRewardsCoordinator.OperatorReward({
            operator: OPERATOR_STAKELY,
            amount: 1e18
        });
        operatorRewards[1] = IRewardsCoordinator.OperatorReward({
            operator: OPERATOR_EIGENYIELDS,
            amount: 1e18
        });

        operatorRewards = _sortAddressArrayAsc(operatorRewards);

        IRewardsCoordinator.OperatorDirectedRewardsSubmission[]
            memory rewardsSubmissions = new IRewardsCoordinator.OperatorDirectedRewardsSubmission[](
                1
            );

        rewardsSubmissions[0] = IRewardsCoordinator
            .OperatorDirectedRewardsSubmission({
                strategiesAndMultipliers: defaultStrategyAndMultipliers,
                token: WETH,
                operatorRewards: operatorRewards,
                startTimestamp: uint32(1734220800), // 2024-12-15 00:00:00 UTC
                duration: uint32(86400), // 1 day
                description: ""
            });

        vm.broadcast();
        eigenDAServiceManager.createAVSRewardsSubmission(rewardsSubmissions);
    }

    function tx_6() public {
        _setupStrategyAndMultiplier();

        IRewardsCoordinator.OperatorReward[]
            memory operatorRewards = new IRewardsCoordinator.OperatorReward[](
                1
            );

        operatorRewards[0] = IRewardsCoordinator.OperatorReward({
            operator: OPERATOR_EIGENYIELDS,
            amount: 1e18
        });

        operatorRewards = _sortAddressArrayAsc(operatorRewards);

        IRewardsCoordinator.OperatorDirectedRewardsSubmission[]
            memory rewardsSubmissions = new IRewardsCoordinator.OperatorDirectedRewardsSubmission[](
                1
            );

        rewardsSubmissions[0] = IRewardsCoordinator
            .OperatorDirectedRewardsSubmission({
                strategiesAndMultipliers: defaultStrategyAndMultipliers,
                token: WETH,
                operatorRewards: operatorRewards,
                startTimestamp: uint32(1733788800), // 2024-12-10 00:00:00 UTC
                duration: uint32(518400), // 6 days
                description: ""
            });

        vm.broadcast();
        eigenDAServiceManager.createAVSRewardsSubmission(rewardsSubmissions);
    }
}
