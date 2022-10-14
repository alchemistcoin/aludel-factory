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

        vm.startBroadcast();

        // AludelV1 deployment
        AludelV1 aludelV1 = new AludelV1();
        
        // no need to initialize an empty contract

        // add AludelV1 template
        factory.addTemplate(address(aludelV1), "AludelV1", true);

        // GeyserV2 deployment
        GeyserV2 geyser = new GeyserV2();

        // idem aludelV1, no need to initialize

        // add GeyserV2 template
        factory.addTemplate(address(geyser), "GeyserV2", true);
        
        vm.stopBroadcast();

        vm.startBroadcast();

        // AludelV2 deployment
        Aludel aludel = new Aludel();

        aludel.initializeLock();

        // add AludelV2 template
        factory.addTemplate(address(aludel), "AludelV2", false);

        vm.stopBroadcast();

    }

}

