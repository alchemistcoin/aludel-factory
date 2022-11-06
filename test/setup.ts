import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import {
  BigNumberish,
  BytesLike,
  Contract,
  Signer,
} from "ethers";
import { ethers, network } from "hardhat";

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

export const ETHER = ethers.utils.parseEther("1");
