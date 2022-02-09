import { AbiCoder } from "@ethersproject/abi";
import { parseEther } from "@ethersproject/units";
import { Wallet } from "@ethersproject/wallet";
import { expect } from "chai";
import { ethers } from "hardhat";
import { beforeEach } from "mocha";
import { AludelFactory, PowerSwitchFactory, RewardPoolFactory } from "../typechain";
import { DAYS, ETHER, signPermission } from "./utils";

describe("Aludel factory", function () {

  async function deployContract(name: string) {
    const Factory = await ethers.getContractFactory("name");
    const instance = await Factory.deploy();
    await instance.deployed() 
    return instance
  }

  let factory: AludelFactory
  let rewardPoolFactory: RewardPoolFactory
  let powerSwitchFactory: PowerSwitchFactory

  beforeEach(async function() {
    const AludelFactory = await ethers.getContractFactory("AludelFactory");
    factory = await AludelFactory.deploy();
    await factory.deployed();

    const RewardPoolFactory = await ethers.getContractFactory("RewardPoolFactory");
    rewardPoolFactory = await RewardPoolFactory.deploy();
    await rewardPoolFactory.deployed() 

    const PowerSwitchFactory = await ethers.getContractFactory("PowerSwitchFactory");
    powerSwitchFactory = await PowerSwitchFactory.deploy();
    await powerSwitchFactory.deployed()
  })
  
  it("test full", async function () {
    
    const [admin, user, anotherUser] = await ethers.getSigners()
    
    const AludelTemplate = await ethers.getContractFactory("Aludel");
    const aludelTemplate = await AludelTemplate.deploy();
    await aludelTemplate.deployed() 

    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const stakingToken = await MockERC20Factory.deploy(user.address, parseEther('1'));
    await stakingToken.deployed()
    const rewardToken = await MockERC20Factory.deploy(admin.address, parseEther('1'));

    await rewardToken.deployed()

    await factory.addTemplate(aludelTemplate.address)

    const params = new AbiCoder().encode(
      ['address', 'address', 'address', 'address', 'address', 'uint256', 'uint256', 'uint256'],
      [
        admin.address,
        rewardPoolFactory.address, powerSwitchFactory.address,
        stakingToken.address, rewardToken.address,
        1, 10, DAYS(1)
      ]
    )

    const tx = await (await factory.launch(0, params)).wait()

    const aludelAddress = await factory.callStatic.launch(0, params)
    const aludel = await ethers.getContractAt('Aludel', aludelAddress)

    await aludel.fund(ETHER(1), DAYS(1))
		
    const crucibleFactory = await ethers.getContractAt(
      "IFactory",
      "0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56"
    )
    // console.log(await (await ethers.getContractAt('InstanceRegistry', "0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56")).instanceCount())
    await crucibleFactory.connect(admin).create('0x')
    const crucibleAddress = await crucibleFactory.connect(admin).callStatic.create('0x')

    const crucible = await ethers.getContractAt(
      'ICrucible',
      crucibleAddress
      )
    
    const signerWallet = Wallet.fromMnemonic(process.env.DEV_MNEMONIC || '')
    await aludel.stake(
      crucible.address,
      ETHER(1),
      await signPermission(
        'Lock',
        crucible,
        signerWallet,
        aludel.address,
        stakingToken.address,
        ETHER(1),
        0
      )
    )

  });
});
