// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

contract Spy {
    bytes[] private _calls;

    fallback(bytes calldata input) external returns(bytes memory){
        _calls.push(input);
        return bytes("");
    }

    function spyWasCalled(bytes calldata input) external view returns (bool){
        for(uint i = 0; i< _calls.length; i++){
            if (keccak256(_calls[i]) == keccak256(input)){
                return true;
            }
        }
        return false;
    }
}
