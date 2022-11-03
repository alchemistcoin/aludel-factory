import { TypedDataField } from "@ethersproject/abstract-signer";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {
  BigNumber,
  BigNumberish,
  BytesLike,
  Contract,
  Signer,
  Wallet,
} from "ethers";
import { ethers, network } from "hardhat";
import { parseEther } from "ethers/lib/utils";
import { splitSignature } from "ethers/lib/utils";

const DAY = 60 * 60 * 24;

export async function getTimestamp() {
  return (await ethers.provider.getBlock("latest")).timestamp;
}

export async function increaseTime(seconds: number) {
  const time = await getTimestamp();
  // instead of using evm_increaseTime, we can pass in the timestamp
  // the next block should setup as the mining time
  const expectedEndTime = time + seconds - 1;
  await network.provider.request({
    method: "evm_mine",
    params: [expectedEndTime],
  });
  if (expectedEndTime !== (await getTimestamp())) {
    throw new Error("evm_mine failed");
  }
}

export async function deployContract(name: string, args: Array<any> = []) {
  const factory = await ethers.getContractFactory(name);
  const contract = await factory.deploy(...args);
  return contract.deployed();
}

export async function deployMist(admin: SignerWithAddress) {
  const factory = await ethers.getContractFactory("Alchemist");

  // todo : use the token manager
  const tokenManager = await (
    await ethers.getContractFactory("TokenManager", admin)
  ).deploy();

  const now = new Date();
  const mist = await factory.deploy(
    admin.address,
    admin.address,
    1000,
    BigNumber.from(14).mul(DAY),
    BigNumber.from(60).mul(DAY),
    parseEther("1000"),
    Math.round(now.getTime() / 1000)
  );

  await mist.connect(admin);
  const initialSupply = await mist.balanceOf(admin.address);

  return {
    mist,
    initialSupply,
  };
}

export async function deployERC20(
  owner: SignerWithAddress,
  supply: BigNumberish
) {
  const token = await deployContract(
    "src/contracts/mocks/MockERC20.sol:MockERC20",
    [owner.address, supply]
  );
  await token.mint(owner.address, supply);
  return token;
}

export async function deployAludel(args: Array<any>) {
  const factory = await ethers.getContractFactory("Aludel");
  return factory.deploy(...args);
}

export async function deployAludelV2(args: Array<any>) {
  const factory = await ethers.getContractFactory("AludelV2");
  return factory.deploy(...args);
}

export async function createInstance(
  instanceName: string,
  factory: Contract,
  signer: Signer,
  args: string = "0x"
) {
  // get contract class
  const instanceFactory = ethers.getContractFactory(instanceName, signer);
  const instance = (await instanceFactory).attach(
    await factory.connect(signer).callStatic["create(bytes)"](args)
  );
  // deploy vault
  await factory.connect(signer)["create(bytes)"](args);
  // return contract class
  return instance;
}

export async function create2Instance(
  instanceName: string,
  factory: Contract,
  signer: Signer,
  salt: BytesLike,
  args: string = "0x"
) {
  // get contract class
  const instance = await ethers.getContractAt(
    instanceName,
    await factory
      .connect(signer)
      .callStatic["create2(bytes,bytes32)"](args, salt)
  );
  // create vault
  await factory.connect(signer)["create2(bytes,bytes32)"](args, salt);
  // return contract class
  return instance;
}
export const signPermitEIP2612ERC721 = async (
  owner: Wallet,
  token: Contract,
  spenderAddress: string,
  tokenId: BigNumberish,
  deadline: BigNumberish,
  nonce?: BigNumberish
) => {
  // get nonce
  nonce = nonce || (await token.nonces(owner.address));
  // get chainId
  const chainId = (await token.provider.getNetwork()).chainId;
  // get domain
  const domain = {
    name: token.name(),
    version: "1",
    chainId: chainId,
    verifyingContract: token.address,
  };
  // get types
  const types = {} as Record<string, TypedDataField[]>;
  types["Permit"] = [
    { name: "owner", type: "address" },
    { name: "spender", type: "address" },
    { name: "tokenId", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ];
  // get values
  const values = {
    owner: owner.address,
    spender: spenderAddress,
    tokenId: tokenId,
    nonce: nonce,
    deadline: deadline,
  };
  // sign permission
  // todo: add fallback if wallet does not support eip 712 rpc
  const signedPermission = await owner._signTypedData(domain, types, values);
  // split signature
  const sig = splitSignature(signedPermission);
  // return
  return [
    values.owner,
    values.spender,
    values.tokenId,
    values.deadline,
    sig.v,
    sig.r,
    sig.s,
  ];
};

export const signNFTPermission = async (
  method: string,
  vault: Contract,
  owner: Wallet,
  delegateAddress: string,
  tokenAddress: string,
  tokenId: BigNumberish,
  vaultNonce?: BigNumberish,
  chainId?: BigNumberish
) => {
  // get nonce
  vaultNonce = vaultNonce !== undefined ? vaultNonce : await vault.getNonce();
  // get chainId
  chainId = chainId || (await vault.provider.getNetwork()).chainId;
  // craft permission
  const domain = {
    name: "UniversalVault",
    version: "1.0.0",
    chainId,
    verifyingContract: vault.address,
  };
  const types = {} as Record<string, TypedDataField[]>;
  types[method] = [
    { name: "delegate", type: "address" },
    { name: "token", type: "address" },
    { name: "tokenId", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ];

  const value = {
    delegate: delegateAddress,
    token: tokenAddress,
    tokenId,
    nonce: vaultNonce,
  };
  // sign permission
  const signedPermission = await owner._signTypedData(domain, types, value);
  // return
  return signedPermission;
};

export const signERC1155Permission = async (
  method: string,
  vault: Contract,
  owner: Wallet,
  delegateAddress: string,
  tokenAddress: string,
  id: BigNumberish,
  amount: BigNumberish,
  vaultNonce?: BigNumberish,
  chainId?: BigNumberish
) => {
  // get nonce
  vaultNonce = vaultNonce !== undefined ? vaultNonce : await vault.getNonce();
  // get chainId
  chainId = chainId || (await vault.provider.getNetwork()).chainId;
  // craft permission
  const domain = {
    name: "UniversalVault",
    version: "1.0.0",
    chainId,
    verifyingContract: vault.address,
  };
  const types = {} as Record<string, TypedDataField[]>;
  types[method] = [
    { name: "delegate", type: "address" },
    { name: "token", type: "address" },
    { name: "id", type: "uint256" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ];

  const value = {
    delegate: delegateAddress,
    token: tokenAddress,
    id,
    amount,
    nonce: vaultNonce,
  };
  // sign permission
  const signedPermission = await owner._signTypedData(domain, types, value);
  // return
  return signedPermission;
};

export const transferNFT = async (
  nft: Contract,
  signer: Signer,
  owner: string,
  recipient: string,
  tokenId: string
) => {
  return nft
    .connect(signer)
    ["safeTransferFrom(address,address,uint256)"](owner, recipient, tokenId);
};

export const ERC1271_VALID_SIG = "0x1626ba7e";
export const ERC1271_INVALID_SIG = "0xffffffff";
export const ETHER = ethers.utils.parseEther("1");
