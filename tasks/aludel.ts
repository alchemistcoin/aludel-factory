import { AbiCoder } from "@ethersproject/abi";
import { formatEther } from "ethers/lib/utils";
import { task, types } from "hardhat/config";
import { parseEther } from "@ethersproject/units";
import { AludelFactory } from "../typechain-types";

// this function is meant to avoid polluting the tests with console output, and
// log on every other scenario
// console.log actually receives several whatevers
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const log = (...args: any[]) => {
  if (global.before === undefined) {
    console.log(...args);
  }
};

export const ETHER = (amount = 1) => parseEther(amount.toString());
export const DAYS = (days = 1) => days * 60 * 60 * 24;

task("launch-program")
  .addParam("templateId", "address of the template to use")
  .addParam("aludelFactory", "address of the aludel factory")
  .addParam("owner", "address of the aludel's owner")
  .addParam("rewardPool", "address of the reward pool factory")
  .addParam("powerSwitch", "address of the power switch factory")
  .addParam("stakingToken", "address of the staking token")
  .addParam("rewardToken", "address of the reward token")
  .addParam("rewardScalingFloor", "reward scaling floor amount (in ETH)")
  .addParam("rewardScalingCeiling", "reward scaling ceiling amount (in ETH)")
  .addParam(
    "rewardScalingTime",
    "duration of the reward scaling period (in days)"
  )
  .addParam("name", "the name of the program")
  .addParam("stakingTokenUrl", "the URL of the staking token")
  .addParam(
    "startTime",
    "the start time for the program in utc timestamp (seconds)"
  )
  .addParam("vaultFactory", "the initial vault factory to be whitelisted")
  .addParam("bonusToken", "address of one bonus token to be added on launch")
  .setAction(async (args, { ethers, network }) => {
    // log config

    log("Network");
    log("  ", network.name);
    log("Task Args");
    log(args);

    // compile

    // await run("compile");

    // get signer

    const signer = (await ethers.getSigners())[0];
    log("Signer");
    log("  at", signer.address);
    log("  ETH", formatEther(await signer.getBalance()));

    // get factory instance
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      args.aludelFactory
    );

    // encode init params
    const params = new AbiCoder().encode(
      [
        "address",
        "address",
        "address",
        "address",
        "uint256",
        "uint256",
        "uint256",
      ],
      [
        args.rewardPool,
        args.powerSwitch,
        args.stakingToken,
        args.rewardToken,
        ETHER(args.rewardScalingFloor),
        ETHER(args.rewardScalingCeiling),
        DAYS(args.rewardScalingTime),
      ]
    );

    // deploy minimal proxy using `params` as init params
    await (
      await factory.launch(
        args.templateId,
        args.name,
        args.stakingTokenUrl,
        args.startTime,
        args.vaultFactory,
        [args.bonusToken], // only supports single bonus token
        args.owner,
        params
      )
    ).wait();
  });

task("update-template", "update an already added template")
  .addParam("template", "address of the template to update")
  .addFlag("disable", "disable the template")
  .addFlag("enable", "enable the template")
  .setAction(async (args, { ethers, deployments }) => {
    if (args.enable == args.disable) {
      throw new Error("pass *either* --disable or --enable");
    }
    const factoryAddress = (await deployments.get("AludelFactory")).address;
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      factoryAddress
    );

    const templateData = await factory.getTemplate(args.template);
    log(
      `updating template ${templateData.name} at ${args.template} on factory ${factoryAddress}`
    );
    const currentlyDisabled = templateData.disabled;
    if (currentlyDisabled && args.disable) {
      throw new Error("Template is already disabled");
    } else if (!currentlyDisabled && args.enable) {
      throw new Error("Template is already enabled");
    }

    await (await factory.updateTemplate(args.template, !!args.disable)).wait();
  });

task("add-template")
  .addParam("aludelFactory", "address of the aludel factory")
  .addParam("template", "address of a template")
  .addParam("name", "name of the template based on mapping object")
  .addFlag("disable", "to set the template as disabled")
  .setAction(async (args, { ethers, network }) => {
    // log config

    log("Network");
    log("  ", network.name);
    log("Task Args");
    log(args);

    // get signer

    const signer = (await ethers.getSigners())[0];
    log("Signer");
    log("  at", signer.address);
    log("  ETH", formatEther(await signer.getBalance()));

    // get factory instance
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      args.aludelFactory
    );

    await (
      await factory.addTemplate(
        args.template,
        args.name,
        args.disabled ? true : false
      )
    ).wait();
  });

task("delist-program")
  .addParam("aludelFactory", "address of the aludel factory")
  .addParam("program", "address of a program")
  .setAction(async (args, { ethers, network }) => {
    // log config

    log("Network");
    log("  ", network.name);
    log("Task Args");
    log(args);

    // get signer

    const signer = (await ethers.getSigners())[0];
    log("Signer");
    log("  at", signer.address);
    log("  ETH", formatEther(await signer.getBalance()));

    // get factory instance
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      args.aludelFactory
    );

    // deploy minimal proxy using `params` as init params
    await (await factory.delistProgram(args.program)).wait();
  });

task("add-program", "add a pre-existing aludel to the network's aludel factory")
  .addParam("program", "deployed address of the program")
  .addParam("template", "address of the program's template")
  .addParam("name", "the name of the program")
  .addParam("stakingTokenUrl", "the URL where to buy the staking token")
  .addOptionalParam(
    "startTime",
    "the program start time in utc timestamp format (seconds). Default is now.",
    Math.floor(Date.now() / 1000), // js date is in milliseconds, not an actual unix epoch
    types.int
  )
  .setAction(
    async (args, { getNamedAccounts, ethers, network, deployments }) => {
      // get factory instance
      const factoryAddress = (await deployments.get("AludelFactory")).address;
      const factory = await ethers.getContractAt(
        "src/contracts/AludelFactory.sol:AludelFactory",
        factoryAddress
      );
      const { deployer } = await getNamedAccounts();
      log(`Adding template ${args.template} to factory ${factoryAddress}`);
      log(`  on network ${network.name} by default deployer ${deployer}`);

      await (
        await factory.addProgram(
          args.program,
          args.template,
          args.name,
          args.stakingTokenUrl,
          args.startTime
        )
      ).wait();
    }
  );

task("update-program", "update an already added template")
  .addParam("program", "address of the program to update")
  .addOptionalParam("newName", "a new name for the program. Optional.", "")
  .addOptionalParam("newUrl", "a new URL for the program. Optional.", "")
  .setAction(async (args, { ethers, deployments }) => {
    const factoryAddress = (await deployments.get("AludelFactory")).address;
    const factory = (await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      factoryAddress
    )) as AludelFactory;

    const programData = await factory.programs(args.program);
    if (args.newName.length == 0 && args.newUrl.length == 0) {
      throw new Error("pass --newName and/or --newUrl");
    }

    log(`updating program ${programData.name} on factory ${factoryAddress}`);

    if (args.newName) {
      log(`rename ${programData.name} to ${args.newName}`);
    }
    if (args.newUrl) {
      log(`update URL ${programData.name} to ${args.newName}`);
    }

    await (
      await factory.updateProgram(args.program, args.newName, args.newUrl)
    ).wait();
  });
