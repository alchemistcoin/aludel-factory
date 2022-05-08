// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import { ProxyFactory } from 'alchemist/factory/ProxyFactory.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { IAludel } from './aludel/IAludel.sol';
import { InstanceRegistry } from "alchemist/factory/InstanceRegistry.sol";

contract AludelFactory is Ownable, InstanceRegistry {

	struct TemplateData {
		address template;
		string title;
		string description;
	}

    /// @notice array of template datas
	/// todo : do we want to have any kind of control over this array? 
	TemplateData[] private _templates;

    /// @dev event emitted every time a new aludel is spawned
	event AludelSpawned(address aludel);

	error InvalidTemplate();

    /// @notice perform a minimal proxy deploy
    /// @param templateId the number of the template to launch
    /// @param data the calldata to use on the new aludel initialization
    /// @return aludel the new aludel deployed address.
	function launch(uint256 templateId, bytes calldata data) public returns (address aludel) {
        // get the aludel template's data
		TemplateData memory template = _templates[templateId];

		// create clone and initialize
		aludel = ProxyFactory._create(
            template.template,
            abi.encodeWithSelector(IAludel.initialize.selector, data)
        );

		// emit event
		emit AludelSpawned(aludel);

		// explicit return
		return aludel;
	}

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

	function getTemplates() public view returns (TemplateData[] memory) {
		return _templates;
	}
}
