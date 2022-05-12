// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import { ProxyFactory } from 'alchemist/factory/ProxyFactory.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { IAludel } from './aludel/IAludel.sol';
import { InstanceRegistry } from "alchemist/factory/InstanceRegistry.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract AludelFactory is Ownable, InstanceRegistry {

	using EnumerableSet for EnumerableSet.AddressSet;

	struct Program {
		address deployedAddress;
		uint32 templateId;
		uint64 creation;

		string name;
		string description;		
	}

	struct TemplateData {
		address template;
		string title;
		string description;
	}

    /// @notice array of template datas
	/// todo : do we want to have any kind of control over this array? 
	TemplateData[] private _templates;

	Program[] private _programs;

    /// @dev event emitted every time a new aludel is spawned
	event AludelSpawned(address aludel);

	error InvalidTemplate();

    /// @notice perform a minimal proxy deploy
    /// @param templateId the number of the template to launch
	/// @param name the string represeting the program's name
	/// @param description the string describing the program or ipfs hash
    /// @param data the calldata to use on the new aludel initialization
    /// @return aludel the new aludel deployed address.
	function launch(
		uint256 templateId,
		string memory name,
		string memory description,
		bytes calldata data
	) public returns (address aludel) {
        // get the aludel template's data
		TemplateData memory template = _templates[templateId];

		// create clone and initialize
		aludel = ProxyFactory._create(
            template.template,
            abi.encodeWithSelector(IAludel.initialize.selector, data)
        );
		
		// add program's data to the array or programs
		_programs.push(Program({
			deployedAddress: aludel,
			templateId: uint32(templateId),
			creation: uint64(block.timestamp),
			name: name,
			description: description
		}));

		// emit event
		emit AludelSpawned(aludel);

		// explicit return
		return aludel;
	}

	/// @notice adds a new template to the factory
	function addTemplate(address template, string memory title, string memory description) public onlyOwner {
		// do we need any other checks here?
		if (template == address(0)) {
			revert InvalidTemplate();
		}

		// add template data to the array of templates
		_templates.push(TemplateData({
			template: template,
			title: title,
			description: description
		}));

        // register instance
		_register(template);
	}

	function getTemplate(uint256 templateId) public view returns (TemplateData memory) {
		return _templates[templateId];
	}

	function getTemplates() external view returns (TemplateData[] memory) {
		return _templates;
	}

	function getProgram(uint256 programId) external view returns (Program memory) {
		return _programs[programId];
	}

	function getPrograms() external view returns (Program[] memory) {
		return _programs;
	}

}
