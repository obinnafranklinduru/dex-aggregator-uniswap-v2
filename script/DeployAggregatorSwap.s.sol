// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {AggregatorSwap} from "../src/AggregatorSwap.sol";
import {UNISWAP_V2_ROUTER_02} from "../src/Constants.sol";

contract DeployAggregatorSwap is Script {
    function run() public returns (AggregatorSwap) {
        uint256 deployerPrivatekey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivatekey);

        AggregatorSwap aggregator = new AggregatorSwap(address(UNISWAP_V2_ROUTER_02));

        vm.stopBroadcast();

        return aggregator;
    }
}
