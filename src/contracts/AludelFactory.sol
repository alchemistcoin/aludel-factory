// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.6;

import {ProxyFactory} from "alchemist/contracts/factory/ProxyFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAludel} from "./aludel/IAludel.sol";
import {InstanceRegistry} from "./libraries/InstanceRegistry.sol";

import {EnumerableSet} from "./libraries/EnumerableSet.sol";

contract AludelFactory is Ownable, InstanceRegistry {
    using EnumerableSet for EnumerableSet.TemplateDataSet;

    struct ProgramData {
        address template;
        uint64 startTime;
        string name;
        string stakingTokenUrl;
    }

    /// @notice set of template data
    EnumerableSet.TemplateDataSet private _templates;

    /// @notice address => ProgramData mapping
    mapping(address => ProgramData) private _programs;

    /// @notice fee's recipient.
    address private _feeRecipient;
    /// @notice fee's basis point
    uint16 private _feeBps;

    /// @dev emitted when a new template is added
    event TemplateAdded(address template);

    /// @dev emitted when a template is updated
    event TemplateUpdated(address template, bool disabled);

    /// @dev emitted when a program's url is changed
    event StakingTokenURLChanged(address program, string url);

    /// @dev emitted when a program's name is changed
    event NameChanged(address program, string name);

    error InvalidTemplate();
    error TemplateNotRegistered();
    error TemplateDisabled();
    error TemplateAlreadyAdded();
    error ProgramAlreadyRegistered();


    constructor(address recipient, uint16 bps) {
        _feeRecipient = recipient;
        _feeBps = bps;
    }

    /// @notice perform a minimal proxy deploy of a predefined aludel template
    /// @param template the number of the template to launch
    /// @param name the string represeting the program's name
    /// @param stakingTokenUrl the program's url
    /// @param data the calldata to use on the new aludel initialization
    /// @return aludel the new aludel deployed address.
    function launch(
        address template,
        string memory name,
        string memory stakingTokenUrl,
        uint64 startTime,
        address vaultFactory,
        address[] memory bonusTokens,
        address ownerAddress,
        bytes calldata data
    )
        public
        returns (address aludel)
    {
        // reverts when template address is not registered
        if (!_templates.contains(template)) {
            revert TemplateNotRegistered();
        }

        // reverts when template is disabled
        if (_templates.at(template).disabled) {
            revert TemplateDisabled();
        }

        // create clone and initialize
        aludel = ProxyFactory._create(
            template,
            abi.encodeWithSelector(
                IAludel.initialize.selector,
                startTime,
                ownerAddress,
                _feeRecipient,
                _feeBps,
                data
            )
        );

        // add program's data to the storage
        _programs[aludel] = ProgramData({
            startTime: startTime,
            template: template,
            name: name,
            stakingTokenUrl: stakingTokenUrl
        });

        // register aludel instance
        _register(aludel);

        // register vault factory
        IAludel(aludel).registerVaultFactory(vaultFactory);

        uint256 bonusTokenLength = bonusTokens.length;

        // register bonus tokens
        for (uint256 index = 0; index < bonusTokenLength; ++index) {
            IAludel(aludel).registerBonusToken(bonusTokens[index]);
        }

        // transfer ownership
        Ownable(aludel).transferOwnership(ownerAddress);

        // explicit return
        return aludel;
    }

    /* admin */

    /// @notice adds a new template to the factory
    function addTemplate(address template, string memory name, bool disabled)
        public
        onlyOwner
        returns (uint256 templateIndex)
    {
        // cannot add address(0) as template
        if (template == address(0)) {
            revert InvalidTemplate();
        }

        // create template data
        EnumerableSet.TemplateData memory data = EnumerableSet.TemplateData({
            template: template,
            disabled: disabled,
            name: name
        });

        // add template to the storage
        if (!_templates.add(data)) {
            revert TemplateAlreadyAdded();
        }

        // emit event
        emit TemplateAdded(template);

        return _templates.length();
    }

    /// @notice sets a template as disable or enabled
    function updateTemplate(address template, bool disabled)
        external
        onlyOwner
    {
        if (!_templates.contains(template)) {
            revert InvalidTemplate();
        }

        // update disable value for the given template
        require(_templates.update(template, disabled));
        // emit event
        emit TemplateUpdated(template, disabled);
    }

    /// @notice updates the stakingTokenUrl for a given program
    function updateStakingTokenUrl(address program, string memory newUrl)
        external
        onlyOwner
    {
        // check if the address is already registered
        require(isInstance(program));
        // update storage
        _programs[program].stakingTokenUrl = newUrl;
        // emit event
        emit StakingTokenURLChanged(program, newUrl);
    }

    /// @notice updates the name for a given program
    function updateName(address program, string memory newName)
        external
        onlyOwner
    {
        // check if the address is already registered
        require(isInstance(program));
        // update storage
        _programs[program].name = newName;
        // emit event
        emit NameChanged(program, newName);
    }

    /// @notice manually adds a program
    /// @dev this allows onchain storage of pre-aludel factory programs
    function addProgram(
        address program,
        address template,
        string memory name,
        string memory stakingTokenUrl,
        uint64 startTime
    )
        external
        onlyOwner
    {
        // register aludel instance
        // if program is already registered this will revert
        _register(program);

        // add program's data to the storage
        _programs[program] = ProgramData({
            startTime: startTime,
            template: template,
            name: name,
            stakingTokenUrl: stakingTokenUrl
        });
    }

    /// @notice delist a program
    /// @dev removes `program` as a registered instance of the factory
    function delistProgram(address program) external onlyOwner {
        _unregister(program);
    }

    /* getters */

    /// @notice retrieves the program's url
    function getStakingTokenUrl(address program)
        external
        view
        returns (string memory)
    {
        return _programs[program].stakingTokenUrl;
    }

    /// @notice retrieves a program's data
    function getProgram(address program)
        external
        view
        returns (ProgramData memory)
    {
        return _programs[program];
    }

    /// @notice retrieves the full list of templates
    /// @dev template values is an unbounded array
    function getTemplates()
        external
        view
        returns (EnumerableSet.TemplateData[] memory)
    {
        return _templates.values();
    }

    /// @notice retrieves a template's data
    function getTemplate(address template)
        external
        view
        returns (EnumerableSet.TemplateData memory)
    {
        return _templates.at(template);
    }

    function feeRecipient() external view returns (address) {
        return _feeRecipient;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        _feeRecipient = newRecipient;
    }

    function feeBps() external view returns (uint256) {
        return _feeBps;
    }

    function setFeeBps(uint16 bps) external onlyOwner {
        _feeBps = bps;
    }
}