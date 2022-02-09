import { AbiCoder } from "@ethersproject/abi";
import { formatEther, parseUnits } from "ethers/lib/utils";
import { task } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import { parseEther } from "@ethersproject/units";

export const ETHER = (amount: number = 1) => parseEther(amount.toString());
export const DAYS = (days: number = 1) => days * 60 * 60 * 24;

/*
yarn hardhat launch-program \
  --alude-factory 
  --owner
  --rewardPool 0xf016fa84d5f3a252409a63b5cb89b555a0d27ccf
  --powerSwitch 0x89d2d92eace71977dd0b159062f8ec90ea64fc24
  --stakingToken 0xCD6bcca48069f8588780dFA274960F15685aEe0e
  --rewardToken 0x88ACDd2a6425c3FaAE4Bc9650Fd7E27e0Bebb7aB
  --rewardScalingFloor 1
  --rewardScalingCeiling 10
  --rewardScalingTime 1
*/

task("launch-program")
  .addParam("aludel-factory", "address of the aludel factory")
  .addParam("owner", "address of the aludel's owner")
  .addParam("rewardPool", "address of the reward pool factory")
  .addParam("powerSwitch", "address of the power switch factory")
  .addParam("stakingToken", "address of the staking token")
  .addParam("rewardToken", "address of the reward token")
  .addParam("rewardScalingFloor", "reward scaling floor amount (in ETH)")
  .addParam("rewardScalingCeiling", "reward scaling ceiling amount (in ETH)")
  .addParam("rewardScalingTime", "duration of the reward scaling period (in days)")

  .setAction(async (args, { ethers, run, network }) => {
    // log config

    console.log("Network");
    console.log("  ", network.name);
    console.log("Task Args");
    console.log(args);

    // compile

    await run("compile");

    // get signer

    const signer = (await ethers.getSigners())[0];
    console.log("Signer");
    console.log("  at", signer.address);
    console.log("  ETH", formatEther(await signer.getBalance()));

    // deploy contracts
    const mintFee = parseEther(args.fee);

    const factory = await ethers.getContractAt(
      "AludelFactory",
      args.aludelFactory
    );

    const params = new AbiCoder().encode(
      [
        "address",
        "address",
        "address",
        "address",
        "address",
        "uint256",
        "uint256",
        "uint256",
      ],
      [
        args.owner,
        args.rewardPool,
        args.powerSwitch,
        args.stakingToken,
        args.rewardToken,
        ETHER(args.rewardScalingFloor),
        ETHER(args.rewardScalingCeiling),
        DAYS(args.rewardScalingTime),
      ]
    );

    await (await factory.launch(0, params)).wait();

  });
