// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import { ProxyFactory } from './factory/ProxyFactory.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { IAludel } from './aludel/IAludel.sol';

contract AludelFactory is Ownable {
    /// @notice array of template addresses
	address[] private _templates;

    /// @dev event emitted every time a new aludel is spawned
	event AludelSpawned(address aludel);

	constructor() Ownable() {}

    /// @notice perform a minimal proxy deploy
    /// @param templateId the number of the template to launch
    /// @param data the calldata to use on the new aludel initialization
    /// @return aludel the new aludel address.
	function launch(uint256 templateId, bytes calldata data) public returns (address aludel) {
        // get the aludel template address
		address template = _templates[templateId];

		// create clone and initialize
		aludel = ProxyFactory._create(
            template,
            abi.encodeWithSelector(IAludel.initialize.selector, data)
        );

		// emit event
		emit AludelSpawned(aludel);

		// explicit return
		return aludel;
	}

	function addTemplate(address template) public onlyOwner {
		// do we need any checks here?
        require(template != address(0), "invalid template");

		// add template to the list
		_templates.push(template);

        // bleep?
	}

	function getTemplate(uint256 templateId) public view returns (address) {
		return _templates[templateId];
	}
}
