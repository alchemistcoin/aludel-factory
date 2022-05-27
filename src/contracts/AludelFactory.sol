// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.6;

import { ProxyFactory } from 'alchemist/factory/ProxyFactory.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { IAludel } from './aludel/IAludel.sol';
import { InstanceRegistry } from "./libraries/InstanceRegistry.sol";

import {EnumerableSet} from "./libraries/EnumerableSet.sol";

contract AludelFactory is Ownable, InstanceRegistry {

	using EnumerableSet for EnumerableSet.TemplateDataSet;

	struct ProgramData {
		address template;
		uint64 creation;
		string name;
		string url;
		string stakingTokenUrl;
	}

    /// @notice set of template addresses
	EnumerableSet.TemplateDataSet private _templates;

	/// @notice address => ProgramData mapping
	mapping(address => ProgramData) private _programs;

	/// @dev emitted when a new template is added 
	event TemplateAdded(address template);
	/// @dev emitted when a template is updated 
	event TemplateUpdated(address template, bool disabled);

	/// @dev emitted when an URL program is changed
	event URLChanged(address program, string url);
	event StakingTokenURLChanged(address program, string url);

	error InvalidTemplate();
	error TemplateNotRegistered();
	error TemplateDisabled();
	error TemplateAlreadyAdded();
	error ProgramAlreadyRegistered();

    /// @notice perform a minimal proxy deploy of a predefined aludel template
    /// @param template the number of the template to launch
	/// @param name the string represeting the program's name
	/// @param url the program's url
    /// @param data the calldata to use on the new aludel initialization
    /// @return aludel the new aludel deployed address.
	function launch(
		address template,
		string memory name,
		string memory url,
		string memory stakingTokenUrl,
		bytes calldata data
	) public returns (address aludel) {

		// revert when template address is not registered
		if (!_templates.contains(template)) {
			revert TemplateNotRegistered();
		}

		// revert when template is disabled
		if (_templates.at(template).disabled) {
			revert TemplateDisabled();
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
			url: url,
			stakingTokenUrl: stakingTokenUrl
		});

		// register aludel instance
		_register(aludel);
		
		// explicit return
		return aludel;
	}

	/* admin */

	/// @notice adds a new template to the factory
	function addTemplate(address template) public onlyOwner returns (uint256 templateIndex) {

		if (template == address(0)) {
			revert InvalidTemplate();
		}

		// create template data
		EnumerableSet.TemplateData memory data = EnumerableSet.TemplateData({
			template: template,
			disabled: false
		});

		if (!_templates.add(data)) {
			revert TemplateAlreadyAdded();
		}

		emit TemplateAdded(template);

		return _templates.length();
	}

	function disableTemplate(address template, bool disabled) external onlyOwner {
		if (!_templates.contains(template)) {
			revert InvalidTemplate();
		}
		// update disable value for the given template
		require(_templates.update(template, disabled));
		// emit event
		emit TemplateUpdated(template, disabled);
	}

	/// @notice updates the url for the given program
	function updateURL(address program, string memory newUrl) external {
		// check if the address is already registered
		require(isInstance(program));
		// only owner
		require(msg.sender == owner());
		// update storage
		_programs[program].url = newUrl;
		// emit event
		emit URLChanged(program, newUrl);
	}

	/// @notice updates the stakingTokenUrl for a given program
	function updateStakingTokenUrl(address program, string memory newUrl) external {
		// check if the address is already registered
		require(isInstance(program));
		// only owner
		require(msg.sender == owner());
		// update storage
		_programs[program].stakingTokenUrl = newUrl;
		// emit event
		emit StakingTokenURLChanged(program, newUrl);
	}

	/// @notice allow owner to manually add a program
	/// @dev this allows to have pre-aludelfactory programs to be stored onchain
	function addProgram(
		address program,
		address template,
		string memory name,
		string memory url,
		string memory stakingTokenUrl
	) external onlyOwner {

		// register aludel instance
		// if program is already registered this will revert
		_register(program);

		// add program's data to the storage 
		_programs[program] = ProgramData({
			creation: uint64(block.timestamp),
			template: template,
			name: name,
			url: url,
			stakingTokenUrl: stakingTokenUrl
		});
	}

	/// @notice removes program as a registered instance of the factory.
	function delistProgram(address program) external onlyOwner {
		_unregister(program);
	}

	/* getters */

	/// @notice retrieves the program's url
	function getStakingTokenUrl(address program) external view returns (string memory) {
		return _programs[program].stakingTokenUrl;
	}

	/// @notice retrieves a program's data
	function getProgram(address program) external view returns (ProgramData memory) {
		return _programs[program];
	}

	function getTemplates() external view returns(EnumerableSet.TemplateData[] memory) {
		return _templates.values();
	}

	function getTemplate(address template) external view returns(EnumerableSet.TemplateData memory) {
		return _templates.at(template);
	}

}
