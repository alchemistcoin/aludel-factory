import { AbiCoder } from "@ethersproject/abi";
import { parseEther } from "@ethersproject/units";
import { Wallet } from "@ethersproject/wallet";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";
import { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { beforeEach } from "mocha";
import { Aludel, AludelFactory, CrucibleFactory, PowerSwitchFactory, RewardPoolFactory } from "../typechain-types";
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

  before(async function() {
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

  beforeEach(async function() {
  
    factory = await get('AludelFactory') as AludelFactory;
    powerSwitchFactory = await get('PowerSwitchFactory') as PowerSwitchFactory;

  })
  
  it("test full", async function () {
    
    const aludelTemplate = await get('Aludel') as Aludel 

    const stakingToken = await deployMockERC20('StakingToken')
    const rewardToken = await deployMockERC20('RewardToken')

    const bonusTokenA = await deployMockERC20('BonusTokenA')
    const bonusTokenB = await deployMockERC20('BonusTokenB')

    const params = new AbiCoder().encode(
      ['address', 'address', 'address', 'address', 'uint256', 'uint256', 'uint256'],
      [
        rewardPoolFactory.address, powerSwitchFactory.address,
        stakingToken.address, rewardToken.address,
        1, 10, DAYS(1)
      ]
    )

    // // todo : abstract this
    let tx = await (
      await factory.launch(
        aludelTemplate.address,
        'program test',
        'https://staking.token',
        Date.now(),
        crucibleFactory.address,
        [bonusTokenA.address, bonusTokenB.address],
        admin.address,
        params))
    .wait()

    const aludelAddress = await factory.callStatic.launch(
      aludelTemplate.address,
      'program test',
      'https://staking.token',
      Date.now(),
      crucibleFactory.address,
      [bonusTokenA.address, bonusTokenB.address],
      admin.address,
      params
    )
    
    // const aludel = await ethers.getContractAt('Aludel', aludelAddress)
    const aludel = aludelTemplate.attach(aludelAddress)
    await aludel.connect(admin).fund(ETHER(1), DAYS(1))
	
    await (await crucibleFactory.connect(admin)["create()"]()).wait();
    const crucibleAddress = await crucibleFactory.connect(admin).callStatic["create()"]()

    const crucible = await ethers.getContractAt(
      'Crucible',
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
