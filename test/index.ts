import { AbiCoder } from "@ethersproject/abi";
import { parseEther } from "@ethersproject/units";
import { Wallet } from "@ethersproject/wallet";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import { deployments, ethers, getNamedAccounts, network, run } from "hardhat";
import { Aludel, AludelFactory, Crucible, CrucibleFactory, ERC20, MockERC20, PowerSwitchFactory, RewardPoolFactory } from "../typechain-types";
import { DAYS, ETHER, revertAfter, signPermission } from "./utils";

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

  async function deployMockERC20(name: string): Promise<Contract> {
    const { deployer, dev } = await getNamedAccounts()
    return deployContract(name, 'MockERC20', [admin.address, parseEther('1')])
  }

  this.beforeEach(async function() {
  
    factory = await get('AludelFactory') as AludelFactory;
    powerSwitchFactory = await get('PowerSwitchFactory') as PowerSwitchFactory;

  })

  it("test full", async function () {
    
    // const aludelTemplate = await get('Aludel') as Aludel 

    const signer = (await ethers.getSigners())[0]
    const deployed = await deployments.get('Aludel')
    const aludelTemplate = await ethers.getContractAt(
      'src/contracts/aludel/Aludel.sol:Aludel',
      deployed.address,
      signer
    );

    const stakingToken = await deployMockERC20('StakingToken')
    const rewardToken = await deployMockERC20('RewardToken') as MockERC20

    const bonusTokenA = await deployMockERC20('BonusTokenA')
    const bonusTokenB = await deployMockERC20('BonusTokenB')

    await rewardToken.mint(admin.address, ETHER(1))

    const params = new AbiCoder().encode(
      ['address', 'address', 'address', 'address', 'uint256', 'uint256', 'uint256'],
      [
        rewardPoolFactory.address, powerSwitchFactory.address,
        stakingToken.address, rewardToken.address,
        1, 10, DAYS(1)
      ]
    )

    // const startTime = BigNumber.from(Date.now()).div(1000)
    const startTime = 0

    let tx = await factory.launch(
      aludelTemplate.address,
      'program test',
      'https://staking.token',
      startTime,
      crucibleFactory.address,
      [bonusTokenA.address, bonusTokenB.address],
      admin.address,
      params
    )
    let receipt = await tx.wait()

    let event = receipt.events?.find(
      event => event.address == factory.address && event.event == 'InstanceAdded'
    )
    const aludelAddress = event?.args!.instance
 
    const aludel = aludelTemplate.attach(aludelAddress) as Aludel
    
    await rewardToken.connect(admin).approve(aludel.address, ETHER(1))

    await aludel.connect(admin).fund(ETHER(1), DAYS(1))

    // expect(await aludel.isStarted()).to.be.true

    receipt = await (await crucibleFactory.connect(admin)["create()"]()).wait();
    event = receipt.events?.find(
      event => event.address == crucibleFactory.address && event.event == 'InstanceAdded'
    )
    const crucibleAddress = event?.args!.instance

    const crucible = await ethers.getContractAt('Crucible', crucibleAddress) as Crucible

    await stakingToken.connect(admin).mint(crucible.address, ETHER(1))

    const signerWallet = Wallet.fromMnemonic(process.env.DEV_MNEMONIC || '')
    tx = await aludel.stake(
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
});
