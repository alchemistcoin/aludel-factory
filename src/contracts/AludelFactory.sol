// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import { ProxyFactory } from 'alchemist/factory/ProxyFactory.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { IAludel } from './aludel/IAludel.sol';
import { InstanceRegistry } from "./libraries/InstanceRegistry.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract AludelFactory is Ownable, InstanceRegistry {

	using EnumerableSet for EnumerableSet.AddressSet;

	struct ProgramData {
		address template;
		uint64 creation;
		string url;
		string name;
	}

	struct TemplateData {
		address template;
		string title;
		string description;
	}

    /// @notice set of template addresses
	EnumerableSet.AddressSet private _templates;

	/// @notice address => ProgramData mapping
	mapping(address => ProgramData) private _programs;

	/// @dev emitted when a new template is added 
	event TemplateAdded(address template);
	/// @dev emitted when an URL program is changed
	event URLChanged(address program, string url);

	error InvalidTemplate();
	error TemplateNotRegistered();
	error TemplateAlreadyAdded();
	error ProgramAlreadyRegistered();

    /// @notice perform a minimal proxy deploy
    /// @param template the number of the template to launch
	/// @param name the string represeting the program's name
	/// @param url the program's url
    /// @param data the calldata to use on the new aludel initialization
    /// @return aludel the new aludel deployed address.
	function launch(
		address template,
		string memory name,
		string memory url,
		bytes calldata data
	) public returns (address aludel) {

		// check if template address is registered
		if (!_templates.contains(template)) {
			revert TemplateNotRegistered();
		}

		// create clone and initialize
		aludel = ProxyFactory._create(
            template,
            abi.encodeWithSelector(IAludel.initialize.selector, data)
        );

		// add program's data to the storage 
		_programs[aludel] = ProgramData({
			creation: uint64(block.timestamp),
			template: template,
			name: name,
			url: url
		});

		// register aludel instance
		_register(aludel);
		
		// explicit return
		return aludel;
	}

	/// @notice adds a new template to the factory
	function addTemplate(address template) public onlyOwner {

		if (template == address(0)) {
			revert InvalidTemplate();
		}

		if (!_templates.add(template)) {
			revert TemplateAlreadyAdded();
		}

		emit TemplateAdded(template);
	}

	/// @notice updates the url for the given program
	function updateURL(address program, string memory newUrl) external {
		require(isInstance(program));
		require(msg.sender == owner());

		_programs[program].url = newUrl;
	}

	function getStakingTokenUrl(address program) external view returns (string memory) {
		return _programs[program].url;
	}

	/// @notice retrieves a program's data
	function getProgram(address program) external view returns (ProgramData memory) {
		return _programs[program];
	}

	/// @notice allow owner to add a program manually
	///         this allows to have pre-aludelfactory programs to be stored onchain
	function addProgram(
		address program,
		address template,
		string memory name,
		string memory url
	) external onlyOwner {

		// register aludel instance, if program is already registered this will revert
		_register(program);

		// add program's data to the storage 
		_programs[program] = ProgramData({
			creation: uint64(block.timestamp),
			template: template,
			name: name,
			url: url
		});
	}

	/// @notice removes program as a registered instance of the factory.
	function delistProgram(address program) external onlyOwner {
		_unregister(program);
	}

}
