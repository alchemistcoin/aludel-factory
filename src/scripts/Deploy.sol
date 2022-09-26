// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DSTest} from "ds-test/src/test.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";

import "forge-std/src/Script.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";

import {IAludel} from "../contracts/aludel/IAludel.sol";
import {Aludel} from "../contracts/aludel/Aludel.sol";

contract DeployFactory is Script {

    function run() external {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");


        // default value: 
        address recipient = vm.envAddress("ALUDEL_FACTORY_RECIPIENT");

        // default value: 100
        uint16 bps = uint16(vm.envUint("ALUDEL_FACTORY_BPS"));

        vm.startBroadcast();

        AludelFactory factory = new AludelFactory(recipient, bps);
        
        vm.stopBroadcast();
    }

}
