// // SPDX-License-Identifier: GPL-3.0-only
// pragma solidity 0.7.6;

// import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// import {IFactory} from "../factory/IFactory.sol";
// import {IInstanceRegistry} from "../factory/InstanceRegistry.sol";

// import {IUniversalVault} from "./Crucible.sol";

// /// @title CrucibleFactory
// contract ICrucibleFactory is IFactory, IInstanceRegistry, IERC721 {

//     /* registry functions */

//     function isInstance(address instance) external view override returns (bool validity) {

//     function instanceCount() external view override returns (uint256 count) {

//     function instanceAt(uint256 index) external view override returns (address instance) {
//         return address(ERC721.tokenByIndex(index));
//     }

//     /* factory functions */

//     function create(bytes calldata) external override returns (address vault) {
//         return create();
//     }

//     function create2(bytes calldata, bytes32 salt) external override returns (address vault) {
//         return create2(salt);
//     }

//     function create() public returns (address vault) {
//         // create clone and initialize
//         vault = ProxyFactory._create(
//             _template,
//             abi.encodeWithSelector(IUniversalVault.initialize.selector)
//         );

//         // mint nft to caller
//         ERC721._safeMint(msg.sender, uint256(vault));

//         // emit event
//         emit InstanceAdded(vault);

//         // explicit return
//         return vault;
//     }

//     function create2(bytes32 salt) public returns (address vault) {
//         // create clone and initialize
//         vault = ProxyFactory._create2(
//             _template,
//             abi.encodeWithSelector(IUniversalVault.initialize.selector),
//             salt
//         );

//         // mint nft to caller
//         ERC721._safeMint(msg.sender, uint256(vault));

//         // emit event
//         emit InstanceAdded(vault);

//         // explicit return
//         return vault;
//     }

//     /* getter functions */

//     function getTemplate() external view returns (address template) {
//         return _template;
//     }
// }
