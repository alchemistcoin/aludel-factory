// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.6;

import {DSTest} from "ds-test/src/test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {Aludel} from "../contracts/aludel/Aludel.sol";
import {IAludel} from "../contracts/aludel/IAludel.sol";
import {RewardPoolFactory} from "alchemist/contracts/aludel/RewardPoolFactory.sol";
import {PowerSwitchFactory} from "../contracts/powerSwitch/PowerSwitchFactory.sol";

import {IFactory} from "alchemist/contracts/factory/IFactory.sol";

import {
    IUniversalVault,
    Crucible
} from "alchemist/contracts/crucible/Crucible.sol";
import {CrucibleFactory} from "alchemist/contracts/crucible/CrucibleFactory.sol";
import {ERC721Holder} from"@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

import {EnumerableSet} from "../contracts/libraries/EnumerableSet.sol";
import "forge-std/src/console2.sol";


contract EnumerableSetTest is DSTest {
    using EnumerableSet for EnumerableSet.TemplateDataSet;

    /// @notice set of template data
    EnumerableSet.TemplateDataSet internal templates; 

    EnumerableSet.TemplateData internal DEFAULT;

    Hevm cheats;

    mapping(bytes32 => uint256) public gasBefore;
    mapping(bytes32 => uint256) public measures;

    function assertEq(bool a, bool b) internal {    
        assertTrue(a == b);
    }

    function setUp() public {
        cheats = Hevm(HEVM_ADDRESS);

        DEFAULT = EnumerableSet.TemplateData({
            template: address(1337),
            disabled: false,
            name: 'template'
        });
    }
    

    function test_at_index() public {
        templates.add(DEFAULT);
        EnumerableSet.TemplateData memory value = templates.at(0);

        assertEq(value.template, address(1337));
        assertEq(value.disabled, false);
        assertEq(value.name, 'template');
    }

    function test_at_template() public {
        templates.add(DEFAULT);

        EnumerableSet.TemplateData memory value = templates.at(address(1337));

        assertEq(value.template, address(1337));
        assertEq(value.disabled, false);
        assertEq(value.name, 'template');
    }

    function test_contains(uint256 length) public {
        cheats.assume(length < 50);

        for (uint i = 0; i < length; i++) {
            assertTrue(templates.add(EnumerableSet.TemplateData({
                template: address(uint160(1337+i)),
                name: string(abi.encode('template', i)),
                disabled: false
            })));
            assertTrue(templates.contains(address(uint160(1337+i))));
        }

        
        assertEq(templates.length(), length);
        assertTrue(!templates.contains(address(uint160(1337+length))));
        
    }

    function _buildTemplateData(
        address template,
        bool disabled,
        string memory name
    ) internal returns (EnumerableSet.TemplateData memory) {
        return EnumerableSet.TemplateData({
            name: name,
            template: template,
            disabled: disabled
        });
    }

    function test_adding_duplicates_revert() public {
        // return true on success
        assertTrue(templates.add(DEFAULT));
        // returns false if `value.template` already exists 
        assertTrue(!templates.add(DEFAULT));

        assertEq(templates.length(), 1);
    }

    function test_add() public {
        // EnumerableSet.TemplateDataSet storage templates; 
        assertEq(templates.length(), 0);
        templates.add(DEFAULT);
        assertEq(templates.length(), 1);
    }

    function test_add_random_string(string memory name) public {
        // EnumerableSet.TemplateDataSet storage templates;
        cheats.assume(bytes(name).length > 32); 
        assertEq(templates.length(), 0);
        templates.add(EnumerableSet.TemplateData({
            template: address(uint160(1337)),
            name: name,
            disabled: false
        }));
        assertEq(templates.length(), 1);
    }

    function test_update() public {
        EnumerableSet.TemplateData memory data;
        assertTrue(!templates.contains(DEFAULT.template));
        templates.add(DEFAULT);
        data = templates.at(DEFAULT.template);
        assertEq(data.disabled, false);
        assertTrue(templates.update(DEFAULT.template, true));

        data = templates.at(DEFAULT.template);
        assertEq(data.disabled, true);        
    }

    function test_update_nonexistent() public {
        SetWrapper set = new SetWrapper();
        // this reverts as expected but i dont know how to test it
        cheats.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        set.at(address(0));
        // update nonexistent entry
        assertTrue(!set.update(address(0), true));
        assertTrue(!set.contains(address(0)));
    }

    function test_remove() public {
        // add template
        templates.add(DEFAULT);
        assertTrue(templates.contains(DEFAULT.template));
        templates.remove(DEFAULT);
    }

    function test_remove_twice() public {
        templates.add(DEFAULT);
        assertTrue(templates.contains(DEFAULT.template));
        assertTrue(templates.remove(DEFAULT));
        assertTrue(!templates.remove(DEFAULT));
    }

    function test_remove_nonexistent() public {
        // templates.add(DEFAULT);
        assertTrue(!templates.remove(DEFAULT));
    }

    function nextAddress(address addr, uint160 n) internal returns(address) {
        unchecked { 
            return address(uint160(uint160(addr) + n));
        }
    }

    function test_internal_state(address template, bool disabled, string memory name) public {
        EnumerableSet.TemplateData memory data = _buildTemplateData(template, disabled, name);

        templates.add(data);
        assertEq(templates._values.length, 1);
        assertEq(templates._indexes[data.template], 1);
        assertEq(templates._values[0].template, template);

        address template2 = nextAddress(template, 2);
        data = _buildTemplateData(template2, disabled, name);
        templates.add(data);
        // values has length 2
        assertEq(templates._values.length, 2);
        // lastest template is index 2
        assertEq(templates._indexes[data.template], 2);
        // first value remains as the original template
        assertEq(templates._values[0].template, template);
        // second value is template2
        assertEq(templates._values[1].template, template2);

        address template3 = nextAddress(template, 3);
        data = _buildTemplateData(template3, disabled, name);
        templates.add(data);
        // values has length 3
        assertEq(templates._values.length, 3);
        // value index 1 is template2, the previous
        assertEq(templates._values[1].template, template2);
        // value index 2 is template3, the current
        assertEq(templates._values[2].template, template3);

        // remove template4
        address template4 = nextAddress(template, 4);
        assertEq(templates._indexes[template4], 0);
        assertTrue(!templates.remove(_buildTemplateData(template4, disabled, name)));


        // index of template2 is 2
        assertEq(templates._indexes[template2], 2);
        assertEq(templates._values[1].template, template2);
        // remove template2
        templates.remove(_buildTemplateData(template2, disabled, name));
        // now values has length 3-1=2
        assertEq(templates._values.length, 2);
        // index used by template2 is now the index of last (length-1) entry, template3
        assertEq(templates._values[1].template, templates._values[templates._values.length-1].template);
        // index for template2 should 0
        assertEq(templates._indexes[template2], 0);
    }

    function test_values() public {
        for (uint160 i = 0; i < 10000; i++) {
            templates.add(_buildTemplateData(address(i), false, "test"));
        }
        EnumerableSet.TemplateData[] memory values = templates.values();
        assertEq(values.length, 10000);
    }
}

contract SetWrapper {
    using EnumerableSet for EnumerableSet.TemplateDataSet;
    EnumerableSet.TemplateDataSet private set;

    function at(address where) public returns(EnumerableSet.TemplateData memory){
        return set.at(where);
    }
    function update(address what, bool disabled) public returns(bool){
        return set.update(what, disabled);
    }
    function contains(address template)
        public
        returns (bool)
    {
        return set.contains(template);
    }
}
