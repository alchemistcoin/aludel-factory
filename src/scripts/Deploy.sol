// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DSTest} from "ds-test/src/test.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";

import "forge-std/src/Script.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";

import {IAludel} from "../contracts/aludel/IAludel.sol";
import {Aludel} from "../contracts/aludel/Aludel.sol";
import {AludelV1} from "../contracts/aludel/legacy/AludelV1.sol";
import {GeyserV2} from "../contracts/aludel/legacy/GeyserV2.sol";

contract DeployFactory is Script {

    function run() external {
        
        // default value: 
        address recipient = vm.envAddress("ALUDEL_FACTORY_RECIPIENT");

        // default value: 100
        uint16 bps = uint16(vm.envUint("ALUDEL_FACTORY_BPS"));

        vm.startBroadcast();
        AludelFactory factory = new AludelFactory(recipient, bps);
        vm.stopBroadcast();

        // AludelV1 deployment
        vm.startBroadcast();
        AludelV1 aludelV1 = new AludelV1();
        vm.stopBroadcast();


        // add AludelV1 template
        vm.startBroadcast();
        factory.addTemplate(address(aludelV1), "AludelV1", true);
        vm.stopBroadcast();


        // AludelV2 deployment
        vm.startBroadcast();
        GeyserV2 geyser = new GeyserV2();
        vm.stopBroadcast();

        // add GeyserV2 template
        vm.startBroadcast();
        factory.addTemplate(address(geyser), "GeyserV2", true);
        vm.stopBroadcast();


        // AludelV2 deployment
        vm.startBroadcast();
        Aludel aludel = new Aludel();
        vm.stopBroadcast();


        // add AludelV2 template
        vm.startBroadcast();
        factory.addTemplate(address(aludel), "AludelV2", false);
        vm.stopBroadcast();

    }

}
