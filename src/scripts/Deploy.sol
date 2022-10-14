// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DSTest} from "ds-test/src/test.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";

import "forge-std/src/Script.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import "forge-std/src/StdJson.sol";
import {IAludel} from "../contracts/aludel/IAludel.sol";
import {Aludel} from "../contracts/aludel/Aludel.sol";
import {AludelV1} from "../contracts/aludel/legacy/AludelV1.sol";
import {GeyserV2} from "../contracts/aludel/legacy/GeyserV2.sol";


contract EmptyContract {}

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

        // deploy an empty contract to reserve an address
        EmptyContract aludelV1 = new EmptyContract();
        
        // no need to initialize an empty contract

        // add AludelV1 template
        factory.addTemplate(address(aludelV1), "AludelV1", true);

        // deploy an empty contract to reserve an address
        EmptyContract geyser = new EmptyContract();

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


contract AddPrograms is Script, DSTest {

    using stdJson for string;


    // Struct keys must be in alphabetical order
    // @dev hex numbers are parsed as bytes
    struct ParsedProgramConfig {
        string name;
        bytes program;
        string stakingTokenUrl;
        uint64 startTime;
        bytes template;
    }
    // we need to reparse the json to convert hex numbers to the correct type
    struct ProgramConfig {
        string name;
        address program;
        string stakingTokenUrl;
        uint64 startTime;
        address template;
    }


    function run() external {
        
        // vm.startBroadcast();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/oldPrograms.json");
        string memory json = vm.readFile(path);
        bytes memory parsed = json.parseRaw(".programs");

        address aludelFactoryAddress = json.readAddress(".aludelFactory");

        ParsedProgramConfig[] memory programs = abi.decode(parsed, (ParsedProgramConfig[]));
        
        for (uint256 i = 0; i < programs.length; i++) {

            ProgramConfig memory program = convertProgramConfig(programs[i]);
            emit log_address(program.program);
            emit log_address(program.template);
            emit log_string(program.name);
            emit log_string(program.stakingTokenUrl);
            emit log_uint(program.startTime);
            // AludelFactory(aludelFactoryAddress).addProgram(
            //     program.program,
            //     program.template,
            //     program.name,
            //     program.stakingTokenUrl,
            //     program.startTime
            // );
        }


        // vm.stopBroadcast();

    }

    function convertProgramConfig(ParsedProgramConfig memory config) internal pure returns (ProgramConfig memory) {
        return ProgramConfig({
            program: address(bytes20(config.program)),
            template: address(bytes20(config.template)),
            name: config.name,
            stakingTokenUrl: config.stakingTokenUrl,
            startTime: config.startTime
        });
    }

}
