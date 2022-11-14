import chai, { expect } from "chai";
import { AbiCoder } from "ethers/lib/utils";
import { deployments, ethers, run } from "hardhat";
import {
  AludelFactory,
  Aludel,
  CrucibleFactory,
  MockERC20,
  PowerSwitchFactory,
  RewardPoolFactory,
} from "../typechain-types";
import { GEYSER_V2_VANITY_ADDRESS } from "../constants";
import chaiAsPromised from "chai-as-promised";
import { DAYS } from "./utils";
chai.use(chaiAsPromised);

describe("Aludel factory deployments", function () {
  describe("WHEN deploying a template set", () => {
    let factory: AludelFactory;
    beforeEach(async () => {
      await deployments.fixture(["templates"], {
        keepExistingDeployments: true,
      });
      const deployedFactory = await deployments.get("AludelFactory");
      factory = (await ethers.getContractAt(
        deployedFactory.abi,
        deployedFactory.address
      )) as AludelFactory;
    });
    it("THEN GeyserV2 and AludelV1 reserved template addresses are added in a disabled state", async () => {
      const geyserv2 = await factory.getTemplate(
        "0x00000000000000000000000000000000be15efb2"
      );
      expect(geyserv2.disabled).to.be.true;
      expect(geyserv2.name).to.be.equal("GeyserV2");
      const aludelv1 = await factory.getTemplate(
        "0x00000000000000000000000000000000a1fde1b1"
      );
      expect(aludelv1.disabled).to.be.true;
      expect(aludelv1.name).to.be.equal("AludelV1");
    });
    it("AND an Aludel is added as an enabled template", async () => {
      const aludelDeployment = await deployments.get("AludelV2");
      const aludelTemplate = await factory.getTemplate(
        aludelDeployment.address
      );
      expect(aludelTemplate.disabled).to.be.false;
      expect(aludelTemplate.name).to.be.equal("AludelV2");
    });

    async function deployMockERC20(name: string): Promise<MockERC20> {
      const factory = await ethers.getContractFactory("MockERC20");
      return (await factory.deploy(name, "MockERC20")) as MockERC20;
    }
    describe("GIVEN a preexisting program", () => {
      let preexistingProgram: Aludel;
      beforeEach(async () => {
        const ethersFactory = await ethers.getContractFactory(
          "src/contracts/aludel/AludelV2.sol:AludelV2"
        );
        preexistingProgram = (await ethersFactory.deploy()) as Aludel;
      });

      describe("WHEN adding it with the add-program task, AND passing al parameters", () => {
        beforeEach(async () => {
          await run("add-program", {
            program: preexistingProgram.address,
            template: GEYSER_V2_VANITY_ADDRESS,
            name: "some name",
            stakingTokenUrl: "http://buy.here",
            startTime: 69,
          });
        });
        it("THEN it is listed", async () => {
          const program = await factory.programs(preexistingProgram.address);
          expect(program.name).to.eq("some name");
        });
      });

      it("WHEN adding it with the add-program task, AND omitting the template THEN it fails because the template is not optional", async () => {
        await expect(
          run("add-program", {
            program: preexistingProgram.address,
            name: "some name",
            stakingTokenUrl: "http://buy.here",
            startTime: 69,
          })
        ).to.be.rejectedWith(
          "HH306: The 'template' parameter expects a value, but none was passed"
        );
      });

      describe("WHEN adding it with the add-program task, AND omitting the startTime", () => {
        beforeEach(async () => {
          await run("add-program", {
            program: preexistingProgram.address,
            template: GEYSER_V2_VANITY_ADDRESS,
            name: "some name",
            stakingTokenUrl: "http://buy.here",
          });
        });
        it("THEN the current timestamp is used", async () => {
          const program = await factory.programs(preexistingProgram.address);
          const currentTime = Date.now() / 1000;
          // we have to use a difference of a stupid amount of seconds, since
          // the optional param in the task is evaluated when the task is
          // registered, and when running the entire test suite, there could be
          // a large difference with the time at which the test is run. This
          // should not be relevant for actual task runs, since the task is run
          // just a few milliseconds after being registered
          expect(program.startTime.toNumber()).to.be.lt(currentTime);
          expect(program.startTime.toNumber()).to.be.gt(currentTime - 400);
        });
      });
    });

    describe("GIVEN a PowerSwitchFactory, a CrucibleFactory, a RewardPoolFactory, and some other stuff", () => {
      let powerSwitchFactory: PowerSwitchFactory;
      let crucibleFactory: CrucibleFactory;
      let rewardPoolFactory: RewardPoolFactory;
      let stakingToken: MockERC20;
      let rewardToken: MockERC20;
      beforeEach(async () => {
        await deployments.fixture(
          ["PowerSwitchFactory", "CrucibleFactory", "RewardPoolFactory"],
          { keepExistingDeployments: true }
        );
        const powerSwitchDeployment = await deployments.get(
          "PowerSwitchFactory"
        );
        powerSwitchFactory = (await ethers.getContractAt(
          powerSwitchDeployment.abi,
          powerSwitchDeployment.address
        )) as PowerSwitchFactory;
        const crucibleFactoryDeployment = await deployments.get(
          "CrucibleFactory"
        );
        crucibleFactory = (await ethers.getContractAt(
          crucibleFactoryDeployment.abi,
          crucibleFactoryDeployment.address
        )) as CrucibleFactory;
        const rewardPoolFactoryDeployment = await deployments.get(
          "RewardPoolFactory"
        );
        rewardPoolFactory = (await ethers.getContractAt(
          rewardPoolFactoryDeployment.abi,
          rewardPoolFactoryDeployment.address
        )) as RewardPoolFactory;
        [stakingToken, rewardToken] = await Promise.all([
          deployMockERC20("STAKE"),
          deployMockERC20("REWARD"),
        ]);
      });

      describe("AND GIVEN a valid template address and deploy params", async () => {
        let templateAddress: string;
        let deployParams: string;

        beforeEach(async () => {
          const aludelTemplateDeployment = await deployments.get("AludelV2");
          templateAddress = aludelTemplateDeployment.address;

          deployParams = new AbiCoder().encode(
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
              rewardPoolFactory.address,
              powerSwitchFactory.address,
              stakingToken.address,
              rewardToken.address,
              1,
              10,
              DAYS(1),
            ]
          );
        });
        it("THEN an aludel can be launched manually", async () => {
          const tx = await factory.launch(
            templateAddress,
            "program name",
            "protocol://program.url",
            0,
            crucibleFactory.address,
            [],
            await factory.owner(),
            deployParams
          );
          await tx.wait();
        });
      });
    });
  });
});
