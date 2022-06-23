import { AbiCoder } from "@ethersproject/abi";
import { parseEther } from "@ethersproject/units";
import { Wallet } from "@ethersproject/wallet";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import { deployments, ethers, getNamedAccounts, network, run } from "hardhat";
import { DeployedContract } from "hardhat-deploy/dist/types";
import { Aludel, AludelFactory, AludelFactory__factory, Crucible, CrucibleFactory, ERC20, InstanceRegistry__factory, MockERC20, PowerSwitchFactory, PowerSwitchFactory__factory, PowerSwitch__factory, RewardPoolFactory } from "../typechain-types";
import { DAYS, ETHER, revertAfter, signPermission } from "./utils";
import {AddressZero} from "@ethersproject/constants"


const { expectRevert } = require('@openzeppelin/test-helpers');

describe("Aludel factory", function () {

  let factory: AludelFactory
  let rewardPoolFactory: RewardPoolFactory
  let powerSwitchFactory: PowerSwitchFactory
  
  let crucibleFactory: CrucibleFactory

  let admin: SignerWithAddress
  let user: SignerWithAddress
  let anotherUser: SignerWithAddress

  // revertAfter()

  const get = async (name: string) => {
    const signer = (await ethers.getSigners())[0]
    const deployed = await deployments.get(name)
    return ethers.getContractAt(deployed.abi, deployed.address, signer);
  }

  this.beforeAll(async function() {

    await deployments.run()

    const signers = await ethers.getSigners()
    admin = signers[0]
    user = signers[1]
    anotherUser = signers[2]

    const { deployer, dev } = await getNamedAccounts()

    crucibleFactory = await ethers.getContractAt(
      'alchemist/contracts/crucible/CrucibleFactory.sol:CrucibleFactory',
      '0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56'
    ) as CrucibleFactory

    rewardPoolFactory = await deployContract(
      'RewardPoolFactory',
      'alchemist/contracts/aludel/RewardPoolFactory.sol:RewardPoolFactory'
    ) as RewardPoolFactory;

  })

  async function deploy(name: string, args ?: any[]): Promise<Contract> {
    return deployContract(name, name, args)
  }

  async function deployContract(name: string, contract: string, args ?: any[]): Promise<Contract> {
    const { deployer, dev } = await getNamedAccounts()
    
    const deployed = await deployments.getOrNull(name)

    if (!deployed) {
      await deployments.deploy(name, {
        from: deployer,
        args: args,
        log: true,
        contract,
        deterministicDeployment: false
      });
    }

    return get(name)
  }

  async function deployMockERC20(name: string): Promise<MockERC20> {
    const { deployer, dev } = await getNamedAccounts()
    return await (
      deployContract(name, 'MockERC20', [admin.address, parseEther('1')])
    ) as MockERC20
  }

  this.beforeEach(async function() {

    factory = (await deploy('AludelFactory', [admin.address, 100])) as AludelFactory
    powerSwitchFactory = (await deploy('PowerSwitchFactory')) as PowerSwitchFactory
    // factory = await get('AludelFactory') as AludelFactory;
    // powerSwitchFactory = await get('PowerSwitchFactory') as PowerSwitchFactory;

  })

  describe("aludel launch", async function () {

    let signer: SignerWithAddress
    let deployed: DeployedContract
    let aludelTemplate: Aludel;

    let stakingToken: MockERC20
    let rewardToken: MockERC20
    let bonusTokenA: MockERC20
    let bonusTokenB: MockERC20

    let aludel: Aludel
    let aludelAddress: string

    async function launchAludel(
      template: string,
      name: string,
      url: string,
      startTime: number,
      vaultFactory: string,
      bonusTokens: string[],
      owner: string,
      params: any
    ): Promise<Aludel> {
      let tx = await factory.launch(
        template, name, url,
        startTime, vaultFactory,
        bonusTokens,
        owner, params
      )
      let receipt = await tx.wait()
  
      let event = receipt.events?.find(
        event => event.address == factory.address && event.event == 'InstanceAdded'
      )
      const aludelAddress = event?.args!.instance
      const aludel = aludelTemplate.attach(aludelAddress) as Aludel

      return aludel
    }

    function getAludelInitParams(
      floor: number, ceiling: number, duration: number
    ) {
      const params = new AbiCoder().encode(
        ['address', 'address', 'address', 'address', 'uint256', 'uint256', 'uint256'],
        [
          rewardPoolFactory.address, powerSwitchFactory.address,
          stakingToken.address, rewardToken.address,
          floor, ceiling, duration
        ]
      )
      return params
    }

    this.beforeEach(async function() {
      signer = (await ethers.getSigners())[0]
      const deployed = await deployments.get('Aludel')
      aludelTemplate = await ethers.getContractAt(
        'src/contracts/aludel/Aludel.sol:Aludel',
        deployed.address,
        signer
      ) as Aludel;
  
      stakingToken = await deployMockERC20('StakingToken')
      rewardToken = await deployMockERC20('RewardToken')
  
      bonusTokenA = await deployMockERC20('BonusTokenA')
      bonusTokenB = await deployMockERC20('BonusTokenB')
  
      await rewardToken.mint(admin.address, ETHER(1))
  
      const params = getAludelInitParams(1, 10, DAYS(1))
  
      // const startTime = BigNumber.from(Date.now()).div(1000)
      const startTime = 0
  
      aludel = await launchAludel(
        aludelTemplate.address,
        "program test",
        "https://staking.token",
        startTime,
        crucibleFactory.address,
        [bonusTokenA.address, bonusTokenB.address],
        admin.address,
        params
      )
      
      await rewardToken.connect(admin).approve(aludel.address, ETHER(1))
  
      await aludel.connect(admin).fund(ETHER(1), DAYS(1))
    })
    it("test full", async function () {
      
      // const aludelTemplate = await get('Aludel') as Aludel 
    
      // expect(await aludel.isStarted()).to.be.true
  
      let receipt = await (await crucibleFactory.connect(admin)["create()"]()).wait();
      let event = receipt.events?.find(
        event => event.address == crucibleFactory.address && event.event == 'InstanceAdded'
      )
      const crucibleAddress = event?.args!.instance
  
      const crucible = await ethers.getContractAt('Crucible', crucibleAddress) as Crucible
  
      await stakingToken.connect(admin).mint(crucible.address, ETHER(1))
  
      const signerWallet = Wallet.fromMnemonic(process.env.DEV_MNEMONIC || '')
      let tx = await aludel.stake(
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
      await tx.wait()
  
      await network.provider.send("evm_increaseTime", [DAYS(1)])
  
      await aludel.unstakeAndClaim(
        crucible.address,
        ETHER(1),
        await signPermission(
          'Unlock',
          crucible,
          signerWallet,
          aludel.address,
          stakingToken.address,
          ETHER(1),
          1
        )
      )
    });


    describe("admin functions", async function () {
      it("templates", async function() {
        const template2 = await deployContract('Aludel2', 'src/contracts/aludel/Aludel.sol:Aludel')
        await factory.addTemplate(template2.address, 'aludel 2', false)
        let templateData = await factory.getTemplate(template2.address)
        expect(templateData.disabled).to.be.false
        expect(templateData.name).equals('aludel 2')
        await factory.updateTemplate(template2.address, true)
        templateData = await factory.getTemplate(template2.address)
        expect(templateData.disabled).to.be.true

        let templates = await factory.getTemplates()
      })
      it("programs", async function() {
        let program = await factory.getProgram(aludel.address)
        expect(program.name, 'program test')
        expect(program.stakingTokenUrl, 'https://staking.token')
        expect(program.stakingTokenUrl, await factory.getStakingTokenUrl(aludel.address))
        await factory.updateName(aludel.address, 'changed')
        await factory.updateStakingTokenUrl(aludel.address, 'https://invalid.url')
        program = await factory.getProgram(aludel.address)
        expect(program.name, 'changed')
        expect(program.stakingTokenUrl, 'https://invalid.url')
        expect(program.stakingTokenUrl, await factory.getStakingTokenUrl(aludel.address))
      })

      it("add program", async function() {
        const template2 = await deployContract('Aludel2', 'src/contracts/aludel/Aludel.sol:Aludel')

        await factory.addProgram(
          AddressZero, template2.address, "program added manually", "https://new.url", 0
        )
        let program = await factory.getProgram(AddressZero)
        expect(program.name, 'program added manually')
        expect(program.stakingTokenUrl, 'https://new.url')
      })

      it("delist program", async function() {

        await factory.delistProgram(aludel.address)
        // await expectRevert(
        //   factory.delistProgram(aludel.address),
        //   'InstanceNotRegistered()'
        // )  
        await factory.addProgram(
          aludel.address, aludelTemplate.address, "program added manually", "https://new.url", 0
        )
        let program = await factory.getProgram(aludel.address)
        expect(program.name, 'program added manually')
        expect(program.stakingTokenUrl, 'https://new.url')
      })

      it("funding fee", async function() {
        let bps = await factory.feeBps()
        let receiver = await factory.feeRecipient()
        expect(bps.toNumber()).eq(100)
        expect(receiver).equals(admin.address)
        await factory.setFeeBps(200)
        await factory.setFeeRecipient(AddressZero)
        bps = await factory.feeBps()
        receiver = await factory.feeRecipient()
        expect(bps.toNumber()).eq(200)
        expect(receiver).equals(AddressZero)
      })

    })

  }) 

  it("")


});
