import { AbiCoder } from "@ethersproject/abi";
import { formatEther, getAddress, parseUnits } from "ethers/lib/utils";
import { task } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import { parseEther } from "@ethersproject/units";
import { AddressZero } from "@ethersproject/constants"

export const ETHER = (amount: number = 1) => parseEther(amount.toString());
export const DAYS = (days: number = 1) => days * 60 * 60 * 24;

task("launch-program")
  .addParam('templateId', 'address of the template to use')
  .addParam("aludelFactory", "address of the aludel factory")
  .addParam("owner", "address of the aludel's owner")
  .addParam("rewardPool", "address of the reward pool factory")
  .addParam("powerSwitch", "address of the power switch factory")
  .addParam("stakingToken", "address of the staking token")
  .addParam("rewardToken", "address of the reward token")
  .addParam("rewardScalingFloor", "reward scaling floor amount (in ETH)")
  .addParam("rewardScalingCeiling", "reward scaling ceiling amount (in ETH)")
  .addParam("rewardScalingTime", "duration of the reward scaling period (in days)")
  .addParam('name', 'the name of the program')
  .addParam('stakingTokenUrl', 'the URL of the staking token')
  .addParam('startTime', 'the start time for the program in utc timestamp (seconds)')
  .addParam('vaultFactory', 'the initial vault factory to be whitelisted')
  .addParam('bonusToken', 'address of one bonus token to be added on launch')
  .setAction(async (args, { ethers, run, network }) => {
    // log config

    console.log("Network");
    console.log("  ", network.name);
    console.log("Task Args");
    console.log(args);

    // compile

    // await run("compile");

    // get signer

    const signer = (await ethers.getSigners())[0];
    console.log("Signer");
    console.log("  at", signer.address);
    console.log("  ETH", formatEther(await signer.getBalance()));

    // get factory instance
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      args.aludelFactory
    );
    
    // encode init params
    const params = new AbiCoder().encode(
      [
        'address',
        'address',
        'address',
        'address',
        'uint256',
        'uint256',
        'uint256'
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


task('update-template')
  .addParam("aludelFactory", "address of the aludel factory")
  .addParam("template", "address of a template")
  .addFlag('disable')
  .setAction(async (args, { ethers, run, network }) => {
    // log config

    console.log("Network");
    console.log("  ", network.name);
    console.log("Task Args");
    console.log(args);

    // get signer

    const signer = (await ethers.getSigners())[0];
    console.log("Signer");
    console.log("  at", signer.address);
    console.log("  ETH", formatEther(await signer.getBalance()));

    // get factory instance
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      args.aludelFactory
    );
   
      console.log(factory)

    // deploy minimal proxy using `params` as init params
    await (
      await factory.updateTemplate(args.template, args.disable ? true : false)
    ).wait();
   
  })

task("add-template")
  .addParam("aludelFactory", "address of the aludel factory")
  .addParam("template", "address of a template")
  .addParam("name", "name of the template based on mapping object")
  .addFlag('disable', 'to set the template as disabled')
  .setAction(async (args, { ethers, run, network }) => {
    // log config

    console.log("Network");
    console.log("  ", network.name);
    console.log("Task Args");
    console.log(args);

    // get signer

    const signer = (await ethers.getSigners())[0];
    console.log("Signer");
    console.log("  at", signer.address);
    console.log("  ETH", formatEther(await signer.getBalance()));

    // get factory instance
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      args.aludelFactory
    );
   
    await (
      await factory.addTemplate(args.template, args.name)
    ).wait();

    if (args.disable) {
      await (await factory.updateTemplate(args.template, true)).wait()
    }

  });

  
task("delist-program")
  .addParam("aludelFactory", "address of the aludel factory")
  .addParam("program", "address of a program")
  .setAction(async (args, { ethers, run, network }) => {
    // log config

    console.log("Network");
    console.log("  ", network.name);
    console.log("Task Args");
    console.log(args);

    // get signer

    const signer = (await ethers.getSigners())[0];
    console.log("Signer");
    console.log("  at", signer.address);
    console.log("  ETH", formatEther(await signer.getBalance()));

    // get factory instance
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      args.aludelFactory
    );
   
    // deploy minimal proxy using `params` as init params
    await (
      await factory.delistProgram(args.program)
    ).wait();

  });


task("add-program")
  .addParam("aludelFactory", "address of the aludel factory")
  .addParam("program", "deployed address of the program")
  .addParam("template", "Optional. deployed address of the program's template", AddressZero)
  .addParam('name', 'the name of the program')
  .addParam('stakingTokenUrl', 'the URL of the staking token')
  .addParam('startTime', 'the program start time in utc timestamp format (seconds)')
  .setAction(async (args, { ethers, run, network }) => {
    // log config

    console.log("Network");
    console.log("  ", network.name);
    console.log("Task Args");
    console.log(args);

    // get signer

    const signer = (await ethers.getSigners())[0];
    console.log("Signer");
    console.log("  at", signer.address);
    console.log("  ETH", formatEther(await signer.getBalance()));

    // get factory instance
    const factory = await ethers.getContractAt(
      "src/contracts/AludelFactory.sol:AludelFactory",
      args.aludelFactory
    );
   
    // deploy minimal proxy using `params` as init params
    await (
      await factory.addProgram(
        args.program,
        args.template,
        args.name,
        args.stakingTokenUrl, 
        args.startTime
      )
    ).wait();

  });
